import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'net_client.dart';

/// 原生每日签到服务，直接执行 K-Misign 签到页面中“签到”按钮的真实请求。
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

  bool _isLoggedInHtml(String html) {
    final doc = parser.parse(html);
    if (doc.querySelector(
          'a[href*="action=logout"], a[href*="logout"], .logout, #logout',
        ) !=
        null) {
      return true;
    }
    final username = AuthService.instance.username?.trim();
    if (username != null && username.isNotEmpty &&
        (doc.body?.text ?? '').contains(username)) {
      return true;
    }
    return false;
  }

  Uri? _findRealSignAction(String html, String pageUrl, String formhash) {
    final doc = parser.parse(html);
    final base = Uri.parse(pageUrl);

    // K-Misign 的实际签到按钮通常是一个带 operation=qiandao 的链接。
    // 不再自己猜 endpoint，而是直接执行网页上这个按钮对应的 URL。
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
      if (url == null || url.isEmpty) continue;

      // onclick 里可能是 javascript:xxx('...')，只取 URL 部分。
      url = url.replaceAll('\\/', '/');
      if (url.startsWith('javascript:')) continue;

      try {
        var uri = base.resolve(url);
        final qp = <String, String>{...uri.queryParameters};
        qp.putIfAbsent('formhash', () => formhash);
        if (!qp.containsKey('inajax')) qp['inajax'] = '1';
        uri = uri.replace(queryParameters: qp);
        return uri;
      } catch (_) {}
    }
    return null;
  }

  String? _resultMessage(String body) {
    if (body.contains('今天已经签到') ||
        body.contains('您今天已经签到') ||
        body.contains('今日已签') ||
        body.contains('btnvisted')) {
      return '今天已经签到';
    }
    if (body.contains('签到成功') || body.contains('恭喜')) return '签到成功';
    if (body.contains('请先登录') || body.contains('登录后')) return '登录状态已失效，请重新登录';
    if ((body.contains('formhash') &&
            (body.contains('非法') || body.contains('错误'))) ||
        body.contains('操作令牌已失效')) {
      return '签到令牌已失效，请刷新登录状态后重试';
    }
    return null;
  }

  Future<String> sign() async {
    if (!AuthService.instance.isLoggedIn) return '请先登录论坛';

    final client = await _client;
    try {
      // 第一步：完全模拟“点击每日签到后进入签到页”。
      final pageUri = Uri.parse('${_base}plugin.php?id=k_misign:sign');
      final pageResponse = await NetClient.retry(() => client.get(
            pageUri,
            headers: _headers(_base),
          ).timeout(NetClient.timeout));
      final pageHtml = NetClient.decode(pageResponse.bodyBytes);

      if (!_isLoggedInHtml(pageHtml)) {
        return '登录状态已失效，请重新登录';
      }

      final formhash = _hidden(pageHtml, 'formhash');
      if (formhash == null || formhash.isEmpty) {
        return '签到页面缺少有效的操作令牌，请刷新登录状态后重试';
      }

      // 第二步：找到网页真正的“签到”按钮，然后直接执行它。
      Uri? signUri = _findRealSignAction(pageHtml, pageUri.toString(), formhash);

      // 某些页面使用独立的签到入口，第二次获取页面后再找一次。
      if (signUri == null) {
        final fallbackUri = Uri.parse('${_base}k_misign-sign.html');
        final fallback = await client.get(
          fallbackUri,
          headers: _headers(pageUri.toString()),
        ).timeout(NetClient.timeout);
        final fallbackHtml = NetClient.decode(fallback.bodyBytes);
        final fallbackHash = _hidden(fallbackHtml, 'formhash') ?? formhash;
        signUri = _findRealSignAction(
          fallbackHtml,
          fallbackUri.toString(),
          fallbackHash,
        );
      }

      // 如果 HTML 没有暴露按钮链接，才使用 K-Misign 已知的标准入口作为最后回退。
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
            headers: _headers(pageUri.toString(), ajax: true),
          ).timeout(NetClient.timeout));
      final body = NetClient.decode(response.bodyBytes);
      final result = _resultMessage(body);
      if (result != null) return result;

      // 有些版本返回的是刷新后的签到页面，成功状态会出现在页面按钮上。
      if (body.contains('btnvisted') || body.contains('已签到')) return '签到成功';
      return '签到失败，请稍后重试';
    } catch (_) {
      return '签到请求失败，请检查网络后重试';
    }
  }
}
