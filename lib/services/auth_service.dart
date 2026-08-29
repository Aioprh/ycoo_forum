import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'login_log.dart';
import 'net_client.dart';

/// 登录 / 会话服务。
///
/// 默认使用原生 HTTP 登录；WebView 仍作为需要额外验证码/验证时的兜底。
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String base = 'https://www.ycoo.net/';
  static const String loginPath = 'member.php?mod=logging&action=login&mobile=2';
  static const String logoutPath = 'member.php?mod=logging&action=logout&mobile=2';
  static const String _prefUser = 'ycoo.session.username';
  static const String _prefUid = 'ycoo.session.uid';
  static const String _prefAvatar = 'ycoo.session.avatar';
  static const String _prefFlag = 'ycoo.session.loggedIn';
  static const String _prefCookie = 'ycoo.session.cookie';

  bool _loggedIn = false;
  String? _username;
  int? _uid;
  String? _avatarUrl;
  String? _cookie;
  http.Client? _client;

  bool get isLoggedIn => _loggedIn;
  String? get username => _username;
  int? get uid => _uid;
  String? get avatarUrl => _avatarUrl;
  String? get authCookie => _cookie;

  Future<http.Client> _http() async => _client ??= await NetClient.instance.client;

  Map<String, String> _headers() {
    final h = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache',
    };
    if (_cookie != null && _cookie!.isNotEmpty) h['Cookie'] = _cookie!;
    return h;
  }

  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _username = sp.getString(_prefUser);
      _uid = sp.getInt(_prefUid);
      _avatarUrl = sp.getString(_prefAvatar);
      _loggedIn = sp.getBool(_prefFlag) ?? false;
      _cookie = sp.getString(_prefCookie);
    } catch (_) {}
  }

  /// 原生登录 Discuz。正常账号密码登录不依赖 WebView。
  /// 返回 null 表示成功；返回文本表示失败原因。
  Future<String?> loginNative(String username, String password) async {
    final user = username.trim();
    if (user.isEmpty) return '请输入用户名';
    if (password.isEmpty) return '请输入密码';

    try {
      final client = await _http();
      final loginPage = await client
          .get(Uri.parse(base + loginPath), headers: _headers())
          .timeout(NetClient.timeout);
      final page = NetClient.decode(loginPage.bodyBytes);
      final formhash = NetClient.first(
            RegExp(r'''name=["']formhash["'][^>]*value=["']([^"']+)["']'''),
            page,
          ) ??
          '';
      if (formhash.isEmpty) return '登录页面缺少 formhash，请稍后重试';

      final loginHash = NetClient.first(
            RegExp(r'''loginhash=([A-Za-z0-9]+)'''),
            page,
          ) ??
          '';
      final endpoint = Uri.parse(
        '${base}member.php?mod=logging&action=login&loginsubmit=yes'
        '${loginHash.isEmpty ? '' : '&loginhash=$loginHash'}&inajax=1',
      );

      final response = await client
          .post(
            endpoint,
            headers: <String, String>{
              ..._headers(),
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': base + loginPath,
            },
            body: <String, String>{
              'formhash': formhash,
              'referer': base,
              'loginfield': 'username',
              'username': user,
              'password': password,
              'cookietime': '2592000',
              'questionid': '0',
              'answer': '',
            },
          )
          .timeout(NetClient.timeout);

      final body = NetClient.decode(response.bodyBytes);
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        _cookie = _cookieFromSetCookie(setCookie);
      }

      if (_looksLikeSuccess(body)) {
        _loggedIn = true;
        _username = user;
        await _save();
        await refreshProfile();
        LoginLog.instance.add('原生登录成功: ${_username ?? user}, uid=${_uid ?? 0}');
        return null;
      }

      if (_needsVerification(body)) {
        return '网站要求验证码或安全验证，请使用网页验证完成登录';
      }

      if (body.contains('密码错误') || body.contains('用户名或密码错误') || body.contains('登录失败')) {
        return '用户名或密码错误';
      }
      if (body.contains('登录次数过多') || body.contains('请稍后再试')) {
        return '登录尝试过于频繁，请稍后再试';
      }
      return '登录失败，请检查账号信息';
    } catch (e) {
      LoginLog.instance.add('原生登录异常: $e');
      return '网络请求失败，请检查网络后重试';
    }
  }

  bool _looksLikeSuccess(String body) {
    return body.contains('succeed') ||
        body.contains('登录成功') ||
        body.contains('欢迎您回来') ||
        body.contains('现在将转入') ||
        body.contains('退出登录') ||
        body.contains('退出');
  }

  bool _needsVerification(String body) {
    return body.contains('seccode') ||
        body.contains('验证码') ||
        body.contains('安全验证') ||
        body.contains('verifycode') ||
        body.contains('验证问答');
  }

  String _cookieFromSetCookie(String raw) {
    final values = raw
        .split(RegExp(r',\s*(?=[A-Za-z0-9_]+=[^;]+)'))
        .map((v) => v.trim().split(';').first.trim())
        .where((v) => v.contains('='))
        .toList();
    return values.join('; ');
  }

  /// 从已登录页面补齐真实用户名、UID、头像。
  Future<void> refreshProfile() async {
    try {
      final client = await _http();
      final url = _uid != null && _uid! > 0
          ? '${base}home.php?mod=space&uid=$_uid&mobile=2'
          : '${base}home.php?mod=space&mobile=2';
      final resp = await client.get(Uri.parse(url), headers: _headers()).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (_isGuestPage(body)) return;

      final uidText = NetClient.first(RegExp(r'''(?:uid=|space&uid=)(\d+)'''), body);
      final parsedUid = int.tryParse(uidText ?? '');
      if (parsedUid != null && parsedUid > 0) _uid = parsedUid;

      final name = _firstNonEmpty([
        NetClient.first(RegExp(r'''class=["'][^"']*(?:vwmy|mn_avatar)[^"']*["'][^>]*>\s*<a[^>]*>([^<]+)'''), body),
        NetClient.first(RegExp(r'''class=["'][^"']*top_user[^"']*["'][^>]*>([^<]+)'''), body),
        NetClient.first(RegExp(r'''id=["']ihavefriends["'][^>]*>\s*<a[^>]*>([^<]+)'''), body),
      ]);
      if (name != null) _username = _cleanText(name);

      final avatar = NetClient.first(
        RegExp(r'''(?:src|data-src)=["']([^"']*(?:avatar|uc_server)[^"']*)["']''', caseSensitive: false),
        body,
      );
      if (avatar != null && avatar.isNotEmpty) {
        _avatarUrl = _absoluteUrl(avatar);
      } else if (_uid != null && _uid! > 0) {
        _avatarUrl = '${base}uc_server/avatar.php?uid=$_uid&size=middle';
      }
      await _save();
    } catch (e) {
      LoginLog.instance.add('刷新用户资料失败: $e');
    }
  }

  bool _isGuestPage(String body) {
    return body.contains('请登录') && !body.contains('退出') && !body.contains('退出登录');
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String _cleanText(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _absoluteUrl(String value) {
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('/')) return 'https://www.ycoo.net$value';
    return base + value;
  }

  Future<void> markLoggedInFromWeb(String username, String cookie, {int? uid, String? avatar}) async {
    _loggedIn = true;
    _username = username.trim().isEmpty ? null : username.trim();
    _uid = uid;
    _avatarUrl = avatar;
    _cookie = cookie.trim().isEmpty ? null : cookie.trim();
    await _save();
    await refreshProfile();
    LoginLog.instance.add(
      '登录成功: ${_username ?? '(未取到用户名)'}'
      '${_uid == null ? '' : ', uid=$_uid'}'
      '${_cookie == null ? '' : ', 已保存 Cookie(${_cookie!.length} 字符)'}',
    );
  }

  Future<bool> checkLoggedIn() async {
    try {
      final client = await _http();
      final resp = await client
          .get(Uri.parse('${base}forum.php?mobile=2'), headers: _headers())
          .timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      final ok = body.contains('action=logout') || body.contains('退出登录') || body.contains('退出');
      if (_loggedIn != ok) {
        _loggedIn = ok;
        if (!ok) {
          _username = null;
          _uid = null;
          _avatarUrl = null;
        }
        await _save();
      }
      if (ok) await refreshProfile();
      return _loggedIn;
    } catch (_) {
      return _loggedIn;
    }
  }

  Future<void> logout() async {
    try {
      final client = await _http();
      await client.get(Uri.parse(base + logoutPath), headers: _headers()).timeout(const Duration(seconds: 8));
    } catch (_) {}
    _loggedIn = false;
    _username = null;
    _uid = null;
    _avatarUrl = null;
    _cookie = null;
    await _save();
  }

  Future<String?> reply(int tid, int fid, String message) async {
    final text = message.trim();
    if (text.isEmpty) return '回帖内容不能为空';
    final client = await _http();
    try {
      final pageResp = await client.get(Uri.parse('${base}thread-$tid-1-1.html'), headers: _headers()).timeout(const Duration(seconds: 15));
      final page = NetClient.decode(pageResp.bodyBytes);
      final formhash = NetClient.first(RegExp(r'''name="formhash"[^>]*value="([0-9a-f]{8})"'''), page) ?? '';
      final noticeauthor = NetClient.first(RegExp(r'''name="noticeauthor"[^>]*value="([^"]*)"'''), page) ?? '';
      if (formhash.isEmpty) return '未取得回帖令牌(formhash)';
      final url = '${base}forum.php?mod=post&action=reply&fid=$fid&tid=$tid&extra=page%3D1&replysubmit=yes&mobile=2';
      final resp = await client.post(Uri.parse(url), headers: _headers(), body: <String, String>{
        'formhash': formhash,
        'noticeauthor': noticeauthor,
        'message': text,
        'replysubmit': '回复',
        'listextra': 'page%3D1',
      }).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (body.contains(text)) return null;
      if (body.contains('登录')) return '请先登录后回帖';
      return '回帖失败,请重试';
    } catch (_) {
      return '回帖请求失败,请稍后重试';
    }
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefUser, _username ?? '');
      if (_uid == null) {
        await sp.remove(_prefUid);
      } else {
        await sp.setInt(_prefUid, _uid!);
      }
      await sp.setString(_prefAvatar, _avatarUrl ?? '');
      await sp.setBool(_prefFlag, _loggedIn);
      await sp.setString(_prefCookie, _cookie ?? '');
    } catch (_) {}
  }
}
