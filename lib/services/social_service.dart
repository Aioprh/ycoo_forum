import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';

class SocialUser {
  final int uid;
  final String name;
  final String avatar;
  final String subtitle;
  final bool followed;
  const SocialUser({required this.uid, required this.name, required this.avatar, required this.subtitle, this.followed = false});
}

class SocialService {
  SocialService._();
  static final instance = SocialService._();
  static const _base = 'https://www.ycoo.net/';

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final response = await NetClient.retry(() => client.get(Uri.parse('$_base$path'), headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
    final html = NetClient.decode(response.bodyBytes);
    if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
    return html;
  }

  Future<List<SocialUser>> fetchFriends() => _fetch('home.php?mod=space&do=friend&view=me&mobile=2');
  Future<List<SocialUser>> fetchFollowing() => _fetch('home.php?mod=space&do=follow&view=following&mobile=2');
  Future<List<SocialUser>> fetchFollowers() => _fetch('home.php?mod=space&do=follow&view=follower&mobile=2');

  Future<List<SocialUser>> _fetch(String path) async {
    final doc = parser.parse(await _get(path));
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    final result = <SocialUser>[];
    final seen = <int>{};
    for (final a in doc.querySelectorAll('a[href*="uid="],a[href*="space-uid-"]')) {
      final uid = _uidFrom(a.attributes['href'] ?? '');
      if (uid <= 0 || seen.contains(uid)) continue;
      final name = _clean(a.text);
      if (name.isEmpty || name.length > 40 || _isNavigation(name)) continue;
      final root = a.parent;
      final text = _clean(root?.text ?? '');
      var subtitle = text.replaceFirst(name, '').trim();
      if (subtitle.isEmpty || subtitle.length > 120) subtitle = 'UID $uid';
      var avatar = '';
      final img = root?.querySelector('img');
      if (img != null) avatar = _absolute((img.attributes['data-src'] ?? img.attributes['src'] ?? '').trim());
      seen.add(uid);
      result.add(SocialUser(uid: uid, name: name, avatar: avatar, subtitle: subtitle));
      if (result.length >= 200) break;
    }
    return result;
  }

  Future<String?> toggleFollow({required int uid, required bool follow}) async {
    if (uid <= 0) return '用户无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final pagePath = 'home.php?mod=spacecp&ac=follow&uid=$uid&mobile=2';
      final page = await _get(pagePath);
      final formhash = _hiddenValue(page, 'formhash');
      if (formhash.isEmpty) return '未取得操作令牌，请刷新登录状态后重试';
      final path = 'home.php?mod=spacecp&ac=follow&op=${follow ? 'add' : 'del'}&uid=$uid&mobile=2';
      final response = await NetClient.retry(() => client.post(Uri.parse('$_base$path'), headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'application/json,text/html,*/*',
        'Referer': '$_base$pagePath',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        if (cookie.isNotEmpty) 'Cookie': cookie,
      }, body: {'formhash': formhash, 'uid': '$uid', 'op': follow ? 'add' : 'del', 'inajax': '1'}).timeout(const Duration(seconds: 20)));
      final body = NetClient.decode(response.bodyBytes);
      if (RegExp(r'(succeed|成功|已关注|关注成功|取消关注成功)', caseSensitive: false).hasMatch(body)) return null;
      if (body.contains('登录') && body.contains('失效')) return '登录态已失效，请重新登录论坛';
      return follow ? '关注失败，请稍后重试' : '取消关注失败，请稍后重试';
    } catch (_) {
      return '操作失败，请检查网络后重试';
    }
  }

  static int _uidFrom(String href) {
    final uri = Uri.tryParse(href);
    final q = uri?.queryParameters['uid'];
    if (q != null) return int.tryParse(q) ?? 0;
    final m = RegExp(r'(?:space-uid-|uid=)(\d+)', caseSensitive: false).firstMatch(href);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  static String _absolute(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return value.startsWith('/') ? '$_base${value.substring(1)}' : '$_base$value';
  }

  static String _hiddenValue(String html, String name) {
    final doc = parser.parse(html);
    final input = doc.querySelector('input[name="$name"]');
    return (input?.attributes['value'] ?? '').trim();
  }

  static String _clean(String value) => value.replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  static bool _isNavigation(String value) => const {'首页', '下一页', '上一页', '更多', '关注', '粉丝', '好友', '删除'}.contains(value);

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    final text = _clean(doc.body?.text ?? '');
    return text.isNotEmpty && RegExp(r'(用户名|登录密码)').hasMatch(text) && text.contains('登录') && !html.contains('action=logout');
  }
}
