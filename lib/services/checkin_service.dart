import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'net_client.dart';

/// 原生每日签到服务，直接执行 K-Misign 签到请求。
class CheckinService {
  CheckinService._();
  static final instance = CheckinService._();
  static const _base = 'https://www.ycoo.net/';

  Future<http.Client> get _client async => NetClient.instance.client;

  Map<String, String> _headers(String referer, {bool ajax = false}) => {
    'User-Agent': NetClient.ua,
    'Accept': ajax ? '*/*' : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache, no-store',
    'Pragma': 'no-cache',
    'Referer': referer,
    if (ajax) 'X-Requested-With': 'XMLHttpRequest',
    if ((AuthService.instance.authCookie ?? '').isNotEmpty)
      'Cookie': AuthService.instance.authCookie!,
  };

  String? _hidden(String html, String name) {
    final document = parser.parse(html);
    for (final input in document.querySelectorAll('input')) {
      if ((input.attributes['name'] ?? '').toLowerCase() == name.toLowerCase()) {
        final value = input.attributes['value'];
        if (value != null && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  /// Discuz 不同模板会把 formhash 放在 hidden input、链接参数、JS 或 data 属性中。
  /// 不能只依赖 <input name="formhash">，否则签到页改模板后会误报令牌缺失。
  String? _extractFormhash(String html) {
    final hidden = _hidden(html, 'formhash');
    if (hidden != null && hidden.isNotEmpty) return hidden;

    final patterns = <RegExp>[
      RegExp(r'''(?:[?&]|formhash\s*[=:"']\s*)formhash(?:=|%3D|\s*[=:]\s*)["']?([a-zA-Z0-9_-]{6,64})''', caseSensitive: false),
      RegExp(r'''["']formhash["']\s*:\s*["']([a-zA-Z0-9_-]{6,64})["']''', caseSensitive: false),
      RegExp(r'''formhash=([a-zA-Z0-9_-]{6,64})''', caseSensitive: false),
    ];
    for (final re in patterns) {
      final match = re.firstMatch(html);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  bool _isLoggedInHtml(String html) {
    final doc = parser.parse(html);
    if (doc.querySelector('a[href*="action=logout"], a[href*="logout"], .logout, #logout') != null) {
      return true;
    }
    final username = AuthService.instance.username?.trim();
    if (username != null && username.isNotEmpty && (doc.body?.text ?? '').contains(username)) {
      return true;
    }
    // 已保存的 Discuz 登录 Cookie 存在时，不因为模板中出现“登录”链接就误判。
    return (AuthService.instance.authCookie ?? '').isNotEmpty;
  }

  Uri? _findRealSignAction(String html, String pageUrl, String formhash) {
    final doc = parser.parse(html);
    final base = Uri.parse(pageUrl);
    for (final element in doc.querySelectorAll('a[href], button[onclick], input[onclick]')) {
      final href = element.attributes['href'];
      final onclick = element.attributes['onclick'];
      final raw = href ?? onclick ?? '';
      if (!raw.contains('qiandao')) continue;

      String? url;
      if (href != null && href.trim().isNotEmpty) {
        url = href.trim();
      } else {
        final match = RegExp(r'''["']([^"']*(?:operation=qiandao|qiandao)[^"']*)["']''').firstMatch(raw);
        url = match?.group(1);
      }
      if (url == null || url.isEmpty || url.startsWith('javascript:')) continue;
      url = url.replaceAll('\\/', '/');
      try {
        var uri = base.resolve(url);
        final qp = <String, String>{...uri.queryParameters};
        qp.putIfAbsent('formhash', () => formhash);
        qp.putIfAbsent('inajax', () => '1');
        qp.putIfAbsent('format', () => 'empty');
        uri = uri.replace(queryParameters: qp);
        return uri;
      } catch (_) {}
    }
    return null;
  }

  String? _resultMessage(String body) {
    if (body.contains('今天已经签到') || body.contains('您今天已经签到') || body.contains('今日已签') || body.contains('btnvisted')) {
      return '今天已经签到';
    }
    if (body.contains('签到成功') || body.contains('恭喜')) return '签到成功';
    if (body.contains('请先登录') || body.contains('登录后')) return '登录状态已失效，请重新登录';
    if ((body.contains('formhash') && (body.contains('非法') || body.contains('错误'))) || body.contains('操作令牌已失效')) {
      return '签到令牌已失效，请刷新登录状态后重试';
    }
    return null;
  }

  Future<String> sign() async {
    if (!AuthService.instance.isLoggedIn) return '请先登录论坛';

    final client = await _client;
    try {
      final pages = <Uri>[
        Uri.parse('${_base}plugin.php?id=k_misign:sign'),
        Uri.parse('${_base}k_misign-sign.html'),
        Uri.parse('${_base}forum.php?mobile=2'),
      ];

      String? formhash;
      String pageUrl = pages.first.toString();
      String pageHtml = '';

      // 每次点击签到都重新请求当前登录会话的页面并提取新 token。
      for (final pageUri in pages) {
        try {
          final response = await NetClient.retry(() => client.get(
                pageUri,
                headers: _headers(_base),
              ).timeout(NetClient.timeout));
          if (response.statusCode < 200 || response.statusCode >= 400) continue;
          final html = NetClient.decode(response.bodyBytes);
          final hash = _extractFormhash(html);
          if (hash != null && hash.isNotEmpty) {
            formhash = hash;
            pageUrl = pageUri.toString();
            pageHtml = html;
            break;
          }
          // 即使当前页面没有 hash，也保留 HTML，后面可能从其中找到真实签到入口。
          if (pageHtml.isEmpty) {
            pageHtml = html;
            pageUrl = pageUri.toString();
          }
        } catch (_) {}
      }

      if (formhash == null || formhash.isEmpty) {
        return '签到页面缺少有效的操作令牌，请重新打开论坛后重试';
      }

      Uri? signUri = _findRealSignAction(pageHtml, pageUrl, formhash);
      signUri ??= Uri.parse('${_base}plugin.php').replace(
        queryParameters: {
          'id': 'k_misign:sign',
          'operation': 'qiandao',
          'formhash': formhash,
          'format': 'empty',
          'inajax': '1',
          'ajaxtarget': 'JD_sign',
        },
      );

      final response = await NetClient.retry(() => client.get(
            signUri!,
            headers: _headers(pageUrl, ajax: true),
          ).timeout(NetClient.timeout));
      final body = NetClient.decode(response.bodyBytes);
      final result = _resultMessage(body);
      if (result != null) return result;
      if (body.contains('btnvisted') || body.contains('已签到')) return '签到成功';
      return '签到失败，请稍后重试';
    } catch (_) {
      return '签到请求失败，请检查网络后重试';
    }
  }
}
