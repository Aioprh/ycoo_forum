import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'credential_store.dart';
import 'user_permission_service.dart';
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
  bool _autoLoginTried = false;
  Future<bool>? _autoLoginTask;
  /// 正在进行的原生登录，用于合并并发请求。
  String? _loginKey;
  Future<String?>? _loginTask;
  bool get isLoggedIn => _loggedIn;
  String? get username => _username;
  int? get uid => _uid;
  String? get avatarUrl => _avatarUrl;
  String? get authCookie => _cookie;
  Future<http.Client> _http() async => _client ??= await NetClient.instance.client;

  Map<String, String> _headers({String? referer, bool withCookie = true}) => <String, String>{
    'User-Agent': NetClient.ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache',
    if (referer != null) 'Referer': referer,
    if (withCookie && _cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
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

  /// 用站点自身的登录接口登录，成功返回 null，失败返回给用户看的文案。
  Future<String?> loginNative(
    String username,
    String password, {
    String questionId = '0',
    String answer = '',
  }) {
    final user = username.trim();
    final cleanAnswer = answer.trim();
    if (user.isEmpty) return Future<String?>.value('请输入用户名');
    if (password.isEmpty) return Future<String?>.value('请输入密码');
    if (questionId != '0' && cleanAnswer.isEmpty) {
      return Future<String?>.value('请输入安全提问答案');
    }

    // 启动时的静默登录与用户手动点「登录」可能同时触发。
    // 并发提交会互相顶掉会话，还会白白消耗站点给的尝试次数，这里合并成一次。
    final key = '$user\u0000$password\u0000$questionId\u0000$cleanAnswer';
    final running = _loginTask;
    if (running != null && _loginKey == key) return running;

    final task = _loginWithFallback(user, password, questionId, cleanAnswer);
    _loginKey = key;
    _loginTask = task;
    return task.whenComplete(() {
      if (identical(_loginTask, task)) {
        _loginTask = null;
        _loginKey = null;
      }
    });
  }

  Future<String?> _loginWithFallback(
    String user,
    String password,
    String questionId,
    String cleanAnswer,
  ) async {
    final client = await _http();
    // 不同地区/运营商能连通的入口不一样，依次尝试，避免卡在一条被拦截的线路上。
    final bases = await SiteConfig.reachableCandidates();
    final candidates = bases.isEmpty ? <String>[base] : bases;

    String? lastError;
    for (final baseUrl in candidates) {
      final outcome = await _loginOnce(client, baseUrl, user, password, questionId, cleanAnswer);
      if (outcome.error == null) return null;
      lastError = outcome.error;
      // 站点已给出明确答复(密码不对、需要验证码)时换线没有意义，
      // 多提交一次反而会再消耗一次站点的登录尝试次数。
      if (!outcome.retryNext) return lastError;
      LoginLog.instance.add('登录换线: $baseUrl 不可用($lastError)，尝试下一个入口');
    }
    LoginLog.instance.add('原生登录: ${candidates.length} 个入口均失败，最后错误=$lastError');
    if (lastError == null) return '登录失败，请稍后重试';
    return candidates.length > 1 ? '$lastError（已尝试 ${candidates.length} 个入口）' : lastError;
  }

  /// 在指定入口上完成一次登录。
  ///
  /// [retryNext] 为 true 表示这个入口本身有问题(取不到令牌/连不上/服务端报错)，
  /// 换线还有机会；为 false 表示站点已给出明确答复(密码错误、需要验证码等)，
  /// 换线既没必要，也可能多消耗一次站点的登录尝试次数。
  Future<({String? error, bool retryNext})> _loginOnce(
    http.Client client,
    String baseUrl,
    String user,
    String password,
    String questionId,
    String cleanAnswer,
  ) async {
    final jar = _CookieJar();
    try {
      final loginUri = Uri.parse('$baseUrl$loginPath');

      // 不带应用里存的旧 Cookie(失效会话会把页面带偏)，但必须把本次登录页
      // 下发的 Cookie 一路带到提交请求：Discuz 的登录提交依赖这里下发的
      // saltkey/sid，缺了会直接返回 503 System Error。
      final loginPage = await client.get(
        loginUri,
        headers: _headers(referer: baseUrl, withCookie: false),
      ).timeout(const Duration(seconds: 8));
      jar.absorb(loginPage.headers);
      final page = NetClient.decode(loginPage.bodyBytes);
      final formhash = _hiddenValue(page, 'formhash');

      LoginLog.instance.add(
        '原生登录页[$baseUrl]: http=${loginPage.statusCode}, bytes=${loginPage.bodyBytes.length}, '
        'title=${_pageTitle(page)}, formhash=${formhash == null ? 'missing' : 'ok'}, '
        'loginhash=${_loginHash(page) == null ? 'missing' : 'ok'}, cookies=${jar.length}',
      );

      if (loginPage.statusCode >= 500) {
        return (error: '当前线路返回系统错误(HTTP ${loginPage.statusCode})', retryNext: true);
      }

      // 登录页上出现验证码输入框时，原生登录必然提交不过去，
      // 先提示网页验证，避免白白消耗一次登录尝试次数。
      if (page.contains('seccodeverify') || page.contains('seccodehash')) {
        return (error: '该账号需要验证码，请使用网页验证完成登录', retryNext: false);
      }

      if (formhash == null || formhash.isEmpty) {
        if (_looksBlocked(page)) {
          // 站点前置防护(Cloudflare 等)拦下了该线路，换入口通常就能绕开。
          return (error: '当前线路被站点安全校验拦截', retryNext: true);
        }
        if (_needsVerification(page)) {
          return (error: '网站要求验证码或安全验证，请使用网页验证完成登录', retryNext: false);
        }
        return (error: '当前线路未返回登录令牌', retryNext: true);
      }

      final loginHash = _loginHash(page);
      final endpoint = Uri.parse(
        '${baseUrl}member.php?mod=logging&action=login&loginsubmit=yes'
        '${loginHash == null ? '' : '&loginhash=${Uri.encodeQueryComponent(loginHash)}'}'
        '&inajax=1',
      );

      // 参数对齐 Discuz X3 登录表单：安全提问未设置时 questionid=0；
      // submit / agreebbrule 与页面上的登录按钮、协议勾选框同名同值。
      final response = await client.post(
        endpoint,
        headers: {
          ..._headers(referer: loginUri.toString(), withCookie: false),
          if (jar.header.isNotEmpty) 'Cookie': jar.header,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Origin': baseUrl,
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: <String, String>{
          'formhash': formhash,
          'referer': baseUrl,
          'fastloginfield': 'username',
          'loginfield': 'username',
          'username': user,
          'password': password,
          'cookietime': '2592000',
          'questionid': questionId,
          'answer': cleanAnswer,
          'submit': 'true',
          'agreebbrule': '1',
        },
      ).timeout(NetClient.timeout);

      jar.absorb(response.headers);
      final body = NetClient.decode(response.bodyBytes);
      final message = _serverMessage(body);

      LoginLog.instance.add(
        '原生登录响应[$baseUrl]: http=${response.statusCode}, bytes=${response.bodyBytes.length}, '
        'cookies=${jar.length}, auth=${jar.hasAuth}, msg=${message ?? '(无)'}',
      );

      if (response.statusCode >= 500) {
        return (error: '当前线路返回系统错误(HTTP ${response.statusCode})', retryNext: true);
      }

      // 站点给了明确失败答复时直接返回，不再多试一条线路。
      final failure = _classifyLoginFailure(body, statusCode: response.statusCode);
      if (failure != null) return failure;

      // 只有服务端真的建立了会话才算登录成功：成功后站点会下发 auth Cookie，
      // 再访问论坛首页应能看到「退出登录」入口，而不是「请登录或注册」。
      final verified = await _verifySession(client, baseUrl, jar.header);
      if (verified || (jar.hasAuth && _looksLikeSuccess(body))) {
        _cookie = jar.header;
        // 记住这条能正常登录的线路，后续请求直接用它。
        SiteConfig.useBase(baseUrl);
        _loggedIn = true;
        _username = user;
        // 换了账号时旧 uid / 头像必须作废，否则会拉到上一个账号的资料。
        _uid = null;
        _avatarUrl = null;
        await _save();
        await refreshProfile();
        LoginLog.instance.add('原生登录成功: ${_username ?? user}, uid=${_uid ?? 0}, 线路=$baseUrl');
        return (error: null, retryNext: false);
      }

      return (error: '登录未成功，请重试或使用网页验证', retryNext: true);
    } on TimeoutException {
      LoginLog.instance.add('原生登录超时[$baseUrl]');
      return (error: '当前线路连接超时', retryNext: true);
    } catch (e) {
      LoginLog.instance.add('原生登录异常[$baseUrl]: $e');
      return (error: '当前线路连接失败', retryNext: true);
    }
  }

  /// 取页面标题，仅用于登录诊断日志。
  String _pageTitle(String html) {
    final title = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html)?.group(1);
    final value = (title ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty) return '(none)';
    return value.length > 40 ? '${value.substring(0, 40)}…' : value;
  }

  /// 页面是否为站点前置防护(Cloudflare 等)/访问限制页，而不是真正的登录页。
  bool _looksBlocked(String html) {
    final lower = html.toLowerCase();
    return lower.contains('cf-browser-verification') ||
        lower.contains('cf_chl') ||
        lower.contains('checking your browser') ||
        lower.contains('just a moment') ||
        lower.contains('attention required') ||
        lower.contains('access denied') ||
        html.contains('访问被拒绝') ||
        html.contains('拒绝访问') ||
        html.contains('当前IP') ||
        html.contains('该地区');
  }

  /// 使用本地保存的账号密码静默登录，用于「记住账号密码」后免重复输入。
  ///
  /// 只在当前没有有效登录态时尝试；默认每个应用生命周期只尝试一次，
  /// 避免密码已变更时反复触发登录请求与站点风控。
  /// 多个页面同时触发时会共用同一个在途任务，不会重复登录。
  /// 失败时返回 false 且不抛异常，调用方继续走正常的登录引导即可。
  Future<bool> tryAutoLogin({bool force = false}) {
    if (_loggedIn) return Future<bool>.value(true);
    if (force) {
      _autoLoginTask = null;
    } else if (_autoLoginTask != null) {
      // 已有在途/已完成的尝试：直接复用结果，避免多页面并发重复登录。
      return _autoLoginTask!;
    } else if (_autoLoginTried) {
      return Future<bool>.value(false);
    }
    _autoLoginTried = true;
    return _autoLoginTask = _autoLoginWithSaved();
  }

  Future<bool> _autoLoginWithSaved() async {
    final saved = await CredentialStore.instance.load();
    if (saved == null || !saved.autoLogin) return false;
    LoginLog.instance.add('尝试使用已保存的账号自动登录: ${saved.username}');
    final error = await loginNative(
      saved.username,
      saved.password,
      questionId: saved.questionId,
      answer: saved.answer,
    );
    if (error == null) {
      LoginLog.instance.add('自动登录成功: ${_username ?? saved.username}');
      return true;
    }
    LoginLog.instance.add('自动登录失败: $error');
    // 账号密码本身失效时关闭静默重登，避免每次启动都撞一次风控；
    // 用户重新登录并勾选「记住账号密码」会再次开启。
    // 注意只认明确的凭证错误，网络异常时不改动设置。
    final credentialInvalid = error.contains('密码错误') ||
        error.contains('用户名或密码') ||
        error.contains('账号不存在') ||
        error.contains('用户不存在') ||
        error.contains('安全提问') ||
        error.contains('答案不正确') ||
        error.contains('还可尝试') ||
        error.contains('锁定') ||
        error.contains('次数过多');
    if (credentialInvalid) {
      await CredentialStore.instance.disableAutoLogin();
    }
    return false;
  }

  bool _looksLikeSuccess(String body) {
    final lower = body.toLowerCase();
    return lower.contains('login_succeed') ||
        lower.contains('succeed') ||
        lower.contains('window.location.href') ||
        lower.contains('location.href=') ||
        lower.contains('location.replace') ||
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

  /// 把站点回复归类成给用户看的错误；返回 null 表示没有明确的失败信号。
  ({String? error, bool retryNext})? _classifyLoginFailure(
    String body, {
    required int statusCode,
  }) {
    // 会话/令牌缺失时 Discuz 会直接抛 System Error 页，换一条线路重走一遍通常就好了。
    if (body.contains('System Error') || body.contains('系统错误')) {
      return (error: '论坛返回系统错误', retryNext: true);
    }
    final text = _serverMessage(body) ?? '';
    if (text.isEmpty) return null;

    if (_needsVerification(text)) {
      return (error: '网站要求验证码或安全验证，请使用网页验证完成登录', retryNext: false);
    }
    if (_looksLikeQuestionError(text)) {
      return (error: '安全提问或答案不正确，请检查后重试', retryNext: false);
    }

    // 「登录失败，您还可以尝试 N 次」是 Discuz 对账号密码错误的提示，N 为剩余次数。
    final attempts = RegExp(r'还可以尝试\s*(\d+)\s*次').firstMatch(text);
    if (attempts != null) {
      final left = int.tryParse(attempts.group(1)!) ?? 0;
      if (left <= 0) {
        return (error: '登录失败次数过多，账号已被临时锁定，请稍后重试或使用网页验证', retryNext: false);
      }
      return (error: '用户名或密码不正确（还可尝试 $left 次）', retryNext: false);
    }
    if (text.contains('密码错误') || text.contains('用户名或密码')) {
      return (error: '用户名或密码错误', retryNext: false);
    }
    if (text.contains('次数过多') || text.contains('禁止') || text.contains('锁定') || text.contains('冻结')) {
      return (error: text, retryNext: false);
    }
    if (text.contains('不存在')) {
      return (error: '账号不存在，请检查用户名', retryNext: false);
    }
    if (text.contains('同意') && text.contains('协议')) {
      return (error: '需要先同意用户协议才能登录，请使用网页验证完成', retryNext: false);
    }
    if (text.contains('来路') || text.contains('令牌') || text.toLowerCase().contains('formhash')) {
      // 令牌/会话不匹配：重新走一遍登录流程会拿到新令牌。
      return (error: text, retryNext: true);
    }
    if (_looksLikeSuccess(body)) return null;
    return (error: text, retryNext: false);
  }

  /// 取出 Discuz 回复里真正给用户看的那句提示。
  String? _serverMessage(String body) {
    if (body.isEmpty) return null;
    var source = body;
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?.group(1);
    if (cdata != null) source = cdata;
    // 默认模板与 Comiis 模板都把提示正文放在 id="messagetext" 里。
    // 只取这一块，避免把整页导航文字也当成提示（旧实现就是因此取不到文案）。
    final boxed = RegExp(
      r'''id=["']messagetext["'][^>]*>([\s\S]*?)</(?:dt|dd|div|p)>''',
      caseSensitive: false,
    ).firstMatch(source)?.group(1);
    if (boxed != null && boxed.trim().isNotEmpty) source = boxed;

    final text = _plainText(source);
    if (text.isEmpty) return null;
    if (!RegExp(r'登录|登陆|密码|账号|帐号|用户|验证|禁止|锁定|失败|错误|稍后|协议|安全|系统').hasMatch(text)) {
      return null;
    }
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  /// 去标签取纯文本。
  ///
  /// 注意空白折叠必须用 `\s+`（旧实现写成 `\\s+`，等价于「反斜杠+s」，
  /// 换行根本不会被折叠，提取出的文案超长后被丢弃，用户只能看到兜底提示）。
  String _plainText(String html) => html
      .replaceAll(RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<bool> _verifySession(http.Client client, String site, String cookie) async {
    try {
      final resp = await client.get(
        Uri.parse('${site}forum.php?mobile=2'),
        headers: {
          ..._headers(referer: site, withCookie: false),
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 10));
      final body = NetClient.decode(resp.bodyBytes);
      // 已登录：页面有「退出登录」入口；未登录：页面是「请登录或注册」。
      return body.contains('action=logout') || body.contains('退出登录');
    } catch (_) {
      return false;
    }
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
      final cookieBefore = _cookie;
      final client = await _http();
      final resp = await client.get(Uri.parse('${base}forum.php?mobile=2'), headers: _headers()).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      final ok = body.contains('action=logout') || body.contains('退出登录');
      // 探测期间若已通过「记住账号密码」重新登录（Cookie 已被替换），
      // 不能用旧会话的探测结果覆盖新的登录态。
      if (!ok && _loggedIn && _cookie != cookieBefore) return _loggedIn;
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
    UserPermissionService.resetCache();
    // 主动退出后不再静默自动登录（避免刚退出又被登回去），
    // 但保留已记住的账号密码，登录页仍会自动填充。
    await CredentialStore.instance.disableAutoLogin();
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

  /// 解析 replyfloor 返回的表单，返回 action 的绝对地址 + 输入字段 + 提交按钮名。
  /// 用动态解析而非硬编码字段，是因为编辑/删除表单的字段由服务端决定。
  ({String? action, Map<String, String> fields, String? submitName, String? textareaName, String? initial}) _parseReplyfloorForm(String html) {
    final fields = <String, String>{};
    String? submitName;
    String? textareaName;
    String? initial;
    dom.Element? form;
    try {
      form = html_parser.parse(html).querySelector('form');
    } catch (_) {}
    if (form == null) return (action: null, fields: fields, submitName: null, textareaName: null, initial: null);
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name'];
      final value = input.attributes['value'] ?? '';
      if (name == null || name.isEmpty) continue;
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'submit' || type == 'button') { submitName = name; continue; }
      fields[name] = value;
      if (name == 'message' && value.trim().isNotEmpty && initial == null) initial = value.trim();
    }
    for (final b in form.querySelectorAll('button')) {
      final name = b.attributes['name'];
      if (name != null && name.isNotEmpty && submitName == null) {
        submitName = name;
        fields[name] = b.attributes['value'] ?? 'yes';
      }
    }
    final ta = form.querySelector('textarea');
    if (ta != null && ta.attributes['name'] != null) {
      textareaName = ta.attributes['name'];
      final t = ta.text ?? '';
      if (t.trim().isNotEmpty && initial == null) initial = t.trim();
    }
    return (action: form.attributes['action'], fields: fields, submitName: submitName, textareaName: textareaName, initial: initial);
  }

  /// 读取一条楼中楼回复的当前正文，供编辑弹窗预填。返回 null 表示取不到(不存在/未登录)。
  Future<String?> fetchFloorEditText(int tid, int postpid, int msgid) async {
    final client = await _http();
    try {
      final formUrl = Uri.parse('${base}plugin.php?id=replyfloor:index&ac=edit&tid=$tid&pid=$postpid&msgid=$msgid&handlekey=editmod&loc=1&inajax=1');
      final resp = await client.get(formUrl, headers: _headers()).timeout(NetClient.timeout);
      final form = _parseReplyfloorForm(NetClient.decode(resp.bodyBytes));
      return form.initial;
    } catch (_) {
      return null;
    }
  }

  /// 读取一条普通楼层回帖的当前正文，供编辑弹窗预填。返回 null 表示取不到。
  Future<String?> fetchPostEditText(int tid, int fid, int pid) async {
    final client = await _http();
    try {
      final formUrl = Uri.parse('${base}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1&mobile=2');
      final resp = await client.get(formUrl, headers: _headers()).timeout(NetClient.timeout);
      final form = _parseReplyfloorForm(NetClient.decode(resp.bodyBytes));
      return form.initial;
    } catch (_) {
      return null;
    }
  }

  /// 编辑一条楼中楼回复（Comiis replyfloor `ac=edit`）。
  /// [postpid] 父楼 Discuz postpid，[msgid] replyfloor 内部回复 id。
  /// 成功返回 null，失败返回可读错误。新原文为 [message]。
  Future<String?> editFloorReply(int tid, int postpid, int msgid, String message) async {
    final text = message.trim();
    if (text.isEmpty) return '编辑内容不能为空';
    final client = await _http();
    final referer = '${base}thread-$tid-1-1.html';
    try {
      final formUrl = Uri.parse('${base}plugin.php?id=replyfloor:index&ac=edit&tid=$tid&pid=$postpid&msgid=$msgid&handlekey=editmod&loc=1&inajax=1');
      final formResp = await client.get(formUrl, headers: _headers(referer: referer)).timeout(NetClient.timeout);
      final form = _parseReplyfloorForm(NetClient.decode(formResp.bodyBytes));
      if (form.action == null) return '编辑内容不存在或已删除';
      final payload = <String, String>{...form.fields};
      // textarea(message) 以新文本覆盖；若无 textarea 则回退到 message 字段。
      final msgKey = form.textareaName ?? 'message';
      payload[msgKey] = text;
      if (form.submitName != null && !payload.containsKey(form.submitName!)) payload[form.submitName!] = 'yes';
      payload['handlekey'] = 'editmod';
      final abs = Uri.parse(base).resolve(form.action!);
      final submitUrl = abs.replace(queryParameters: {...abs.queryParameters, 'loc': '1', 'inajax': '1'});
      final resp = await client.post(submitUrl, headers: {..._headers(referer: formUrl.toString()), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Origin': base, 'X-Requested-With': 'XMLHttpRequest'}, body: payload).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (body.contains('succeedhandle_editmod')) return null;
      return _floorError(body, '编辑失败,请重试');
    } catch (_) {
      return '编辑请求失败,请稍后重试';
    }
  }

  /// 删除一条楼中楼回复（Comiis replyfloor `ac=delete`）。
  Future<String?> deleteFloorReply(int tid, int postpid, int msgid) async {
    final client = await _http();
    final referer = '${base}thread-$tid-1-1.html';
    try {
      final formUrl = Uri.parse('${base}plugin.php?id=replyfloor:index&ac=delete&tid=$tid&pid=$postpid&msgid=$msgid&handlekey=deletemod&loc=1&inajax=1');
      final formResp = await client.get(formUrl, headers: _headers(referer: referer)).timeout(NetClient.timeout);
      final form = _parseReplyfloorForm(NetClient.decode(formResp.bodyBytes));
      if (form.action == null) return '该回复不存在或已删除';
      final payload = <String, String>{...form.fields};
      payload['handlekey'] = 'deletemod';
      if (form.submitName != null && !payload.containsKey(form.submitName!)) payload[form.submitName!] = 'yes';
      final abs = Uri.parse(base).resolve(form.action!);
      final submitUrl = abs.replace(queryParameters: {...abs.queryParameters, 'loc': '1', 'inajax': '1'});
      final resp = await client.post(submitUrl, headers: {..._headers(referer: formUrl.toString()), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Origin': base, 'X-Requested-With': 'XMLHttpRequest'}, body: payload).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (body.contains('succeedhandle_deletemod')) return null;
      return _floorError(body, '删除失败,请重试');
    } catch (_) {
      return '删除请求失败,请稍后重试';
    }
  }

  /// 编辑一条普通楼层回帖（Discuz 原生 `forum.php?mod=post&action=edit`）。
  /// [pid] 为楼层 Discuz postpid。成功返回 null，失败返回可读错误。
  Future<String?> editPostReply(int tid, int fid, int pid, String message) async {
    final text = message.trim();
    if (text.isEmpty) return '编辑内容不能为空';
    final client = await _http();
    try {
      final formUrl = Uri.parse('${base}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1&mobile=2');
      final formResp = await client.get(formUrl, headers: _headers()).timeout(NetClient.timeout);
      // 编辑表单可能是输入框(<input name="message">)或富文本(<textarea name="message">)，都能被解析。
      final form = _parseReplyfloorForm(NetClient.decode(formResp.bodyBytes));
      if (form.action == null) return '该回帖不存在或已删除';
      final payload = <String, String>{...form.fields};
      final msgKey = form.textareaName ?? 'message';
      payload[msgKey] = text;
      payload['fid'] = '$fid';
      payload['tid'] = '$tid';
      payload['pid'] = '$pid';
      payload['editsubmit'] = 'yes';
      final abs = Uri.parse(base).resolve(form.action!);
      final submitUrl = abs.replace(queryParameters: {...abs.queryParameters, 'mobile': '2'});
      final resp = await client.post(submitUrl, headers: {..._headers(referer: formUrl.toString()), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Origin': base, 'X-Requested-With': 'XMLHttpRequest'}, body: payload).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (body.contains('succeedhandle_') || (body.contains('location.href') && (body.contains('#pid_') || body.contains('thread-$tid')))) return null;
      return _floorError(body, '编辑失败,请重试');
    } catch (_) {
      return '编辑请求失败,请稍后重试';
    }
  }

  /// 删除自己的一条普通楼层回帖（Discuz `forum.php?mod=post&action=edit`）。
  ///
  /// 站点移动模板没有单独的删除地址：删除就是「把编辑表单里隐藏的 delete 置 1 再提交」，
  /// 模板自身的 JS `comiis_delthread()` 也只是改了该隐藏域后点击保存按钮。
  /// 因此这里先取真实编辑表单，原样回填并带上 delete=1 提交。
  /// 成功返回 null，失败返回可读错误。
  Future<String?> deletePostReply(int tid, int fid, int pid) async {
    final client = await _http();
    try {
      final formUrl = Uri.parse('${base}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1&mobile=2');
      final formResp = await client.get(formUrl, headers: _headers()).timeout(NetClient.timeout);
      final form = _parseReplyfloorForm(NetClient.decode(formResp.bodyBytes));
      if (form.action == null) return '该回帖不存在或已删除';
      final payload = <String, String>{...form.fields};
      payload[form.textareaName ?? 'message'] = form.initial ?? '';
      payload['fid'] = '$fid';
      payload['tid'] = '$tid';
      payload['pid'] = '$pid';
      payload['editsubmit'] = 'yes';
      payload['delete'] = '1';
      final abs = Uri.parse(base).resolve(form.action!);
      final submitUrl = abs.replace(queryParameters: {...abs.queryParameters, 'mobile': '2'});
      final resp = await client.post(submitUrl, headers: {..._headers(referer: formUrl.toString()), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Origin': base, 'X-Requested-With': 'XMLHttpRequest'}, body: payload).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      // 服务端给了提示文案(成功/无权限等)时以文案为准：此时编辑页也可能已经取不到表单，
      // 若直接按“没有表单”判定会把「无权限」误判成删除成功。
      final message = _mobileMessage(body);
      if (message != null) return message.contains('成功') ? null : message;
      // 无提示(通常是被重定向回主题页): 再确认编辑页是否已经取不到表单。
      final check = await client.get(formUrl, headers: _headers()).timeout(NetClient.timeout);
      if (_parseReplyfloorForm(NetClient.decode(check.bodyBytes)).action == null) return null;
      return '删除失败,请重试';
    } catch (_) {
      return '删除请求失败,请稍后重试';
    }
  }

  /// Comiis 移动模板 showmessage 的提示文案(成功/失败共用同一套结构)。
  String? _mobileMessage(String html) {
    final match = RegExp(r'''comiis_password_top[\s\S]{0,400}?<p[^>]*>([^<]+)</p>''').firstMatch(html);
    final text = match?.group(1)?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// 楼中楼编辑/删除操作失败时的可读错误提取。
  String _floorError(String body, String fallback) {
    final needLogin = RegExp(r'''loginform|您需要(?:先)?登录才能|未登录|登录后才能''').hasMatch(body);
    if (needLogin) return '请先登录后操作';
    final showErr = RegExp(r'''showError\(\s*['"]([^'"]+)['"]''').firstMatch(body)?.group(1) ??
        RegExp(r'''errorhandle_(?:edit|delete)mod\(\s*['"]([^'"]+)['"]''').firstMatch(body)?.group(1);
    if (showErr != null && showErr.trim().isNotEmpty) return showErr.trim();
    return fallback;
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

/// 一次登录流程内的 Cookie 罐。
///
/// `package:http` 的 IOClient 不保存 Cookie，而 Discuz 的登录提交必须带上
/// 登录页下发的 saltkey/sid，否则服务端会直接返回 503 System Error；
/// 登录成功后下发的 auth 也必须原样回传给后续请求才能维持会话。
/// 这里按「一次登录」的粒度收集并回放，避免把上一次的失效会话带进来。
class _CookieJar {
  final Map<String, String> _values = <String, String>{};

  int get length => _values.length;

  /// 是否已拿到登录凭证 Cookie（形如 `xxxx_auth`）。服务端只在登录成功时下发。
  bool get hasAuth =>
      _values.entries.any((e) => e.key.endsWith('_auth') && e.value.isNotEmpty);

  String get header =>
      _values.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// 吸收一个响应的 `Set-Cookie` 头。
  ///
  /// http 包会把多条 Set-Cookie 用逗号拼成一个字符串，因此按
  /// 「逗号 + 紧跟着 name=」切分；Expires 里的 `Wed, 15-Nov-2026` 不会命中。
  void absorb(Map<String, String> headers) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    for (final piece in raw.split(RegExp(r',\s*(?=[A-Za-z0-9_.\-]+=)'))) {
      final first = piece.split(';').first.trim();
      final index = first.indexOf('=');
      if (index <= 0) continue;
      final name = first.substring(0, index).trim();
      final value = first.substring(index + 1).trim();
      if (name.isEmpty) continue;
      final lower = piece.toLowerCase();
      final expired = value.isEmpty ||
          value.toLowerCase() == 'deleted' ||
          lower.contains('max-age=0') ||
          lower.contains('expires=thu, 01 jan 1970');
      if (expired) {
        _values.remove(name);
      } else {
        _values[name] = value;
      }
    }
  }
}
