import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'net_client.dart';

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
    if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!,
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
    if (doc.querySelector('a[href*="action=logout"], a[href*="logout"], .logout, #logout') != null) return true;
    final username = AuthService.instance.username?.trim();
    if (username != null && username.isNotEmpty && (doc.body?.text ?? '').contains(username)) return true;
    return false;
  }

  Future<String?> _getFormhash(http.Client client) async {
    final urls = <String>[
      '${_base}plugin.php?id=k_misign:sign',
      '${_base}k_misign-sign.html',
      '${_base}forum.php?mobile=2',
    ];
    for (final raw in urls) {
      try {
        final response = await client.get(Uri.parse(raw), headers: _headers(_base)).timeout(NetClient.timeout);
        if (response.statusCode < 200 || response.statusCode >= 400) continue;
        final hash = _hidden(NetClient.decode(response.bodyBytes), 'formhash');
        if (hash != null) return hash;
      } catch (_) {}
    }
    return null;
  }

  Future<String> sign() async {
    if (!AuthService.instance.isLoggedIn) return '请先登录论坛';
    final client = await _client;
    try {
      final sessionPage = await client.get(Uri.parse('${_base}forum.php?mobile=2'), headers: _headers(_base)).timeout(NetClient.timeout);
      final sessionHtml = NetClient.decode(sessionPage.bodyBytes);
      // 页面中经常同时存在“登录/注册”链接，不能用 contains('登录') 判断会话失效。
      if (!_isLoggedInHtml(sessionHtml)) return '登录状态已失效，请重新登录';

      final formhash = await NetClient.retry(() => _getFormhash(client));
      if (formhash == null || formhash.isEmpty) return '签到页面缺少有效的操作令牌，请刷新登录状态后重试';

      final params = {'operation': 'qiandao', 'formhash': formhash, 'format': 'empty', 'inajax': '1', 'ajaxtarget': 'JD_sign'};
      final endpoints = <Uri>[
        Uri.parse('${_base}plugin.php').replace(queryParameters: {'id': 'k_misign:sign', ...params}),
        Uri.parse('${_base}k_misign-sign.html').replace(queryParameters: {'operation': 'qiandao', 'format': 'button', ...params}),
      ];
      String lastBody = '';
      for (final endpoint in endpoints) {
        final response = await NetClient.retry(() => client.get(endpoint, headers: _headers('${_base}plugin.php?id=k_misign:sign', ajax: true)).timeout(NetClient.timeout));
        lastBody = NetClient.decode(response.bodyBytes);
        if (response.statusCode < 200 || response.statusCode >= 400) continue;
        if (lastBody.contains('今天已经签到') || lastBody.contains('您今天已经签到') || lastBody.contains('今日已签') || lastBody.contains('btnvisted')) return '今天已经签到';
        if (lastBody.contains('签到成功') || lastBody.contains('恭喜')) return '签到成功';
      }
      if (lastBody.contains('请先登录') || lastBody.contains('登录后')) return '登录状态已失效，请重新登录';
      if ((lastBody.contains('formhash') && (lastBody.contains('非法') || lastBody.contains('错误'))) || lastBody.contains('操作令牌已失效')) return '签到令牌已失效，请刷新登录状态后重试';
      return '签到失败，请稍后重试';
    } catch (_) {
      return '签到请求失败，请检查网络后重试';
    }
  }
}
