import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'login_log.dart';
import 'net_client.dart';

/// 原生登录 / 会话服务(基于 Cronet 浏览器内核)。
///
/// 会话 Cookie 与重定向由 Cronet 自动维护(Discuz 登录后下发的 `auth` Cookie
/// 保存在共享引擎内),因此登录成功后无需再手动携带 Cookie 即可回帖。
/// 登录态的用户名与标记额外持久化到本地,用于界面展示;真实会话由 Cronet
/// 在引擎生命周期内维持,冷启动后可调用 [checkLoggedIn] 联网核验。
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

  bool _loggedIn = false;
  String? _username;
  String? lastError;

  http.Client? _client;

  bool get isLoggedIn => _loggedIn;
  String? get username => _username;

  Future<http.Client> _http() async =>
      _client ??= await NetClient.instance.client;

  Map<String, String> _headers() => {'User-Agent': NetClient.ua};

  /// 读取本地保存的登录态(用户名 + 标记)。
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _username = sp.getString(_prefUser);
      _loggedIn = sp.getBool(_prefFlag) ?? false;
    } catch (_) {}
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

  /// 原生登录。成功返回 true 并持久化会话;失败返回 false,原因写入 [lastError]。
  Future<bool> login(
    String account,
    String password, {
    String questionId = '0',
    String answer = '',
  }) async {
    lastError = null;
    LoginLog.add('开始登录: $account');
    // 密码不落日志,只记录长度提示。
    LoginLog.add('密码长度: ${password.length} 位');
    final client = await _http();
    try {
      // 弱网/瞬时断连(ERR_CONNECTION_CLOSED)时自动重试;
      // 传输层失败代表请求未提交,重试整段(取表单 + 提交)是安全的。
      final body = await NetClient.retry(
        () async {
          final formUrl = Uri.parse(base + loginPath);
          LoginLog.add('GET 登录表单: $formUrl');
          final formPage = await client
              .get(formUrl, headers: _headers())
              .timeout(NetClient.timeout);
          final page = NetClient.decode(formPage.bodyBytes);
          LoginLog.add('表单响应 HTTP ${formPage.statusCode}, '
              '大小 ${page.length} 字符');
          final formhash = NetClient.first(
                  RegExp(r'''name="formhash"[^>]*value=['"]?([0-9a-f]{8})'''),
                  page) ??
              NetClient.first(
                  RegExp(r'''formhash\s*=\s*['"]([0-9a-f]{8})'''), page) ??
              '';
          final loginHash =
              NetClient.first(RegExp(r'loginhash=([A-Za-z0-9]+)'), page) ?? '';
          var referer = NetClient.first(
                  RegExp(r'''name="referer"[^>]*value=['"]?([^'">]+)'''), page) ??
              base;
          referer = referer
              .replaceAll('&amp;', '&')
              .replaceAll('&quot;', '"')
              .trim();
          LoginLog.add('解析: formhash=${formhash.isEmpty ? '(空)' : formhash}, '
              'loginhash=${loginHash.isEmpty ? '(空)' : loginHash}');

          final uri = Uri.parse(
              '${base}member.php?mod=logging&action=login&loginsubmit=yes'
              '${loginHash.isEmpty ? '' : '&loginhash=$loginHash'}&mobile=2');
          LoginLog.add('POST 登录: $uri');
          final resp = await client
              .post(uri, headers: _headers(), body: <String, String>{
            'formhash': formhash,
            'referer': referer,
            'fastloginfield': 'username',
            'cookietime': '31104000',
            'username': account,
            'password': password,
            'questionid': questionId,
            'answer': answer,
          }).timeout(NetClient.timeout);
          final body = NetClient.decode(resp.bodyBytes);
          LoginLog.add('登录响应 HTTP ${resp.statusCode}, 大小 ${body.length} 字符');
          return body;
        },
        onRetry: (error, attempt) =>
            LoginLog.add('传输失败,第 $attempt 次重试: $error'),
      );

      // Cronet 已自动跟随重定向:登录成功会带着 auth Cookie 进入已登录页。
      var ok = body.contains('action=logout') || body.contains(account.trim());
      if (ok) {
        LoginLog.add('响应正文含登录成功标记(action=logout / 用户名)');
      } else {
        // 拿到了响应但没有成功标记:常见于响应被压缩/跳转/截断导致漏判,
        // 登录其实可能已成功。用同一会话再抓一次首页核验登录态,比直接判失败可靠。
        LoginLog.add('响应正文未检出成功标记,改用首页二次核验登录态');
        ok = await _verifyLoggedIn(client, account);
      }

      if (ok) {
        LoginLog.add('登录判定: 成功');
        _loggedIn = true;
        _username = account.trim();
        await _save();
        return true;
      }
      lastError = _parseLoginError(body);
      LoginLog.add('登录判定: 失败 -> $lastError');
      LoginLog.add('响应片段: ${_snippet(body)}');
      return false;
    } on http.ClientException catch (e) {
      LoginLog.add('ClientException: $e');
      lastError = '网络不可用,请检查网络后重试';
      return false;
    } catch (e) {
      LoginLog.add('异常: $e');
      lastError = '网络请求失败,请检查网络后重试';
      return false;
    }
  }

  /// 用同一会话再次请求首页,通过是否出现 `action=logout` 判定真实登录态。
  Future<bool> _verifyLoggedIn(http.Client client, String account) async {
    try {
      final resp = await client
          .get(Uri.parse('${base}forum.php?mobile=2'), headers: _headers())
          .timeout(NetClient.timeout);
      final html = NetClient.decode(resp.bodyBytes);
      final ok =
          html.contains('action=logout') || html.contains(account.trim());
      LoginLog.add(
          '二次核验: HTTP ${resp.statusCode}, 大小 ${html.length}, 结果=$ok');
      return ok;
    } catch (e) {
      LoginLog.add('二次核验请求失败: $e');
      return false;
    }
  }

  /// 截取响应正文开头的少量内容用作诊断日志,避免日志过大、泄露过多信息。
  static String _snippet(String body, {int max = 200}) {
    final s = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= max ? s : s.substring(0, max) + '…';
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
    await _save();
  }

  /// 原生回帖。成功返回 null;失败返回提示文本(中文)。
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

  static String _parseLoginError(String body) {
    if (body.contains('密码错误次数过多') || body.contains('次数过多')) {
      return '该账号触发登录保护,请15分钟后重试';
    }
    if (body.contains('验证码')) return '需要输入验证码,请稍后在网页端登录';
    if (body.contains('操作频繁') || body.contains('过快')) {
      return '操作频繁,请稍后再试';
    }
    if (body.contains('来路不正确') || body.contains('无效')) {
      return '登录请求已过期,请重试';
    }
    if (body.contains('密码错误') || body.contains('用户名不存在')) {
      return '用户名或密码错误';
    }
    return '登录失败,请稍后重试';
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefUser, _username ?? '');
      await sp.setBool(_prefFlag, _loggedIn);
    } catch (_) {
      // 持久化失败不影响内存状态。
    }
  }
}