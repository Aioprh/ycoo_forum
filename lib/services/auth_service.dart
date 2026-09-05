import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'site_config.dart';
import 'login_log.dart';
import 'net_client.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  static String get base => SiteConfig.base;
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

  Map<String, String> _headers({String? referer}) => <String, String>{
    'User-Agent': NetClient.ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache',
    if (referer != null) 'Referer': referer,
    if (_cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
  };

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

  String? _hiddenValue(String html, String name) {
    final escaped = RegExp.escape(name);
    final inputRe = RegExp(r'<input\b[^>]*>', caseSensitive: false);
    final nameFirst = RegExp('name\\s*=\\s*["\\\']$escaped["\\\'][^>]*value\\s*=\\s*["\\\']([^"\\\']+)["\\\']', caseSensitive: false);
    final valueFirst = RegExp('value\\s*=\\s*["\\\']([^"\\\']+)["\\\'][^>]*name\\s*=\\s*["\\\']$escaped["\\\']', caseSensitive: false);
    for (final m in inputRe.allMatches(html)) {
      final tag = m.group(0)!;
      final a = nameFirst.firstMatch(tag)?.group(1);
      if (a != null && a.trim().isNotEmpty) return a.trim();
      final b = valueFirst.firstMatch(tag)?.group(1);
      if (b != null && b.trim().isNotEmpty) return b.trim();
    }
    return null;
  }

  String? _loginHash(String html) {
    for (final re in <RegExp>[
      RegExp(r'''loginhash\s*=\s*([A-Za-z0-9_-]+)''', caseSensitive: false),
      RegExp(r'''[?&]loginhash(?:=|%3D)([A-Za-z0-9_-]+)''', caseSensitive: false),
      RegExp(r'''id=["']main_messaqge_([A-Za-z0-9_-]+)["']''', caseSensitive: false),
    ]) {
      final m = re.firstMatch(html);
      if (m != null && m.group(1)!.isNotEmpty) return m.group(1);
    }
    return null;
  }

  Future<String?> loginNative(
    String username,
    String password, {
    String questionId = '0',
    String answer = '',
  }) async {
    final user = username.trim();
    final cleanAnswer = answer.trim();
    if (user.isEmpty) return '请输入用户名';
    if (password.isEmpty) return '请输入密码';
    if (questionId != '0' && cleanAnswer.isEmpty) return '请输入安全提问答案';

    try {
      final client = await _http();
      final loginUri = Uri.parse(base + loginPath);

      // Discuz 登录令牌必须从本次登录页实时取得，不能缓存 formhash。
      final loginPage = await client.get(
        loginUri,
        headers: _headers(referer: base),
      ).timeout(NetClient.timeout);
      final page = NetClient.decode(loginPage.bodyBytes);
      final formhash = _hiddenValue(page, 'formhash');

      LoginLog.instance.add(
        '原生登录页: http=${loginPage.statusCode}, bytes=${loginPage.bodyBytes.length}, '
        'formhash=${formhash == null ? 'missing' : 'ok'}, loginhash=${_loginHash(page) == null ? 'missing' : 'ok'}',
      );

      if (formhash == null || formhash.isEmpty) {
        if (_needsVerification(page)) return '网站要求验证码或安全验证，请使用网页验证完成登录';
        return '登录页面暂时无法取得登录令牌，请刷新后重试';
      }

      final loginHash = _loginHash(page);
      final endpoint = Uri.parse(
        '${base}member.php?mod=logging&action=login&loginsubmit=yes'
        '${loginHash == null ? '' : '&loginhash=${Uri.encodeQueryComponent(loginHash)}'}'
        '&inajax=1',
      );

      // 参数与 Discuz X3 登录表单保持一致：安全提问未设置时 questionid=0。
      final response = await client.post(
        endpoint,
        headers: {
          ..._headers(referer: loginUri.toString()),
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Origin': base,
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: <String, String>{
          'formhash': formhash,
          'referer': base,
          'loginfield': 'username',
          'username': user,
          'password': password,
          'cookietime': '2592000',
          'questionid': questionId,
          'answer': cleanAnswer,
        },
      ).timeout(NetClient.timeout);

      final body = NetClient.decode(response.bodyBytes);
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        final parsed = _cookieFromSetCookie(setCookie);
        if (parsed.isNotEmpty) _cookie = _mergeCookies(_cookie, parsed);
      }

      LoginLog.instance.add(
        '原生登录响应: http=${response.statusCode}, bytes=${response.bodyBytes.length}, '
        'cookie=${_cookie == null ? 'none' : 'present'}',
      );

      if (_looksLikeSuccess(body) || await _verifySession(client)) {
        _loggedIn = true;
        _username = user;
        await _save();
        await refreshProfile();
        LoginLog.instance.add('原生登录成功: ${_username ?? user}, uid=${_uid ?? 0}');
        return null;
      }

      if (_needsVerification(body)) return '网站要求验证码或安全验证，请使用网页验证完成登录';
      if (_looksLikeQuestionError(body)) return '安全提问或答案不正确，请检查后重试';
      if (body.contains('密码错误') || body.contains('用户名或密码错误')) return '用户名或密码错误';
      if (body.contains('登录次数过多') || body.contains('请稍后再试')) return '登录尝试过于频繁，请稍后再试';

      final serverMessage = _extractServerMessage(body);
      if (serverMessage != null) {
        LoginLog.instance.add('原生登录服务器返回: $serverMessage');
        return serverMessage;
      }
      return '登录失败，请检查账号信息';
    } catch (e) {
      LoginLog.instance.add('原生登录异常: $e');
      return '网络请求失败，请检查网络后重试';
    }
  }

  bool _looksLikeSuccess(String body) {
    final lower = body.toLowerCase();
    return lower.contains('login_succeed') ||
        lower.contains('succeed') ||
        body.contains('登录成功') ||
        body.contains('欢迎您回来') ||
        body.contains('现在将转入');
  }

  bool _needsVerification(String body) {
    final lower = body.toLowerCase();
    return body.contains('seccode') ||
        body.contains('验证码') ||
        body.contains('安全验证') ||
        lower.contains('verifycode') ||
        body.contains('验证问答') ||
        body.contains('seccodeverify');
  }

  bool _looksLikeQuestionError(String body) {
    return body.contains('login_question_invalid') ||
        body.contains('安全提问错误') ||
        body.contains('验证问答错误') ||
        body.contains('问题答案错误');
  }

  String? _extractServerMessage(String body) {
    // Discuz inajax 通常返回 <root><![CDATA[...]]></root>，优先取其中的可读文本。
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1);
    final source = (cdata ?? body)
        .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();
    if (source.isEmpty || source.length > 120) return null;
    if (source.contains('登录') || source.contains('密码') || source.contains('账号') || source.contains('验证')) {
      return source;
    }
    return null;
  }

  Future<bool> _verifySession(http.Client client) async {
    try {
      final resp = await client.get(
        Uri.parse('${base}forum.php?mobile=2'),
        headers: _headers(referer: base),
      ).timeout(const Duration(seconds: 10));
      final body = NetClient.decode(resp.bodyBytes);
      return body.contains('action=logout') || body.contains('退出登录');
    } catch (_) {
      return false;
    }
  }

  String _cookieFromSetCookie(String raw) => raw
      .split(RegExp(r',\s*(?=[A-Za-z0-9_]+=[^;]+)'))
      .map((v) => v.trim().split(';').first.trim())
      .where((v) => v.contains('='))
      .join('; ');

  String _mergeCookies(String? oldCookie, String newCookie) {
    final map = <String, String>{};
    for (final part in [...?oldCookie?.split(';'), ...newCookie.split(';')]) {
      final p = part.trim();
      final i = p.indexOf('=');
      if (i > 0) map[p.substring(0, i)] = p.substring(i + 1);
    }
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> refreshProfile() async {
    try {
      final client = await _http();
      final url = _uid != null && _uid! > 0
          ? '${base}home.php?mod=space&uid=$_uid&mobile=2'
          : '${base}home.php?mod=space&mobile=2';
      final resp = await client.get(Uri.parse(url), headers: _headers()).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (_isGuestPage(body)) return;
      final uidText = RegExp(r'(?:uid=|space&uid=)(\d+)').firstMatch(body)?.group(1);
      final parsedUid = int.tryParse(uidText ?? '');
      if (parsedUid != null && parsedUid > 0) _uid = parsedUid;
      final values = <String?>[
        RegExp(r'''class=["'][^"']*(?:vwmy|mn_avatar)[^"']*["'][^>]*>\s*<a[^>]*>([^<]+)''').firstMatch(body)?.group(1),
        RegExp(r'''class=["'][^"']*top_user[^"']*["'][^>]*>([^<]+)''').firstMatch(body)?.group(1),
        RegExp(r'''id=["']ihavefriends["'][^>]*>\s*<a[^>]*>([^<]+)''').firstMatch(body)?.group(1),
      ];
      final name = values.firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
      if (name != null) _username = _cleanText(name);
      final avatar = RegExp(r'''(?:src|data-src)=["']([^"']*(?:avatar|uc_server)[^"']*)["']''', caseSensitive: false).firstMatch(body)?.group(1);
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

  bool _isGuestPage(String body) => body.contains('请登录') && !body.contains('退出') && !body.contains('退出登录');
  String _cleanText(String value) {
    var t = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 剔除开头独立粘连的图标残留数字(源站图标字体被剥离后残留的等级/角标数字)。
    t = t.replaceFirst(RegExp(r'^\d+\s+'), '').trim();
    return t;
  }
  String _absoluteUrl(String value) {
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('/')) return SiteConfig.base + value.substring(1);
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
    LoginLog.instance.add('登录成功: ${_username ?? '(未取到用户名)'}${_uid == null ? '' : ', uid=$_uid'}${_cookie == null ? '' : ', 已保存 Cookie(${_cookie!.length} 字符)'}');
  }

  Future<bool> checkLoggedIn() async {
    try {
      final client = await _http();
      final resp = await client.get(Uri.parse('${base}forum.php?mobile=2'), headers: _headers()).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      final ok = body.contains('action=logout') || body.contains('退出登录');
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

  /// 回复主题(发新楼层): 完全对齐网页端 fastpost 的 AJAX 提交。
  ///
  /// 网页端帖子底部的快速回复用 `#fastpostsubmit` 触发:
  /// ```js
  /// $.ajax({ type:'POST',
  ///   url: form.attr('action') + '&handlekey=fastpost&loc=1&inajax=1',
  ///   data: form.serialize(),  // formhash + noticeauthor + message
  ///   dataType:'xml' });
  /// ```
  /// 成功返回 <root><![CDATA[...succeedhandle_fastpost(...)]]></root>。
  /// 若缺少 handlekey=fastpost&loc=1&inajax=1 或 noticeauthor, Discuz 会走同步跳转,
  /// 拿不到可判定的 ajax 成功协议, 导致“实际已发布却提示回复失败”。
  Future<String?> reply(int tid, int fid, String message) async {
    final text = message.trim();
    if (text.isEmpty) return '回帖内容不能为空';
    final client = await _http();
    try {
      final getUrl = '${base}thread-$tid-1-1.html';
      final pageResp = await client.get(Uri.parse(getUrl), headers: _headers()).timeout(const Duration(seconds: 15));
      final page = NetClient.decode(pageResp.bodyBytes);
      final formhash = _hiddenValue(page, 'formhash') ?? '';
      if (formhash.isEmpty) return '未取得回帖令牌(formhash)';
      final extra = 'page%3D1';
      final noticeauthor = _hiddenValue(page, 'noticeauthor') ?? '';
      final postBody = <String, String>{
        'formhash': formhash,
        'message': text,
        'replysubmit': 'yes',
        if (noticeauthor.isNotEmpty) 'noticeauthor': noticeauthor,
      };
      final url = '${base}forum.php?mod=post&action=reply&fid=$fid&tid=$tid&extra=$extra&replysubmit=yes&handlekey=fastpost&loc=1&inajax=1&mobile=2';
      final resp = await client.post(Uri.parse(url), headers: {..._headers(referer: getUrl), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Origin': base, 'X-Requested-With': 'XMLHttpRequest'}, body: postBody).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (_isReplySuccess(body, tid, resp.statusCode)) return null;
      return _replyError(body, text);
    } catch (_) {
      return '回帖请求失败,请稍后重试';
    }
  }

  /// 回复楼层/楼中楼: 走 Comiis replyfloor 插件自己的接口
  /// `plugin.php?id=replyfloor:index&ac=post`, 而不是 Discuz 原生 reply。
  ///
  /// [postpid] 是父楼 Discuz 原生 postpid(如 2657801), [msgid] 是 replyfloor 内部回复 id:
  /// 0 表示回复本楼, 非 0 表示回复某条楼中楼(如 20568)。
  Future<String?> replyFloor(int tid, int postpid, String message, {int msgid = 0}) async {
    final text = message.trim();
    if (text.isEmpty) return '回复内容不能为空';
    if (postpid <= 0) return '未取得回复楼层，请刷新后重试';
    final client = await _http();
    try {
      // 第一步: 打开 replyfloor 回复表单, 取它自己的 formhash。
      final formUrl = '${base}plugin.php?id=replyfloor:index&ac=post&tid=$tid&pid=$postpid&msgid=$msgid&style=1&handlekey=messagepost&loc=1&inajax=1';
      final formResp = await client.get(Uri.parse(formUrl), headers: _headers(referer: '${base}thread-$tid-1-1.html')).timeout(const Duration(seconds: 15));
      final formPage = NetClient.decode(formResp.bodyBytes);
      final formhash = _hiddenValue(formPage, 'formhash') ?? '';
      if (formhash.isEmpty) return '未取得回帖令牌(formhash)';

      // 第二步: 提交回复。表单 action 自带 infloat=yes, JS 再拼 &loc=1&inajax=1。
      final submitUrl = '${base}plugin.php?id=replyfloor:index&ac=post&tid=$tid&pid=$postpid&infloat=yes&loc=1&inajax=1';
      final postBody = <String, String>{
        'formhash': formhash,
        'message': text,
        'msgid': '$msgid',
        'savesubmit': 'true',
        'handlekey': 'messagepost',
      };
      final resp = await client.post(Uri.parse(submitUrl), headers: {..._headers(referer: formUrl), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Origin': base, 'X-Requested-With': 'XMLHttpRequest'}, body: postBody).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      // replyfloor 成功返回: <root><![CDATA[...回复发布成功...succeedhandle_messagepost...]]></root>
      if (_isReplySuccess(body, tid, resp.statusCode)) return null;
      return _replyError(body, text);
    } catch (_) {
      return '回帖请求失败,请稍后重试';
    }
  }

  /// 统一判定回复是否成功：覆盖 Discuz 原生 reply(含 fastpost) 与 Comiis replyfloor。
  ///
  /// 关键点：Discuz 的 ajax 成功/失败是成对回调 succeedhandle_* / errorhandle_*。
  /// 页面里内联的 JS 会同时定义这两个函数，所以一旦响应是整页回退，
  /// 就必须用“含成功回调且不含错误回调”来判定，否则会把失败页误判为成功。
  bool _isReplySuccess(String body, int tid, int statusCode) {
    final hasError = RegExp(r'errorhandle_|showError\s*\(|alert_error', caseSensitive: false).hasMatch(body);
    if (hasError) return false;

    // 1. ajax 成功回调 / 成功文案(回复成功、回复发布成功、succeedhandle_*、do_success)。
    if (body.contains('succeedhandle_') ||
        body.contains('do_success') ||
        body.contains('回复发布成功') ||
        body.contains('回复成功') ||
        body.contains('发表回复完成')) {
      return true;
    }
    // 2. 部分版本成功只回一个跳转 location.href：回到主题、或定位到新发表楼层 #pid_。
    if (body.contains('location.href') &&
        (body.contains('tid=$tid') || body.contains('thread-$tid') || body.contains('#pid_'))) {
      return true;
    }
    // 3. replyfloor inajax 返回 <root><![CDATA[...]]></root> 包裹的新回帖 HTML。
    if (statusCode == 200 &&
        body.contains('<root') &&
        body.toLowerCase().contains('<![cdata[') &&
        body.contains('succeed')) {
      return true;
    }
    return false;
  }

  /// body 是否回显了用户输入的回复文本（两边都先抹空白，容忍 HTML 换行等转换）。
  bool _echoed(String body, String text) {
    if (text.isEmpty) return false;
    final b = body.replaceAll(RegExp(r'\s+'), '');
    final t = text.replaceAll(RegExp(r'\s+'), '');
    return t.isNotEmpty && b.contains(t);
  }

  /// 统一的回复失败信息映射: 从 Discuz / replyfloor 的响应正文里提取可读错误。
  String? _replyError(String body, String text) {
    final needLogin = RegExp(r'''您需要(?:先)?登录才能|未登录|登录后才能|action=login[^0-9]|<title>[^<]*登录[^<]*</title>''', caseSensitive: false).hasMatch(body);
    if (needLogin) return '请先登录后回帖';
    if (RegExp(r'''formhash.*(验证失败|非法请求|失效|令牌)|来路不正确|security\.validate''').hasMatch(body) ||
        (body.contains('formhash') && (body.contains('验证失败') || body.contains('非法请求') || body.contains('令牌') || body.contains('失效')))) {
      return '回帖令牌已失效，请刷新后重试';
    }
    final showErr = RegExp(r'''showError\(\s*['"]([^'"]+)['"]''').firstMatch(body)?.group(1) ??
        RegExp(r'''errorhandle_[A-Za-z_]*\(\s*['"]([^'"]+)['"]''').firstMatch(body)?.group(1) ??
        RegExp(r'''(?:alert_error|error_message)[^>]*>\s*(?:<[^>]+>\s*)?([^<]{2,120})''').firstMatch(body)?.group(1) ??
        RegExp(r'<div[^>]*class="alert_error[^"]*"[^>]*>([^<]{2,120})').firstMatch(body)?.group(1);
    if (showErr != null && showErr.trim().isNotEmpty) return showErr.trim();
    if (_echoed(body, text)) return null;
    return '回复失败,请重试';
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
