import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import 'site_config.dart';
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
  static String get _base => SiteConfig.base;
  final Map<int, ProfileData> _cache = <int, ProfileData>{};

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

  Future<ProfileData> fetchProfile(int uid, {String? fallbackUsername, bool forceRefresh = false}) async {
    if (uid <= 0) throw Exception('无效的用户ID');
    if (!forceRefresh) {
      final cached = _cache[uid];
      if (cached != null) return cached;
    }
    final html = await _get('home.php?mod=space&uid=$uid&do=profile&mobile=2');
    final doc = parser.parse(html);
    for (final n in doc.querySelectorAll('script,style,noscript,template')) { n.remove(); }
    final text = _clean(doc.body?.text ?? '');
    final username = _profileUsername(doc, uid) ?? _labelValue(doc, ['昵称', '显示名称', '用户名']) ?? (fallbackUsername?.trim().isNotEmpty == true && _validName(fallbackUsername) ? fallbackUsername!.trim() : '用户');
    final avatar = _avatar(doc, uid);
    final group = _clean(doc.querySelector('.comiis_space_level, .gm, .xg1, a[href*="gid="]')?.text ?? '');
    final signature = _clean(doc.querySelector('.comiis_space_signature, .personal_signature, .spv, .sign, [class*="signature"]')?.text ?? '');
    final threads = _numberFromHref(doc, (href) => href.contains('do=thread') && href.contains('type=thread')) ?? _numberNearLabel(doc, ['主题', '主题数']);
    final replies = _numberFromHref(doc, (href) => href.contains('do=thread') && href.contains('type=reply')) ?? _numberNearLabel(doc, ['回帖', '回帖数', '帖子']);
    final followers = _numberFromHref(doc, (href) => href.contains('mod=follow') && href.contains('do=follower')) ?? _numberNearLabel(doc, ['粉丝']);
    final following = _numberFromHref(doc, (href) => (href.contains('mod=follow') && (href.contains('do=following') || href.contains('do=friend'))) || href.contains('do=friend')) ?? _numberNearLabel(doc, ['关注', '好友']);
    final credits = _numberNearLabel(doc, ['星币', '源币', '金币', '余额']);
    final points = _numberNearLabel(doc, ['积分', '贡献']);
    final followedByMe = AuthService.instance.uid != null && RegExp(r'(?:取消关注|已关注)').hasMatch(text);
    final result = ProfileData(uid: uid, username: _validName(username) ? username : (fallbackUsername?.trim().isNotEmpty == true && _validName(fallbackUsername) ? fallbackUsername!.trim() : '用户'), avatar: avatar, group: group, signature: signature, threads: threads, replies: replies, following: following, followers: followers, credits: credits, points: points, followingMe: false, followedByMe: followedByMe);
    _cache[uid] = result;
    return result;
  }

  static String? _profileUsername(dom.Document doc, int uid) {
    final uidText = uid.toString();
    const selectors = ['.comiis_space_info h2', '#uhd .vwmy a', '#uhd .vwmy', '.vwmy a', '.vwmy'];
    for (final selector in selectors) {
      final value = _clean(doc.querySelector(selector)?.text ?? '');
      if (_validName(value) && !_uiLabel(value)) return value;
    }
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final lower = href.toLowerCase();
      final hasUid = lower.contains('uid=$uidText') || lower.contains('uid%3d$uidText') || lower.contains('uid%253d$uidText');
      if (!hasUid || !lower.contains('mod=space') || !lower.contains('do=profile')) continue;
      final value = _clean(a.text);
      if (_validName(value) && !_uiLabel(value)) return value;
      final parentValue = _clean(a.parent?.text ?? '');
      if (_validName(parentValue) && !_uiLabel(parentValue)) return parentValue;
    }
    final candidates = [doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '', doc.querySelector('title')?.text ?? ''];
    for (var value in candidates) {
      value = _clean(value).replaceFirst(RegExp(r'\s*[-|｜]\s*源论坛\s*$', caseSensitive: false), '').replaceFirst(RegExp(r'\s*的个人资料\s*$', caseSensitive: false), '').replaceFirst(RegExp(r'^个人资料\s*[-|｜:]\s*', caseSensitive: false), '').trim();
      if (_validName(value) && !_uiLabel(value)) return value;
    }
    return null;
  }

  static String _avatar(dom.Document doc, int uid) {
    final uidText = uid.toString();
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').toLowerCase();
      if (!href.contains('uid=$uidText') || !href.contains('do=profile')) continue;
      final img = a.querySelector('img[src], img[data-src]');
      final value = _abs(img?.attributes['src'] ?? img?.attributes['data-src'] ?? '');
      if (_isRealAvatar(value, uid)) return value;
    }
    for (final selector in ['.comiis_space_avatar img', '.comiis_space_user img.avatar', '.comiis_space_user img.user_avatar', '.comiis_space_box img[src*="avatar"]', '.space_avatar img']) {
      final node = doc.querySelector(selector);
      if (node == null) continue;
      final value = _abs(node.attributes['src'] ?? node.attributes['data-src'] ?? '');
      if (_isRealAvatar(value, uid)) return value;
    }
    final s = uid.toString().padLeft(8, '0');
    return '${_base}data/avatar/${s.substring(0, 3)}/${s.substring(3, 5)}/${s.substring(5, 7)}/${s.substring(7)}_avatar_middle.jpg';
  }

  static bool _isRealAvatar(String value, int uid) {
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    if (lower.contains('noavatar')) return false;
    return lower.contains('avatar');
  }

  static bool _uiLabel(String value) => RegExp(r'^(?:关注|已关注|聊天|私信|回复|主题|回帖|帖子|帖子数|粉丝|积分|星币|登录|注册|退出|刷新|用户|用户名|昵称|资料|个人资料|用户资料|个人中心|Ta的空间|空间|我的|提示信息|系统提示|温馨提示|提示|抱歉|无权|没有权限|不存在|该用户)$').hasMatch(_clean(value));

  static int? _numberFromHref(dom.Document doc, bool Function(String href) matches) {
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (!matches(href)) continue;
      final match = RegExp(r'(?<!\d)(\d{1,12})(?!\d)').firstMatch(_clean(a.text));
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
          final match = RegExp('([0-9]{1,12})[^0-9]{0,12}${RegExp.escape(label)}').firstMatch(text) ?? RegExp('${RegExp.escape(label)}[^0-9]{0,12}([0-9]{1,12})').firstMatch(text);
          if (match != null) return int.tryParse(match.group(1)!) ?? 0;
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
        if (_validName(value) && !_uiLabel(value)) return value;
      }
    }
    return null;
  }

  static bool _validName(String? value) {
    if (value == null) return false;
    final v = _clean(value);
    if (v.isEmpty || v.length > 32 || v.contains('\uFFFD') || v.contains('�')) return false;
    if (RegExp(r'[\x00-\x1F]').hasMatch(v)) return false;
    if (RegExp(r'^(?:资料|个人资料|用户资料|用户|用户名|昵称|登录|注册|退出|主题|回帖|帖子|帖子数|关注|已关注|聊天|私信|刷新|个人中心|Ta的空间|空间|我的|提示信息|系统提示|温馨提示|提示|抱歉|无权|没有权限|不存在|该用户)$', caseSensitive: false).hasMatch(v)) return false;
    return !RegExp(r'^(UID|用户|用户名|昵称|登录|注册|退出|主题|回帖|帖子|帖子数|个人中心|空间|我的|提示信息)\s*[:：]?$', caseSensitive: false).hasMatch(v);
  }

  Future<List<ThreadItem>> fetchThreads(int uid, {bool replies = false}) {
    final type = replies ? 'reply' : 'thread';
    return MemberServiceV2.instance.fetchThreads('home.php?mod=space&uid=$uid&do=thread&type=$type&view=me&from=space&mobile=2');
  }

  Future<String?> setFollow(int uid, bool follow) async {
    if (uid <= 0 || uid == (AuthService.instance.uid ?? 0)) return '用户无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      // 关注操作必须先访问 spacecp/ac=follow 页面取得当前会话对应的 formhash。
      // 直接从个人资料页取 token 在部分 Comiis/Discuz 模板下会拿不到，导致
      // “未取得操作令牌”。这里与关系页使用同一套官方操作入口。
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
        'X-Requested-With': 'XMLHttpRequest',
        'Cookie': cookie,
      }, body: {
        'formhash': formhash,
        'uid': '$uid',
        'op': follow ? 'add' : 'del',
        'inajax': '1',
      }).timeout(const Duration(seconds: 20)));

      final body = NetClient.decode(response.bodyBytes);
      if (RegExp(r'(succeed|成功|已关注|关注成功|取消关注成功)', caseSensitive: false).hasMatch(body)) return null;
      if (body.contains('登录') && (body.contains('失效') || body.contains('请登录'))) return '登录态已失效，请重新登录论坛';
      if (_tokenFailed(body)) return '操作令牌已失效，请刷新后重试';
      return _message(body) ?? (follow ? '关注失败，请稍后重试' : '取消关注失败，请稍后重试');
    } catch (_) {
      return '操作失败，请检查网络后重试';
    }
  }

  static String? _message(String html) => RegExp(r'''(?:showError|showDialog)\(\s*['"]([^'"]+)''').firstMatch(html)?.group(1);

  static String _hiddenValue(String html, String name) {
    final doc = parser.parse(html);
    final exact = doc.querySelector('input[name="$name"]');
    final value = (exact?.attributes['value'] ?? '').trim();
    if (value.isNotEmpty) return value;
    final escaped = RegExp.escape(name);
    final inputRe = RegExp(r'<input\b[^>]*>', caseSensitive: false);
    for (final match in inputRe.allMatches(html)) {
      final tag = match.group(0)!;
      final a = RegExp('name\\s*=\\s*["\\\']$escaped["\\\'][^>]*value\\s*=\\s*["\\\']([^"\\\']+)["\\\']', caseSensitive: false).firstMatch(tag)?.group(1);
      if (a != null && a.trim().isNotEmpty) return a.trim();
      final b = RegExp('value\\s*=\\s*["\\\']([^"\\\']+)["\\\'][^>]*name\\s*=\\s*["\\\']$escaped["\\\']', caseSensitive: false).firstMatch(tag)?.group(1);
      if (b != null && b.trim().isNotEmpty) return b.trim();
    }
    return '';
  }

  static bool _tokenFailed(String body) {
    final lower = body.toLowerCase();
    return lower.contains('formhash') && (lower.contains('错误') || lower.contains('invalid') || lower.contains('token'));
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  static String _abs(String u) { if (u.isEmpty) return ''; if (u.startsWith('http')) return u; if (u.startsWith('//')) return 'https:$u'; if (u.startsWith('/')) return _base + u.substring(1); return _base + u.replaceFirst(RegExp(r'^\./'), ''); }
}
