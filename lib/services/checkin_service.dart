import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'net_client.dart';

/// 原生每日签到服务，适配 Discuz K_Misign。
class CheckinService {
  CheckinService._();
  static final instance = CheckinService._();
  static const _base = 'https://www.ycoo.net/';

  Future<http.Client> get _client async => NetClient.instance.client;

  Map<String, String> _headers(String referer) => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache',
        'Referer': referer,
        'X-Requested-With': 'XMLHttpRequest',
        if ((AuthService.instance.authCookie ?? '').isNotEmpty)
          'Cookie': AuthService.instance.authCookie!,
      };

  String? _hidden(String html, String name) {
    final document = parser.parse(html);
    for (final input in document.querySelectorAll('input')) {
      if ((input.attributes['name'] ?? '').toLowerCase() == name.toLowerCase()) {
        final value = input.attributes['value'];
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Future<String> sign() async {
    if (!AuthService.instance.isLoggedIn) return '请先登录论坛';

    final client = await _client;
    final signUrl = Uri.parse('${_base}k_misign-sign.html?_ycoo_ts=${DateTime.now().millisecondsSinceEpoch}');
    try {
      final page = await NetClient.retry(() => client
          .get(signUrl, headers: _headers(_base))
          .timeout(NetClient.timeout));
      final html = NetClient.decode(page.bodyBytes);

      if (html.contains('今天已经签到') || html.contains('您今天已经签到') || html.contains('btnvisted')) {
        return '今天已经签到';
      }

      final formhash = _hidden(html, 'formhash');
      if (formhash == null || formhash.isEmpty) return '签到页面缺少 formhash';

      final endpoint = Uri.parse(
        '${_base}k_misign-sign.html?operation=qiandao&format=button&formhash=${Uri.encodeQueryComponent(formhash)}&inajax=1&ajaxtarget=JD_sign',
      );
      final response = await NetClient.retry(() => client.post(
            endpoint,
            headers: {
              ..._headers(signUrl.toString()),
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            },
            body: const <String, String>{},
          ).timeout(NetClient.timeout));
      final body = NetClient.decode(response.bodyBytes);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (body.contains('签到成功') || body.contains('恭喜') || body.contains('已经签到')) return '签到成功';
        if (body.contains('今天已经签到') || body.contains('您今天已经签到')) return '今天已经签到';
      }
      return '签到失败，请稍后重试';
    } catch (_) {
      return '签到请求失败，请检查网络后重试';
    }
  }
}
