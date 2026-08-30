import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import 'auth_service.dart';
import 'member_service_v2.dart';
import 'net_client.dart';

class ProfileData {
  final int uid;
  final String username;
  final String avatar;
  final String group;
  final String signature;
  final int threads;
  final int replies;
  final int following;
  final int followers;
  final int credits;
  final int points;
  final bool followingMe;
  final bool followedByMe;

  const ProfileData({required this.uid, required this.username, required this.avatar, required this.group, required this.signature, required this.threads, required this.replies, required this.following, required this.followers, required this.credits, required this.points, required this.followingMe, required this.followedByMe});

  ProfileData copyWith({int? following, int? followers, bool? followingMe, bool? followedByMe}) => ProfileData(
    uid: uid, username: username, avatar: avatar, group: group, signature: signature,
    threads: threads, replies: replies, following: following ?? this.following,
    followers: followers ?? this.followers, credits: credits, points: points,
    followingMe: followingMe ?? this.followingMe, followedByMe: followedByMe ?? this.followedByMe,
  );
}

class ProfileService {
  ProfileService._();
  static final instance = ProfileService._();
  static const _base = 'https://www.ycoo.net/';

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final parsed = Uri.parse('$_base$path');
    final uri = parsed.replace(queryParameters: {
      ...parsed.queryParameters,
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final cookie = AuthService.instance.authCookie;
    final r = await NetClient.retry(() => client.get(uri, headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(const Duration(seconds: 20)));
    if (r.statusCode != 200) throw Exception('请求失败 HTTP ${r.statusCode}');
    return NetClient.decode(r.bodyBytes);
  }

  Future<ProfileData> fetchProfile(int uid, {String? fallbackUsername}) async {
    final html = await _get('home.php?mod=space&uid=$uid&do=profile&mobile=2');
    final doc = parser.parse(html);
    for (final n in doc.querySelectorAll('script,style,noscript,template')) { n.remove(); }
    final text = _clean(doc.body?.text ?? '');

    final username = _profileUsername(doc, uid) ??
        _labelValue(doc, ['昵称', '显示名称', '用户名']) ??
        _visibleName(doc) ??
        (fallbackUsername?.trim().isNotEmpty == true ? fallbackUsername!.trim() : '用户');
    final avatar = _avatar(doc);
    final group = _clean(doc.querySelector('.comiis_space_level, .gm, .xg1, a[href*="gid="]')?.text ?? '');
    final signature = _clean(doc.querySelector('.comiis_space_signature, .personal_signature, .spv, .sign, [class*="signature"]')?.text ?? '');

    // Discuz exposes these values as links on profile pages. Prefer the link
    // targets over text-label scraping because custom mobile templates often
    // separate the number and label into different sibling nodes.
    final threads = _numberFromHref(doc, (href) =>
        href.contains('do=thread') && href.contains('type=thread')) ??
        _numberNearLabel(doc, ['主题', '主题数']);
    final replies = _numberFromHref(doc, (href) =>
        href.contains('do=thread') && href.contains('type=reply')) ??
        _numberNearLabel(doc, ['回帖', '回帖数', '帖子']);
    final followers = _numberFromHref(doc, (href) =>
        href.contains('mod=follow') && href.contains('do=follower')) ??
        _numberNearLabel(doc, ['粉丝']);
    final following = _numberFromHref(doc, (href) =>
        href.contains('mod=follow') && (href.contains('do=following') || href.contains('do=friend'))) ??
        _numberNearLabel(doc, ['关注', '好友']);
    final credits = _numberNearLabel(doc, ['星币', '源币', '金币', '余额']);
    final points = _numberNearLabel(doc, ['积分', '贡献']);

    final me = AuthService.instance.uid ?? 0;
    final followedByMe = me > 0 && RegExp(r'(?:取消关注|已关注)').hasMatch(text);

    return ProfileData(
      uid: uid,
      username: _validName(username) ? username : (fallbackUsername?.trim().isNotEmpty == true ? fallbackUsername!.trim() : '用户'),
      avatar: avatar,
      group: group,
      signature: signature,
      threads: threads,
      replies: replies,
      following: following,
      followers: followers,
      credits: credits,
      points: points,
      followingMe: false,
      followedByMe: followedByMe,
    );
  }

  static String? _profileUsername(dom.Document doc, int uid) {
    final uidText = uid.toString();
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('uid=$uidText') && !href.contains('uid%3D$uidText')) continue;
      final value = _clean(a.text);
      if (_validName(value)) return value;
    }
    final title = _clean(doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '');
    return _validName(title) ? title : null;
  }

  static String _avatar(dom.Document doc) {
    for (final selector in [
      '.avatar img', '.avtm img', '.user_avatar img', '.comiis_space_avatar img',
      'img[src*="avatar"]', 'img[data-src*="avatar"]',
    ]) {
      final node = doc.querySelector(selector);
      if (node == null) continue;
      final src = node.attributes['src'] ?? node.attributes['data-src'] ?? '';
      final value = _abs(src);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static int? _numberFromHref(dom.Document doc, bool Function(String href) matches) {
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (!matches(href)) continue;
      final value = _clean(a.text);
      final match = RegExp(r'(?<!\d)(\d{1,12})(?!\d)').firstMatch(value);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static int _numberNearLabel(dom.Document doc, List<String> labels) {
    final labelSet = labels.map(_clean).where((e) => e.isNotEmpty).toList();
    for (final node in doc.querySelectorAll('th,td,li,dt,dd,div,span,p,a,strong,em')) {
      final value = _clean(node.text);
      if (value.isEmpty || value.length > 100 || !labelSet.any((label) => value == label || value.contains(label))) continue;
      for (final candidate in [node, node.parent, node.parent?.parent]) {
        if (candidate == null) continue;
        final text = _clean(candidate.text);
        if (text.isEmpty || text.length > 160) continue;
        for (final label in labelSet) {
          final after = RegExp('${RegExp.escape(label)}[^0-9]{0,12}([0-9]{1,12})').firstMatch(text);
          final before = RegExp('([0-9]{1,12})[^0-9]{0,12}${RegExp.escape(label)}').firstMatch(text);
          final match = after ?? before;
          if (match == null) continue;
          final n = int.tryParse(match.group(1)!);
          if (n != null && n != 29113) return n;
        }
      }
    }
    return 0;
  }

  static String? _labelValue(dom.Document doc, List<String> labels) {
    for (final node in doc.querySelectorAll('li,dt,dd,th,td,p,div,span')) {
      final text = _clean(node.text);
      for (final label in labels) {
        if (!text.contains(label)) continue;
        final value = _clean(text.replaceFirst(label, '').replaceFirst(':', '').replaceFirst('：', ''));
        if (_validName(value)) return value;
      }
    }
    return null;
  }

  static String? _visibleName(dom.Document doc) {
    for (final selector in [
      '.vwmy a', '.vwmy', '.pf_username', '.userinfo a', '.user-info a',
      '.member-name', '.username', '.nickname', '[class*="username"]', '[class*="nickname"]',
    ]) {
      final value = _clean(doc.querySelector(selector)?.text ?? '');
      if (_validName(value)) return value;
    }
    return null;
  }

  static bool _validName(String? value) {
    if (value == null) return false;
    final v = _clean(value);
    return v.isNotEmpty && v.length <= 32 && !RegExp(r'^(UID|用户|用户名|昵称|登录|注册|退出|主题|回帖)\s*[:：]?$', caseSensitive: false).hasMatch(v);
  }

  Future<List<ThreadItem>> fetchThreads(int uid, {bool replies = false}) {
    final type = replies ? 'reply' : 'thread';
    final path = 'home.php?mod=space&uid=$uid&do=thread&type=$type&view=me&from=space&mobile=2';
    return MemberServiceV2.instance.fetchThreads(path);
  }

  Future<String?> setFollow(int uid, bool follow) async {
    final cookie = AuthService.instance.authCookie;
    if ((cookie ?? '').isEmpty) return '请先登录论坛';
    final client = await NetClient.instance.client;
    try {
      final page = await _get('home.php?mod=space&uid=$uid&do=profile&mobile=2');
      final formhash = _hidden(page, 'formhash');
      if (formhash == null || formhash.isEmpty) return '未取得操作令牌，请刷新后重试';
      final r = await client.post(Uri.parse('$_base' 'home.php?mod=spacecp&ac=friend&op=${follow ? 'add' : 'ignore'}&uid=$uid&inajax=1'), headers: {'User-Agent': NetClient.ua, 'Accept': '*/*', 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Referer': '$_base' 'home.php?mod=space&uid=$uid&do=profile&mobile=2', 'X-Requested-With': 'XMLHttpRequest', 'Cookie': cookie ?? ''}, body: {'formhash': formhash, 'uid': '$uid', 'handlekey': 'follow_$uid'}).timeout(const Duration(seconds: 20));
      final body = NetClient.decode(r.bodyBytes);
      if (body.contains('succeed') || body.contains('成功') || body.contains('已关注') || (follow && body.contains('follow'))) return null;
      if (body.contains('登录') && body.contains('用户名')) return '登录态已失效，请重新登录';
      return _message(body) ?? '操作失败，请稍后重试';
    } catch (_) { return '网络请求失败，请稍后重试'; }
  }

  static String? _message(String html) => RegExp(r'''(?:showError|showDialog)\(\s*['"]([^'"]+)''').firstMatch(html)?.group(1);
  static String? _hidden(String html, String name) {
    final e = RegExp.escape(name);
    return RegExp('name\\s*=\\s*["\\\']$e["\\\'][^>]*value\\s*=\\s*["\\\']([^"\\\']+)', caseSensitive: false).firstMatch(html)?.group(1);
  }
  static String _clean(String s) => s.replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  static String _abs(String u) { if (u.isEmpty) return ''; if (u.startsWith('http')) return u; if (u.startsWith('//')) return 'https:$u'; if (u.startsWith('/')) return _base + u.substring(1); return _base + u; }
}
