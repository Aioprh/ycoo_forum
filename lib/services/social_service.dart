import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
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
  static String get _base => SiteConfig.base;

  /// 从已加载的页面中缓存的 formhash —— 用户能看到列表说明这个令牌一定有效。
  static String _cachedFormhash = '';

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
            'Pragma': 'no-cache',
            if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
          },
        ).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) {
      throw Exception('请求失败 HTTP ${response.statusCode}');
    }
    final html = NetClient.decode(response.bodyBytes);
    if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
    // 每次请求后都尝试提取并缓存 formhash
    _tryCacheFormhash(html);
    return html;
  }

  static void _tryCacheFormhash(String html) {
    final token = _hiddenValue(html, 'formhash');
    if (token.isNotEmpty) _cachedFormhash = token;
  }

  int get _currentUid => AuthService.instance.uid ?? 0;

  Future<List<SocialUser>> fetchFollowing() => _fetch(
        'home.php?mod=follow&do=following&uid=$_currentUid&mobile=2',
        followed: true,
      );

  Future<List<SocialUser>> fetchFollowers() => _fetch(
        'home.php?mod=follow&do=follower&uid=$_currentUid&mobile=2',
        followed: false,
      );

  Future<List<SocialUser>> fetchFriends() => _fetch(
        'home.php?mod=space&do=friend&view=me&uid=$_currentUid&mobile=2',
        followed: true,
      );

  Future<List<SocialUser>> _fetch(String path, {required bool followed}) async {
    final html = await _get(path);
    return _parseUsers(html, followed: followed);
  }

  Future<List<SocialUser>> _parseUsers(
    String html, {
    required bool followed,
  }) async {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) {
      node.remove();
    }

    final currentUid = _currentUid;
    final currentName = _clean(AuthService.instance.username ?? '');
    final seen = <int>{};
    final result = <SocialUser>[];

    // Discuz 不同模板的关注列表链接并不统一：有的使用
    // home.php?mod=space&uid=xxx，有的使用 fuid=xxx / followuid=xxx。
    // 因此不能只筛选 mod=space，否则真实关注用户会被整个过滤掉。
    final anchors = doc.querySelectorAll('a[href]');

    for (final anchor in anchors) {
      final href = anchor.attributes['href'] ?? '';
      final uid = _uidFrom(href);
      if (uid <= 0 || uid == currentUid || seen.contains(uid)) continue;

      // 当前关系页中的 uid/fuid/followuid 才是候选关系用户。
      // 排除明确属于当前操作页的 UID 参数，避免把页头自己的资料识别进去。
      if (!_isRelationUserHref(href)) continue;

      final container = _userContainer(anchor);
      final profileAnchor = _findProfileAnchor(container, uid) ??
          (_isProfileHref(href) ? anchor : null);

      var name = _extractName(profileAnchor ?? anchor, container);
      var avatar = _extractAvatar(profileAnchor ?? anchor, container);
      var subtitle = _extractSubtitle(container, name, uid);

      // 有些移动模板的关系项只有 fuid/followuid 操作链接，没有独立
      // 的个人空间链接。此时 UID 已经从关系项确认，允许通过 UID 拉取
      // 真实资料，避免回退成当前用户。
      if (_badName(name) || avatar.isEmpty) {
        try {
          final profile = await ProfileService.instance.fetchProfile(uid);
          if (_validProfileName(profile.username)) {
            name = profile.username.trim();
          }
          if (avatar.isEmpty && profile.avatar.isNotEmpty) {
            avatar = profile.avatar;
          }
          if (subtitle == 'UID $uid' && profile.group.isNotEmpty) {
            subtitle = 'UID $uid · ${profile.group}';
          }
        } catch (_) {}
      }

      if (_badName(name)) continue;
      if (currentName.isNotEmpty && name == currentName) continue;

      seen.add(uid);
      result.add(SocialUser(
        uid: uid,
        name: name,
        avatar: avatar,
        subtitle: subtitle,
        followed: followed,
      ));
      if (result.length >= 200) break;
    }

    return result;
  }

  bool _isRelationUserHref(String href) {
    final lower = href.toLowerCase();
    if (lower.contains('space-uid-')) return true;

    // 个人空间链接。
    if (_isProfileHref(href)) return true;

    // 关注/粉丝列表中常见的目标 UID 参数。
    if (RegExp(r'(?:[?&](?:fuid|followuid)=\d+)', caseSensitive: false)
        .hasMatch(lower)) {
      return true;
    }

    return false;
  }

  Element? _userContainer(Element anchor) {
    Element? node = anchor.parent;
    for (var i = 0; i < 7 && node != null; i++) {
      final text = _clean(node.text);
      final hasTarget = node.querySelector(
            'a[href*="mod=space"][href*="uid="],'
            'a[href*="space-uid-"],'
            'a[href*="fuid="],'
            'a[href*="followuid="]',
          ) !=
          null;
      final hasImage = node.querySelector('img') != null;
      if (hasTarget && hasImage && text.length <= 350) return node;
      if (hasTarget && text.length <= 220) return node;
      node = node.parent;
    }
    return anchor.parent;
  }

  Element? _findProfileAnchor(Element? container, int uid) {
    if (container == null) return null;
    final candidates = container.querySelectorAll('a[href]').where((a) {
      final href = a.attributes['href'] ?? '';
      return _uidFrom(href) == uid && _isProfileHref(href);
    }).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => _nameScore(_clean(b.text))
        .compareTo(_nameScore(_clean(a.text))));
    return candidates.first;
  }

  String _extractName(Element anchor, Element? container) {
    final values = <String>[
      _clean(anchor.text),
      _clean(anchor.attributes['title'] ?? ''),
      _clean(anchor.attributes['aria-label'] ?? ''),
      _clean(anchor.querySelector('img')?.attributes['alt'] ?? ''),
      _clean(container?.querySelector(
                '.xw1,.xi2,.name,.username,.nickname,.title,.flw_name',
              )?.text ??
          ''),
      _clean(container?.attributes['title'] ?? ''),
    ];
    if (container != null) {
      for (final a in container.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        if (_isProfileHref(href)) values.add(_clean(a.text));
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
      final raw = (image.attributes['data-src'] ??
              image.attributes['data-original'] ??
              image.attributes['src'] ??
              '')
          .trim();
      if (_validImageSource(raw)) return _absolute(raw);
    }
    return '';
  }

  String _extractSubtitle(Element? container, String name, int uid) {
    if (container == null) return 'UID $uid';
    var text = _clean(container.text);
    if (name.isNotEmpty) text = text.replaceFirst(name, '').trim();
    if (text.isEmpty || text.length > 120 || _isNavigation(text)) {
      return 'UID $uid';
    }
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

  static int _uidFrom(String href) {
    final uri = Uri.tryParse(href);
    for (final key in const ['uid', 'fuid', 'followuid']) {
      final value = uri?.queryParameters[key];
      final uid = int.tryParse(value ?? '');
      if (uid != null && uid > 0) return uid;
    }
    final match = RegExp(
      r'(?:space-uid-|uid=|fuid=|followuid=)(\d+)',
      caseSensitive: false,
    ).firstMatch(href);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static bool _isProfileHref(String href) {
    final lower = href.toLowerCase();
    if (lower.contains('space-uid-')) return true;
    if (!lower.contains('uid=') || !lower.contains('mod=space')) return false;
    if (lower.contains('mod=spacecp')) return false;
    return !lower.contains('do=') || lower.contains('do=profile');
  }

  String _absolute(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return value.startsWith('/') ? '$_base${value.substring(1)}' : '$_base$value';
  }

  static bool _validImageSource(String value) {
    if (value.isEmpty || value == '×' || value.toLowerCase() == 'x') return false;
    if (value.contains('�') || value.contains('\uFFFD')) return false;
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('//') ||
        value.startsWith('/');
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

  static String _clean(String value) => value
      .replaceAll('\uFFFD', '�')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isNavigation(String value) => const {
    '首页','下一页','上一页','更多','关注','粉丝','好友','删除','取消关注'
  }.contains(value);

  Future<String?> toggleFollow({required int uid, required bool follow}) async {
    if (uid <= 0 || uid == _currentUid) return '用户无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;

      // 优先使用缓存的 formhash —— 用户能看到列表说明缓存一定有效。
      // 如果缓存为空(极端情况:用户没进过列表就点了关注), 就去拉一次关注列表页。
      var token = _cachedFormhash;
      if (token.isEmpty) {
        final listPath = 'home.php?mod=follow&do=following&uid=$_currentUid&mobile=2';
        final listHtml = await _get(listPath);
        token = _cachedFormhash;
        if (token.isEmpty) token = _hiddenValue(listHtml, 'formhash');
      }
      if (token.isEmpty) return '未取得操作令牌,请刷新登录状态后重试';

      // Discuz follow 接口: fuid 是目标用户 UID, hash 查询参数必须带上。
      // 用 GET 即可触发操作, 比 POST 更简单可靠, Comiis 模板不会拦截。
      final op = follow ? 'add' : 'del';
      final actionUrl = '$_base'
          'home.php?mod=spacecp&ac=follow&op=$op&fuid=$uid&hash=$token&mobile=2';
      final refererUrl = '$_base'
          'home.php?mod=space&uid=$uid&mobile=2';

      final response = await NetClient.retry(() => client.get(
            Uri.parse(actionUrl),
            headers: {
              'User-Agent': NetClient.ua,
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Referer': refererUrl,
              'Cookie': cookie,
            },
          ).timeout(const Duration(seconds: 20)));
      final body = NetClient.decode(response.bodyBytes);

      // 刷新缓存, 关注操作后服务器可能更换 formhash
      _tryCacheFormhash(body);

      if (RegExp(r'(succeed|成功|已关注|关注成功|取消关注成功|follow\w*ok)', caseSensitive: false)
          .hasMatch(body)) {
        return null;
      }
      if (body.contains('登录') && body.contains('失效')) {
        return '登录态已失效,请重新登录论坛';
      }
      if (_tokenFailed(body)) return '操作令牌已失效,请刷新后重试';
      return follow ? '关注失败,请稍后重试' : '取消关注失败,请稍后重试';
    } catch (_) {
      return '操作失败,请检查网络后重试';
    }
  }

  static String _hiddenValue(String html, String name) {
    final doc = parser.parse(html);
    final input = doc.querySelector('input[name="$name"]');
    final value = (input?.attributes['value'] ?? '').trim();
    if (value.isNotEmpty) return value;
    final escaped = RegExp.escape(name);
    final patterns = <RegExp>[
      RegExp('name\\s*=\\s*["\\\']$escaped["\\\'][^>]*value\\s*=\\s*["\\\']([^"\\\']+)["\\\']', caseSensitive: false),
      RegExp('value\\s*=\\s*["\\\']([^"\\\']+)["\\\'][^>]*name\\s*=\\s*["\\\']$escaped["\\\']', caseSensitive: false),
      // Comiis 模板: formhash=ca6c6844 形式出现在链接/JS 字符串中。
      RegExp('(?:^|[?&,;\\s\'"])' + escaped + '\\s*=\\s*["\']?([a-zA-Z0-9]{4,})["\']?', caseSensitive: false),
      RegExp(r"formhash=([a-zA-Z0-9]{4,})", caseSensitive: false),
      RegExp(r"hash=([a-zA-Z0-9]{4,})", caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return match.group(1)?.trim() ?? '';
    }
    return '';
  }

  static bool _tokenFailed(String body) {
    final lower = body.toLowerCase();
    return lower.contains('formhash') &&
        (lower.contains('错误') || lower.contains('invalid') || lower.contains('token'));
  }

  static bool _looksLikeLogin(String html) {
    final lower = html.toLowerCase();
    return lower.contains('name="loginfield"') ||
        lower.contains('id="ls_username"') ||
        (lower.contains('登录') && lower.contains('password'));
  }
}
