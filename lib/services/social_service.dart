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

  Future<List<SocialUser>> fetchFriends() => _fetchCandidates([
        'home.php?mod=space&do=friend&view=me&mobile=2',
        'home.php?mod=space&do=friend&view=me',
        'home.php?mod=space&do=friend&mobile=2',
        'home.php?mod=space&do=friend',
      ]);

  Future<List<SocialUser>> fetchFollowing() => _fetchCandidates([
        'home.php?mod=space&do=follow&view=following&mobile=2',
        'home.php?mod=space&do=follow&view=following',
        'home.php?mod=follow&view=following&mobile=2',
        'home.php?mod=follow&view=following',
      ]);

  Future<List<SocialUser>> fetchFollowers() => _fetchCandidates([
        'home.php?mod=space&do=follow&view=follower&mobile=2',
        'home.php?mod=space&do=follow&view=follower',
        'home.php?mod=follow&view=follower&mobile=2',
        'home.php?mod=follow&view=follower',
      ]);

  Future<List<SocialUser>> _fetchCandidates(List<String> paths) async {
    Object? last;
    List<SocialUser> best = const [];
    var bestScore = -1;
    for (final path in paths) {
      try {
        final users = await _parseUsers(await _get(path));
        final score = _qualityScore(users);
        if (score > bestScore) {
          best = users;
          bestScore = score;
        }
        if (users.isNotEmpty && score >= users.length * 4) return users;
      } catch (e) {
        last = e;
      }
    }
    if (best.isNotEmpty) return best;
    if (last != null) throw last!;
    return const [];
  }

  Future<List<SocialUser>> _parseUsers(String html) async {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) {
      node.remove();
    }

    final result = <SocialUser>[];
    final seen = <int>{};
    final links = doc.querySelectorAll('a[href*="uid="],a[href*="space-uid-"]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';
      final uid = _uidFrom(href);
      if (uid <= 0 || seen.contains(uid)) continue;

      var name = _clean(a.text);
      if (_badName(name)) name = _clean(a.attributes['title'] ?? a.attributes['aria-label'] ?? '');
      if (_badName(name)) name = _clean(a.querySelector('img')?.attributes['alt'] ?? '');
      if (_badName(name)) {
        final parent = a.parent;
        final candidates = <String>[
          _clean(parent?.querySelector('.xw1,.xi2,.name,.username,.title')?.text ?? ''),
          _clean(parent?.attributes['title'] ?? ''),
        ];
        for (final candidate in candidates) {
          if (!_badName(candidate)) {
            name = candidate;
            break;
          }
        }
      }
      if (_badName(name)) continue;

      final container = _userContainer(a);
      final containerText = _clean(container?.text ?? '');
      var subtitle = containerText.replaceFirst(name, '').trim();
      if (subtitle.length > 120 || _isNavigation(subtitle)) subtitle = '';
      if (subtitle.isEmpty) subtitle = 'UID $uid';

      var avatar = '';
      final image = a.querySelector('img') ?? container?.querySelector('img');
      if (image != null) {
        avatar = _absolute((image.attributes['data-src'] ?? image.attributes['data-original'] ?? image.attributes['src'] ?? '').trim());
      }

      seen.add(uid);
      result.add(SocialUser(uid: uid, name: name, avatar: avatar, subtitle: subtitle));
      if (result.length >= 200) break;
    }
    return result;
  }

  dynamic _userContainer(dynamic anchor) {
    var node = anchor.parent;
    for (var i = 0; i < 4 && node != null; i++) {
      final text = _clean(node.text ?? '');
      final hasUserAction = node.querySelector('a[href*="space"],a[href*="uid="],img') != null;
      if (hasUserAction && text.length <= 240) return node;
      node = node.parent;
    }
    return anchor.parent;
  }

  int _qualityScore(List<SocialUser> users) {
    if (users.isEmpty) return 0;
    var score = users.length * 2;
    for (final user in users) {
      if (user.name.contains('�')) score -= 5;
      if (user.name.length >= 2) score += 2;
      if (RegExp(r'[\u4e00-\u9fffA-Za-z0-9]').hasMatch(user.name)) score += 1;
      if (user.avatar.isNotEmpty) score += 1;
    }
    return score;
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

  static bool _badName(String value) {
    if (value.isEmpty || value.length > 40) return true;
    if (const {'首页', '下一页', '上一页', '更多', '关注', '粉丝', '好友', '删除'}.contains(value)) return true;
    return value.replaceAll('�', '').trim().isEmpty;
  }

  static String _clean(String value) => value.replaceAll('\uFFFD', '�').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isNavigation(String value) => const {'首页', '下一页', '上一页', '更多', '关注', '粉丝', '好友', '删除', '取消关注'}.contains(value);

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    final text = _clean(doc.body?.text ?? '');
    return text.isNotEmpty && RegExp(r'(用户名|登录密码)').hasMatch(text) && text.contains('登录') && !html.contains('action=logout');
  }
}
