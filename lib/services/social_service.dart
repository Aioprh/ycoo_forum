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
            'Pragma': 'no-cache',
            if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
          },
        ).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) {
      throw Exception('请求失败 HTTP ${response.statusCode}');
    }
    final html = NetClient.decode(response.bodyBytes);
    if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
    return html;
  }

  int get _currentUid => AuthService.instance.uid ?? 0;

  // Discuz X3 的关注页实际入口是 mod=follow&do=following，
  // 不是 mod=space&do=follow&view=following。
  Future<List<SocialUser>> fetchFollowing() => _fetch(
        'home.php?mod=follow&do=following&uid=$_currentUid&mobile=2',
        followed: true,
      );

  // Discuz X3 的粉丝页实际入口是 mod=follow&do=follower。
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

    // 关系页本身已经限定了数据范围，因此不要再用整页所有 uid 做
    // “候选用户”。只接受真正的个人空间链接，避免页头“我的资料”
    // 和操作按钮被识别成自己。
    final anchors = doc.querySelectorAll(
      'a[href*="mod=space"][href*="uid="],'
      'a[href*="space-uid-"],'
      'a[href*="mod=space&uid="]',
    );

    for (final anchor in anchors) {
      final href = anchor.attributes['href'] ?? '';
      final uid = _uidFrom(href);
      if (uid <= 0 || uid == currentUid || seen.contains(uid)) continue;
      if (!_isProfileHref(href)) continue;

      final container = _userContainer(anchor);
      var name = _extractName(anchor, container);
      var avatar = _extractAvatar(anchor, container);
      var subtitle = _extractSubtitle(container, name, uid);

      // 页面可能只有 UID 没有用户名/头像；此时只根据已经确认的 UID
      // 请求资料，绝不回退到当前用户。
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

  Element? _userContainer(Element anchor) {
    Element? node = anchor.parent;
    for (var i = 0; i < 6 && node != null; i++) {
      final text = _clean(node.text);
      final hasProfile = node.querySelector(
            'a[href*="mod=space"][href*="uid="],a[href*="space-uid-"]',
          ) !=
          null;
      final hasImage = node.querySelector('img') != null;
      if (hasProfile && hasImage && text.length <= 300) return node;
      if (hasProfile && text.length <= 180) return node;
      node = node.parent;
    }
    return anchor.parent;
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
    ];
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

  Future<String?> toggleFollow({required int uid, required bool follow}) async {
    if (uid <= 0 || uid == _currentUid) return '用户无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final pagePath = 'home.php?mod=spacecp&ac=follow&uid=$uid&mobile=2';
      final page = await _get(pagePath);
      final formhash = _hiddenValue(page, 'formhash');
      if (formhash.isEmpty) return '未取得操作令牌，请刷新登录状态后重试';

      // Discuz 关注关系的目标参数使用 uid；关注列表中的删除链接则
      // 使用 fuid。这里保持 spacecp 操作接口的 uid 写法。
      final path =
          'home.php?mod=spacecp&ac=follow&op=${follow ? 'add' : 'del'}&uid=$uid&mobile=2';
      final response = await NetClient.retry(() => client.post(
            Uri.parse('$_base$path'),
            headers: {
              'User-Agent': NetClient.ua,
              'Accept': 'application/json,text/html,*/*',
              'Referer': '$_base$pagePath',
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
            body: {
              'formhash': formhash,
              'uid': '$uid',
              'op': follow ? 'add' : 'del',
              'inajax': '1',
            },
          ).timeout(const Duration(seconds: 20)));
      final body = NetClient.decode(response.bodyBytes);
      if (RegExp(
        r'(succeed|成功|已关注|关注成功|取消关注成功)',
        caseSensitive: false,
      ).hasMatch(body)) return null;
      if (body.contains('登录') && body.contains('失效')) {
        return '登录态已失效，请重新登录论坛';
      }
      if (_tokenFailed(body)) return '操作令牌已失效，请刷新后重试';
      return follow ? '关注失败，请稍后重试' : '取消关注失败，请稍后重试';
    } catch (_) {
      return '操作失败，请检查网络后重试';
    }
  }

  static String _hiddenValue(String html, String name) {
    final doc = parser.parse(html);
    final input = doc.querySelector('input[name="$name"]');
    final value = (input?.attributes['value'] ?? '').trim();
    if (value.isNotEmpty) return value;
    return '';
  }

  static bool _tokenFailed(String body) =>
      body.contains('formhash') &&
      (body.contains('错误') ||
          body.contains('失效') ||
          body.contains('非法') ||
          body.contains('验证失败'));

  static bool _validImageSource(String value) {
    if (value.isEmpty || value == '×' || value.toLowerCase() == 'x') return false;
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('//') ||
        value.startsWith('/');
  }

  static String _absolute(String value) {
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('/')) return '$_base${value.substring(1)}';
    return '$_base$value';
  }

  static bool _validProfileName(String value) =>
      !_badName(value) &&
      !RegExp(r'^(?:用户|资料|个人资料|用户名|昵称)$').hasMatch(value.trim());

  static bool _badName(String value) {
    final v = _clean(value);
    if (v.isEmpty || v.length > 40) return true;
    if (const {
      '首页',
      '下一页',
      '上一页',
      '更多',
      '关注',
      '粉丝',
      '好友',
      '删除',
      '取消关注',
      '帖子',
      '主题',
      '回帖',
      '资料',
      '个人资料',
      '昵称',
      '用户名',
      '设置',
      '个人中心',
      'Ta的空间',
      '空间',
      '我的',
      '提示信息',
      '系统提示',
      '温馨提示',
      '提示',
      '抱歉',
      '无权',
      '没有权限',
      '不存在',
      '该用户',
      '×',
      'x',
      'X',
    }.contains(v)) return true;
    return !RegExp(r'[\u4e00-\u9fffA-Za-z0-9]').hasMatch(v);
  }

  static String _clean(String value) =>
      value.replaceAll('\uFFFD', '�').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isNavigation(String value) => const {
        '首页',
        '下一页',
        '上一页',
        '更多',
        '关注',
        '粉丝',
        '好友',
        '删除',
        '取消关注',
      }.contains(value);

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) {
      node.remove();
    }
    final text = _clean(doc.body?.text ?? '');
    return text.isNotEmpty &&
        RegExp(r'(用户名|登录密码)').hasMatch(text) &&
        text.contains('登录') &&
        !html.contains('action=logout');
  }
}
