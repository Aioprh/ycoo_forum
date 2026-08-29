import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 原生登录 / 会话服务。
///
/// 用一个保持 Cookie 的 [HttpClient] 与 Discuz!X 站点交互:
/// 先 GET 登录页取 `formhash` 与 `loginhash`,再 POST 登录接口;
/// 登录成功会下发 `<cookiepre>auth` Cookie,据此判断并持久化会话。
/// 登录态保存在 SharedPreferences,冷启动后自动恢复。
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String base = 'https://www.ycoo.net/';
  static const String loginPath =
      'member.php?mod=logging&action=login&mobile=2';
  static const String logoutPath =
      'member.php?mod=logging&action=logout&mobile=2';
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 10) YcoForum/1.0';
  static const String _prefKey = 'ycoo.session.cookies.v1';

  final HttpClient _io = HttpClient()
    ..followRedirects = false
    ..autoUncompress = true;

  final Map<String, String> _cookies = {};
  String _cookiepre = 'YPSa_2132_';
  bool _ready = false;
  bool _loggedIn = false;

  /// 会话中是否持有 auth Cookie(视为已登录)。
  bool get isLoggedIn => _loggedIn;

  /// 已登录用户名(来自会话 Cookie,可能为空)。
  String? get username => _cookies['${_cookiepre}username'];

  /// 组装当前会话的 Cookie 请求头,供其它需登录的请求复用。
  String get sessionCookie => _cookieHeader();

  /// Cookie 前缀,如 `YPSa_2132_`,供拼接 auth/username 等键。
  String get cookiepre => _cookiepre;

  /// 加载本地保存的会话。可重复调用;失败时降级为未登录。
  Future<void> init() async {
    if (_ready) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _cookies.clear();
        m.forEach((k, v) {
          if (v is String && v.isNotEmpty) _cookies[k] = v;
        });
        // 根据保存的 `xxxusername` 键反推 cookie 前缀。
        String? cp;
        for (final k in _cookies.keys) {
          if (k.endsWith('username')) {
            cp = k.substring(0, k.length - 'username'.length);
            break;
          }
        }
        if (cp != null && cp.isNotEmpty) _cookiepre = cp;
        _loggedIn = _hasAuth();
      }
    } catch (_) {
      _cookies.clear();
      _loggedIn = false;
    }
    _ready = true;
  }

  /// 原生登录。成功返回 true,并持久化会话;失败返回 false。
  Future<bool> login(
    String account,
    String password, {
    String questionId = '0',
    String answer = '',
  }) async {
    await init();
    final page = await _request('GET', loginPath);
    if (page.isEmpty) return false;

    final formhash =
        _first(RegExp(r'''name="formhash"[^>]*value=['"]?([0-9a-f]{8})'''),
            page) ??
        _first(RegExp(r'''formhash\s*=\s*['"]?([0-9a-f]{8})'''), page) ??
        '';
    final loginhash =
        _first(RegExp(r'loginhash=([A-Za-z0-9]+)'), page) ?? '';
    final cookiepre = _first(RegExp(r'''cookiepre\s*=\s*['"]([^'"]+)'''), page);
    if (cookiepre != null && cookiepre.isNotEmpty) _cookiepre = cookiepre;

    var referer = _first(
            RegExp(r'''name="referer"[^>]*value=['"]?([^'">]+)'''), page) ??
        base;
    referer = referer
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .trim();

    final md5Password = md5.convert(utf8.encode(password)).toString();
    final suffix = StringBuffer('member.php?mod=logging&action=login'
        '&loginsubmit=yes');
    if (loginhash.isNotEmpty) suffix.write('&loginhash=$loginhash');
    suffix.write('&mobile=2');

    await _request(
      'POST',
      suffix.toString(),
      form: {
        'formhash': formhash,
        'referer': referer,
        'fastloginfield': 'username',
        'cookietime': '31104000',
        'username': account,
        'password': md5Password,
        'questionid': questionId,
        'answer': answer,
      },
    );

    _loggedIn = _hasAuth();
    if (_loggedIn) {
      _cookies['${_cookiepre}username'] = account;
      await _save();
    }
    return _loggedIn;
  }

  /// 登出:尽力请求站点登出,并清空本地会话。
  Future<void> logout() async {
    if (_ready == false) return;
    try {
      await _request('GET', logoutPath, timeout: const Duration(seconds: 8));
    } catch (_) {
      // 忽略网络失败,本地仍然登出。
    }
    _cookies.clear();
    _loggedIn = false;
    _ready = true;
    await _save();
  }

  // ------------------------------------------------------------------
  // Cookie 化的 HTTP 请求(不自动跟随重定向,便于抓取 set-cookie)
  // ------------------------------------------------------------------

  Future<String> _request(
    String method,
    String path, {
    Map<String, String>? form,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    var url = Uri.parse(base + path);
    for (var hop = 0; hop < 8; hop++) {
      final req = await _io.openUrl(method, url);
      final ch = _cookieHeader();
      if (ch.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, ch);
      if (method == 'POST' && form != null) {
        req.headers.set(HttpHeaders.contentTypeHeader,
            'application/x-www-form-urlencoded; charset=utf-8');
        req.write(_encodeForm(form));
      }
      final resp = await req.close().timeout(timeout);
      final setCookies = resp.headers[HttpHeaders.setCookieHeader];
      if (setCookies != null) {
        for (final c in setCookies) {
          _feed(c);
        }
      }
      final status = resp.statusCode;
      final location = resp.headers[HttpHeaders.locationHeader];
      final body = await _readBody(resp);
      if (status >= 300 && status < 400 && location != null &&
          location.isNotEmpty) {
        // 遵循浏览器行为:POST 提交后的 3xx 重定向改走 GET,不再重复提交表单。
        if (method == 'POST') {
          method = 'GET';
          form = null;
        }
        url = url.resolve(location);
        continue;
      }
      return body;
    }
    throw const HttpException('too many redirects');
  }

  Future<String> _readBody(HttpClientResponse resp) async {
    final buf = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      buf.add(chunk);
    }
    return utf8.decode(buf.toBytes(), allowMalformed: true);
  }

  String _encodeForm(Map<String, String> fields) {
    final parts = <String>[];
    fields.forEach((k, v) {
      parts.add('${Uri.encodeQueryComponent(k)}='
          '${Uri.encodeQueryComponent(v)}');
    });
    return parts.join('&');
  }

  String _cookieHeader() {
    if (_cookies.isEmpty) return '';
    return _cookies.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
  }

  bool _hasAuth() => _cookies.containsKey('${_cookiepre}auth');

  void _feed(String header) {
    final segs = header.split(';');
    if (segs.isEmpty) return;
    final first = segs.first.trim();
    final eq = first.indexOf('=');
    if (eq <= 0) return;
    final name = first.substring(0, eq).trim();
    var value = first.substring(eq + 1).trim();

    int? maxAge;
    String? expires;
    for (final s in segs.skip(1)) {
      final t = s.trim();
      final lower = t.toLowerCase();
      if (lower.startsWith('max-age=')) {
        maxAge = int.tryParse(lower.substring('max-age='.length));
      } else if (lower.startsWith('expires=')) {
        expires = t.substring('expires='.length).trim();
      }
    }

    var expired = false;
    if (value.toLowerCase() == 'deleted') {
      expired = true;
    } else if (maxAge != null) {
      expired = maxAge <= 0;
    } else if (expires != null) {
      expired = _isPastDate(expires);
    }

    if (expired || value.isEmpty) {
      _cookies.remove(name);
    } else {
      _cookies[name] = value;
    }
  }

  bool _isPastDate(String v) {
    final cleaned = v.replaceFirst(' GMT', 'Z').replaceFirst(' GMT+0800', 'Z');
    final parsed = DateTime.tryParse(cleaned);
    if (parsed == null) {
      final m = RegExp(
              r'^\w+, (\d+)-(\w+)-(\d{4}) (\d{2}):(\d{2}):(\d{2})')
          .firstMatch(v);
      if (m == null) return false;
      final months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final month = months[m.group(2)];
      if (month == null) return false;
      return DateTime.utc(
        int.parse(m.group(3)!),
        month,
        int.parse(m.group(1)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      ).isBefore(DateTime.now().toUtc());
    }
    return parsed.isBefore(DateTime.now());
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, jsonEncode(_cookies));
    } catch (_) {
      // 持久化失败不影响内存登录态。
    }
  }

  static String? _first(RegExp re, String s) {
    final m = re.firstMatch(s);
    return m?.group(1);
  }
}