import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// Discuz 私信发送器。
///
/// 私信发送必须使用“当前登录会话”页面里的实时 formhash。
/// 不复用登录页/旧页面令牌，并把收件人 UID 一起提交，兼容 Comiis/Discuz 移动模板。
class PrivateMessageService {
  PrivateMessageService._();
  static final instance = PrivateMessageService._();

  static String get _base => SiteConfig.base;

  Map<String, String> _headers(String cookie) => <String, String>{
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if (cookie.isNotEmpty) 'Cookie': cookie,
      };

  Future<String?> send({
    required int touid,
    required String username,
    required String message,
  }) async {
    final target = username.trim();
    final text = message.trim();
    if (target.isEmpty) return '请输入收件人用户名';
    if (text.isEmpty) return '请输入私信内容';

    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) return '请先登录论坛';
    final cookie = AuthService.instance.authCookie?.trim() ?? '';
    if (cookie.isEmpty) return '登录态已失效，请重新登录论坛';

    try {
      final client = await NetClient.instance.client;
      final baseHeaders = _headers(cookie);

      // 必须从“发送私信”页面取得本次会话的 formhash。
      // 某些 Comiis 版本只有带 touid 时才渲染发送表单，因此优先带 UID 请求。
      final candidates = <Uri>[
        Uri.parse('${_base}home.php').replace(queryParameters: {
          'mod': 'spacecp',
          'ac': 'pm',
          'op': 'send',
          if (touid > 0) 'touid': '$touid',
          'mobile': '2',
          '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
        }),
        Uri.parse('${_base}home.php').replace(queryParameters: {
          'mod': 'space',
          'do': 'pm',
          'subop': 'view',
          if (touid > 0) 'touid': '$touid',
          'mobile': '2',
          '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
        }),
        Uri.parse('${_base}home.php').replace(queryParameters: {
          'mod': 'space',
          'do': 'pm',
          'mobile': '2',
          '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
        }),
        Uri.parse('${_base}forum.php').replace(queryParameters: {
          'mobile': '2',
          '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
        }),
      ];

      String? formhash;
      Uri? referer;
      for (final uri in candidates) {
        try {
          final response = await client.get(
            uri,
            headers: {
              ...baseHeaders,
              'Referer': '${_base}home.php?mod=space&do=pm&mobile=2',
            },
          ).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) continue;
          final html = NetClient.decode(response.bodyBytes);
          if (_looksLikeLogin(html)) return '登录态已失效，请重新登录论坛';
          final candidate = _formhashFromHtml(html);
          if (candidate.isNotEmpty) {
            formhash = candidate;
            referer = uri;
            break;
          }
        } catch (_) {}
      }

      if (formhash == null || formhash.isEmpty) {
        return '未取得私信令牌(formhash)，请刷新登录状态后重试';
      }

      final sendUri = Uri.parse('${_base}home.php').replace(queryParameters: {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'send',
        'mobile': '2',
        'inajax': '1',
      });

      final response = await client.post(
        sendUri,
        headers: {
          ...baseHeaders,
          'Referer': (referer ?? Uri.parse('${_base}home.php?mod=space&do=pm&mobile=2')).toString(),
          'Origin': _base,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: <String, String>{
          'formhash': formhash,
          'touid': touid > 0 ? '$touid' : '',
          'username': target,
          'message': text,
          'pmsubmit': 'yes',
          'sendpm': 'true',
          'inajax': '1',
        },
      ).timeout(const Duration(seconds: 20));

      final body = NetClient.decode(response.bodyBytes);
      if (_looksLikeSuccess(body)) return null;
      if (_looksLikeLogin(body)) return '登录态已失效，请重新登录论坛';
      if (_looksLikeTokenError(body)) {
        // 令牌可能在 GET 与 POST 间过期；重新抓一次实时 token 后只重试一次。
        final retryHash = await _fetchFreshFormhash(client, baseHeaders, touid);
        if (retryHash != null && retryHash.isNotEmpty && retryHash != formhash) {
          final retry = await client.post(
            sendUri,
            headers: {
              ...baseHeaders,
              'Referer': (referer ?? Uri.parse('${_base}home.php?mod=space&do=pm&mobile=2')).toString(),
              'Origin': _base,
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'X-Requested-With': 'XMLHttpRequest',
            },
            body: <String, String>{
              'formhash': retryHash,
              'touid': touid > 0 ? '$touid' : '',
              'username': target,
              'message': text,
              'pmsubmit': 'yes',
              'sendpm': 'true',
              'inajax': '1',
            },
          ).timeout(const Duration(seconds: 20));
          final retryBody = NetClient.decode(retry.bodyBytes);
          if (_looksLikeSuccess(retryBody)) return null;
          if (_looksLikeLogin(retryBody)) return '登录态已失效，请重新登录论坛';
          return _messageFromResponse(retryBody) ?? '私信发送失败，请稍后重试';
        }
        return '私信令牌已失效，请刷新登录状态后重试';
      }
      return _messageFromResponse(body) ?? '私信发送失败，请稍后重试';
    } catch (_) {
      return '私信请求失败，请检查网络后重试';
    }
  }

  Future<String?> _fetchFreshFormhash(
    dynamic client,
    Map<String, String> headers,
    int touid,
  ) async {
    try {
      final uri = Uri.parse('${_base}home.php').replace(queryParameters: {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'send',
        if (touid > 0) 'touid': '$touid',
        'mobile': '2',
        '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
      });
      final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      return _formhashFromHtml(NetClient.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String _formhashFromHtml(String html) {
    // 1. 标准 Discuz hidden input，兼容 name/value 顺序和大小写。
    final inputRe = RegExp(r'<input\b[^>]*>', caseSensitive: false);
    final nameFirst = RegExp(
      r'''name\s*=\s*["']formhash["'][^>]*value\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final valueFirst = RegExp(
      r'''value\s*=\s*["']([^"']+)["'][^>]*name\s*=\s*["']formhash["']''',
      caseSensitive: false,
    );
    for (final match in inputRe.allMatches(html)) {
      final tag = match.group(0)!;
      final a = nameFirst.firstMatch(tag)?.group(1)?.trim();
      if (a != null && _validFormhash(a)) return a;
      final b = valueFirst.firstMatch(tag)?.group(1)?.trim();
      if (b != null && _validFormhash(b)) return b;
    }

    // 2. Discuz/Comiis 常见 JS 变量形式。
    final patterns = <RegExp>[
      RegExp(r'''(?:formhash|formHash)\s*[:=]\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
      RegExp(r'''["']formhash["']\s*[,=:]\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
      RegExp(r'''(?:data-formhash|data-formHash)\s*=\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1)?.trim();
      if (value != null && _validFormhash(value)) return value;
    }
    return '';
  }

  static bool _validFormhash(String value) => RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(value);

  static bool _looksLikeLogin(String body) =>
      body.contains('请登录') || body.contains('登录后才能') || body.contains('loginhash') && body.contains('logging');

  static bool _looksLikeTokenError(String body) =>
      body.contains('formhash') || body.contains('操作令牌') || body.contains('请求令牌') || body.contains('token');

  static bool _looksLikeSuccess(String body) =>
      body.contains('succeed') || body.contains('do_success') || body.contains('发送成功') || body.contains('操作成功');

  static String? _messageFromResponse(String body) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1);
    final source = (cdata ?? body)
        .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (source.isEmpty || source.length > 160) return null;
    if (source.contains('私信') || source.contains('消息') || source.contains('用户') || source.contains('权限') || source.contains('登录') || source.contains('失败')) {
      return source;
    }
    final showError = RegExp(r'''showError\(\s*["']([^"']+)["']''').firstMatch(body)?.group(1)?.trim();
    return showError?.isNotEmpty == true ? showError : null;
  }
}
