import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'profile_service.dart';

class SocialUser {
  final int uid;
  final String name;
  final String avatar;
  final String subtitle;
  final bool followed;

  const SocialUser({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.subtitle,
    this.followed = false,
  });
}

class SocialService {
  SocialService._();
  static final instance = SocialService._();
  static const _base = 'https://www.ycoo.net/';

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final response = await NetClient.retry(() => client.get(
      Uri.parse('$_base$path'),
      headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      },
    ).timeout(const Duration(seconds: 20)));
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
    for (final path in paths) {
      try {
        final users = await _parseUsers(await _get(path));
        if (users.length > best.length) best = users;
        if (users.isNotEmpty) return users;
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

    final currentUid = AuthService.instance.uid ?? 0;
    final currentName = _clean(AuthService.instance.username ?? '');
    final scopes = _relationScopes(doc);
    final roots = <Element>[];
    if (scopes.isNotEmpty) {
      roots.addAll(scopes);
    } else if (doc.body != null) {
      // Document is not an Element. Use its body for the unscoped fallback.
      roots.add(doc.body!);
    }

    final seen = <int>{};
    final result = <SocialUser>[];
    for (final root in roots) {
      final links = root.querySelectorAll('a[href*="uid="],a[href*="space-uid-"]');
      for (final link in links) {
        final uid = _uidFrom(link.attributes['href'] ?? '');
        if (uid <= 0 || uid == currentUid || seen.contains(uid)) continue;

        final container = _userContainer(link, root);
        final scoped = scopes.isNotEmpty;
        if (!scoped && !_isProfileHref(link.attributes['href'] ?? '')) continue;
        if (!_looksLikeRelationItem(link, container)) continue;

        final profileAnchor = _bestProfileAnchor(container, uid) ?? link;
        var name = _extractName(profileAnchor, container, uid);
        var avatar = _extractAvatar(profileAnchor, container);
        var subtitle = _extractSubtitle(container, name, uid);

        if (_badName(name)) {
          try {
            final profile = await ProfileService.instance.fetchProfile(uid);
            if (_validProfileName(profile.username)) name = profile.username.trim();
            if (avatar.isEmpty && profile.avatar.isNotEmpty) avatar = profile.avatar;
            if (subtitle == 'UID $uid' && profile.group.isNotEmpty) {
              subtitle = 'UID $uid · ${profile.group}';
            }
          } catch (_) {}
        }

        if (_badName(name) || (currentName.isNotEmpty && name == currentName)) continue;
        seen.add(uid);
        result.add(SocialUser(uid: uid, name: name, avatar: avatar, subtitle: subtitle));
        if (result.length >= 200) return result;
      }
    }
    return result;
  }

  List<Element> _relationScopes(Document doc) {
    const selectors = <String>[
      '#ct .buddy', '#ct .buddylist', '#ct .flw_list', '#ct .flw_ulist',
      '#ct .follow_list', '#ct .friend_list', '#ct ul.buddy', '#ct ul.flw_list',
      '.buddy', '.buddylist', '.flw_list', '.flw_ulist', '.follow_list', '.friend_list',
    ];
    final found = <Element>[];
    final seen = <Element>{};
    for (final selector in selectors) {
      for (final element in doc.querySelectorAll(selector)) {
        if (seen.add(element)) found.add(element);
      }
    }
    return found;
  }

  bool _looksLikeRelationItem(Element link, Element? container) {
    final text = _clean(container?.text ?? link.text);
    if (text.length > 500) return false;
    if (container == null) return true;
    return container.querySelector('a[href*="uid="],a[href*="space-uid-"]') != null ||
        container.querySelector('img') != null;
  }

  Element? _bestProfileAnchor(Element? container, int uid) {
    if (container == null) return null;
    final candidates = container
        .querySelectorAll('a[href*="uid="],a[href*="space-uid-"]')
        .where((a) => _uidFrom(a.attributes['href'] ?? '') == uid)
        .toList();
    candidates.sort((a, b) {
      final ap = _isProfileHref(a.attributes['href'] ?? '') ? 0 : 1;
      final bp = _isProfileHref(b.attributes['href'] ?? '') ? 0 : 1;
      if (ap != bp) return ap - bp;
      return _nameScore(_clean(b.text)).compareTo(_nameScore(_clean(a.text)));
    });
    return candidates.isEmpty ? null : candidates.first;
  }

  Element? _userContainer(Element anchor, Element root) {
    Element? node = anchor.parent;
    for (var i = 0; i < 6 && node != null && node != root; i++) {
      final text = _clean(node.text);
      final hasLink = node.querySelector('a[href*="uid="],a[href*="space-uid-"]') != null;
      final hasImage = node.querySelector('img') != null;
      if (hasLink && hasImage && text.length <= 300) return node;
      if (hasLink && text.length <= 180) return node;
      node = node.parent;
    }
    return anchor.parent;
  }

  String _extractName(Element anchor, Element? container, int uid) {
    final values = <String>[
      _clean(anchor.text),
      _clean(anchor.attributes['title'] ?? ''),
      _clean(anchor.attributes['aria-label'] ?? ''),
      _clean(anchor.querySelector('img')?.attributes['alt'] ?? ''),
      _clean(container?.querySelector('.xw1,.xi2,.name,.username,.nickname,.title,.flw_name')?.text ?? ''),
      _clean(container?.attributes['title'] ?? ''),
    ];
    if (container != null) {
      for (final a in container.querySelectorAll('a[href]')) {
        if (_uidFrom(a.attributes['href'] ?? '') == uid) values.add(_clean(a.text));
      }
    }
    for (final value in values) {
      if (!_badName(value)) return value;
    }
    return '';
  }

  String _extractAvatar(Element anchor, Element? container) {
    final images = <Element>[];
    final anchorImage = anchor.querySelector('img');
    if (anchorImage != null) images.add(anchorImage);
    if (container != null) images.addAll(container.querySelectorAll('img'));
    for (final image in images) {
      final raw = (image.attributes['data-src'] ?? image.attributes['data-original'] ?? image.attributes['src'] ?? '').trim();
      if (_validImageSource(raw)) return _absolute(raw);
    }
    return '';
  }

  String _extractSubtitle(Element? container, String name, int uid) {
    if (container == null) return 'UID $uid';
    var text = _clean(container.text);
    if (name.isNotEmpty) text = text.replaceFirst(name, '').trim();
    if (text.isEmpty || text.length > 120 || _isNavigation(text)) return 'UID $uid';
    return text;
  }

  int _nameScore(String value) {
    if (_badName(value)) return -100;
    var score = 0;
    if (RegExp(r'[\u4e00-\u9fffA-Za-z0-9]').hasMatch(value)) score += 5;
    if (value.length >= 2) score += 2;
    if (value.length <= 32) score += 1;
    return score;
  }

  Future<String?> toggleFollow({required int uid, required bool follow}) async {
    if (uid <= 0 || uid == (AuthService.instance.uid ?? 0)) return '用户无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final pagePath = 'home.php?mod=spacecp&ac=follow&uid=$uid&mobile=2';
      final page = await _get(pagePath);
      final formhash = _hiddenValue(page, 'formhash');
      if (formhash.isEmpty) return '未取得操作令牌，请刷新登录状态后重试';
      final path = 'home.php?mod=spacecp&ac=follow&op=${follow ? 'add' : 'del'}&uid=$uid&mobile=2';
      final response = await NetClient.retry(() => client.post(
        Uri.parse('$_base$path'),
        headers: {
          'User-Agent': NetClient.ua,
          'Accept': 'application/json,text/html,*/*',
          'Referer': '$_base$pagePath',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
        body: {'formhash': formhash, 'uid': '$uid', 'op': follow ? 'add' : 'del', 'inajax': '1'},
      ).timeout(const Duration(seconds: 20)));
      final body = NetClient.decode(response.bodyBytes);
      if (RegExp(r'(succeed|成功|已关注|关注成功|取消关注成功)', caseSensitive: false).hasMatch(body)) return null;
      if (body.contains('登录') && body.contains('失效')) return '登录态已失效，请重新登录论坛';
      if (_tokenFailed(body)) return '操作令牌已失效，请刷新后重试';
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

  static bool _isProfileHref(String href) {
    final lower = href.toLowerCase();
    if (lower.contains('space-uid-')) return true;
    if (!lower.contains('uid=') || !lower.contains('mod=space')) return false;
    return !lower.contains('mod=spacecp') && (!lower.contains('do=') || lower.contains('do=profile'));
  }

  static String _absolute(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return value.startsWith('/') ? '$_base${value.substring(1)}' : '$_base$value';
  }

  static bool _validImageSource(String value) {
    if (value.isEmpty || value == '×' || value.toLowerCase() == 'x') return false;
    if (value.contains('�') || value.contains('\uFFFD')) return false;
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('//') || value.startsWith('/');
  }

  static bool _validProfileName(String value) => !_badName(value) &&
      !RegExp(r'^(?:用户|资料|个人资料|用户名|昵称)$').hasMatch(value.trim());

  static bool _badName(String value) {
    final v = _clean(value);
    if (v.isEmpty || v.length > 40) return true;
    if (const {
      '首页','下一页','上一页','更多','关注','粉丝','好友','删除','取消关注','帖子','主题','回帖',
      '资料','个人资料','昵称','用户名','设置','个人中心','Ta的空间','空间','我的','提示信息',
      '系统提示','温馨提示','提示','抱歉','无权','没有权限','不存在','该用户','×','x','X','××'
    }.contains(v)) return true;
    if (v.contains('�') || v.contains('\uFFFD')) return true;
    return !RegExp(r'[\u4e00-\u9fffA-Za-z0-9]').hasMatch(v);
  }

  static String _clean(String value) => value.replaceAll('\uFFFD', '�').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isNavigation(String value) => const {
    '首页','下一页','上一页','更多','关注','粉丝','好友','删除','取消关注'
  }.contains(value);

  static String _hiddenValue(String html, String name) {
    final doc = parser.parse(html);
    final input = doc.querySelector('input[name="$name"]');
    final value = (input?.attributes['value'] ?? '').trim();
    if (value.isNotEmpty) return value;
    final escaped = RegExp.escape(name);
    final patterns = <RegExp>[
      RegExp('name\\s*=\\s*["\\\']$escaped["\\\'][^>]*value\\s*=\\s*["\\\']([^"\\\']+)["\\\']', caseSensitive: false),
      RegExp('value\\s*=\\s*["\\\']([^"\\\']+)["\\\'][^>]*name\\s*=\\s*["\\\']$escaped["\\\']', caseSensitive: false),
      RegExp('(?:[?&]|\\b)$escaped(?:=|%3D)([A-Za-z0-9_-]{6,64})', caseSensitive: false),
      RegExp('["\\\']$escaped["\\\']\\s*:\\s*["\\\']([A-Za-z0-9_-]{6,64})["\\\']', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null && match.group(1)!.trim().isNotEmpty) return match.group(1)!.trim();
    }
    return '';
  }

  static bool _tokenFailed(String body) => body.contains('formhash') &&
      (body.contains('错误') || body.contains('失效') || body.contains('非法') || body.contains('验证失败'));

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) {
      node.remove();
    }
    final text = _clean(doc.body?.text ?? '');
    return text.isNotEmpty && RegExp(r'(用户名|登录密码)').hasMatch(text) &&
        text.contains('登录') && !html.contains('action=logout');
  }
}
