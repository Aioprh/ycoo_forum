import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'login_log.dart';
import 'net_client.dart';

/// 登录 / 会话服务。
///
/// 登录采用 WebView 网页登录(与 shuyuan_app 一致),登录成功后本站下发的
/// `auth` Cookie 会一并持久化,并在回帖等请求中随 Cookie 头带到服务端以
/// 维持登录态。登录态的用户名与标记额外持久化到本地用于界面展示。
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String base = 'https://www.ycoo.net/';
  static const String loginPath =
      'member.php?mod=logging&action=login&mobile=2';
  static const String logoutPath =
      'member.php?mod=logging&action=logout&mobile=2';
  static const String _prefUser = 'ycoo.session.username';
  static const String _prefFlag = 'ycoo.session.loggedIn';
  static const String _prefCookie = 'ycoo.session.cookie';

  bool _loggedIn = false;
  String? _username;
  String? _cookie;

  http.Client? _client;

  bool get isLoggedIn => _loggedIn;
  String? get username => _username;

  /// WebView 登录后保存的完整 Cookie 串(用于回帖等需要登录态的请求)。
  String? get authCookie => _cookie;

  Future<http.Client> _http() async =>
      _client ??= await NetClient.instance.client;

  Map<String, String> _headers() {
    final h = <String, String>{
      'User-Agent': NetClient.ua,
      // 补齐浏览器常用请求头,降低被站点 WAF/反爬按"脚本请求"识别的概率。
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache',
    };
    // WebView 登录后,把会话 Cookie 带上,使回帖等敏感操作保持登录态。
    if (_cookie != null && _cookie!.isNotEmpty) h['Cookie'] = _cookie!;
    return h;
  }

  /// 读取本地保存的登录态(用户名 + 标记 + Cookie)。
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _username = sp.getString(_prefUser);
      _loggedIn = sp.getBool(_prefFlag) ?? false;
      _cookie = sp.getString(_prefCookie);
    } catch (_) {}
  }

  /// WebView 登录成功后调用:保存用户名与会话 Cookie,标记为已登录。
  Future<void> markLoggedInFromWeb(String username, String cookie) async {
    _loggedIn = true;
    _username = username.trim().isEmpty ? null : username.trim();
    _cookie = cookie.trim().isEmpty ? null : cookie.trim();
    LoginLog.instance.add(
        'WebView 登录成功: ${_username ?? '(未取到用户名)'}'
        '${_cookie == null ? '' : ', 已保存 Cookie(${_cookie!.length} 字符)'}');
    await _save();
  }

  /// 联网核验当前会话是否仍为登录态,并据此修正本地状态。
  Future<bool> checkLoggedIn() async {
    try {
      final client = await _http();
      final resp = await client
          .get(Uri.parse('${base}forum.php?mobile=2'), headers: _headers())
          .timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      final ok = body.contains('action=logout');
      if (_loggedIn != ok) {
        _loggedIn = ok;
        if (!ok) _username = null;
        await _save();
      }
      return _loggedIn;
    } catch (_) {
      return _loggedIn;
    }
  }

  /// 登出:尽力请求站点登出,并清空本地登录态。
  Future<void> logout() async {
    try {
      final client = await _http();
      await client
          .get(Uri.parse(base + logoutPath), headers: _headers())
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // 忽略网络失败,本地仍然登出。
    }
    _loggedIn = false;
    _username = null;
    _cookie = null;
    await _save();
  }

  /// 回帖。成功返回 null;失败返回提示文本(中文)。
  Future<String?> reply(int tid, int fid, String message) async {
    final text = message.trim();
    if (text.isEmpty) return '回帖内容不能为空';
    final client = await _http();
    try {
      final pageResp = await client
          .get(Uri.parse('${base}thread-$tid-1-1.html'), headers: _headers())
          .timeout(const Duration(seconds: 15));
      final page = NetClient.decode(pageResp.bodyBytes);
      final formhash = NetClient.first(
              RegExp(r'''name="formhash"[^>]*value="([0-9a-f]{8})"'''), page) ??
          '';
      final noticeauthor = NetClient.first(
              RegExp(r'''name="noticeauthor"[^>]*value="([^"]*)"'''), page) ??
          '';
      if (formhash.isEmpty) return '未取得回帖令牌(formhash)';

      // 与浏览器一致:extra 需为 URL 编码后的 `page%3D1`,故拼原始字符串。
      final url = '${base}forum.php?mod=post&action=reply&fid=$fid&tid=$tid'
          '&extra=page%3D1&replysubmit=yes&mobile=2';
      final resp = await client
          .post(Uri.parse(url), headers: _headers(), body: <String, String>{
        'formhash': formhash,
        'noticeauthor': noticeauthor,
        'message': text,
        'replysubmit': '回复',
        'listextra': 'page%3D1',
      }).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (body.contains(text)) return null; // 已跳回帖子且出现本条回帖 → 成功
      if (body.contains('登录')) return '请先登录后回帖';
      return '回帖失败,请重试';
    } catch (e) {
      return '回帖请求失败,请稍后重试';
    }
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefUser, _username ?? '');
      await sp.setBool(_prefFlag, _loggedIn);
      await sp.setString(_prefCookie, _cookie ?? '');
    } catch (_) {
      // 持久化失败不影响内存状态。
    }
  }
}