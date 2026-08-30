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
    final uri = parsed.replace(queryParameters: {...parsed.queryParameters, '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString()});
    final cookie = AuthService.instance.authCookie;
    final r = await NetClient.retry(() => client.get(uri, headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(const Duration(seconds: 20)));
    if (r.statusCode != 200) throw Exception('请求失败 HTTP ${r.statusCode}');
    return NetClient.decode(r.bodyBytes);
  }

  Future<ProfileData> fetchProfile(int uid) async {
    final html = await _get('home.php?mod=space&do=profile&uid=$uid&mobile=2');
    final doc = parser.parse(html);
    for (final n in doc.querySelectorAll('script,style,noscript,template')) { n.remove(); }
    final text = _clean(doc.body?.text ?? '');

    // “头像旁边”显示昵称：优先取资料页明确标注的昵称，而不是用户名链接。
    final nickname = _labelValue(doc, ['昵称', '昵称：', '显示名称']);
    final username = _labelValue(doc, ['用户名', '用户名：']) ?? _visibleName(doc);
    final name = _validName(nickname) ? nickname! : (_validName(username) ? username! : '用户');
    final avatar = _abs(doc.querySelector('.avatar img, .avtm img, img[src*="avatar"], .comiis_space_avatar img')?.attributes['src'] ?? '');
    final group = _clean(doc.querySelector('.comiis_space_level, .gm, .xg1')?.text ?? '');
    final signature = _clean(doc.querySelector('.comiis_space_signature, .personal_signature, .spv')?.text ?? '');

    final following = _numberFor(doc, text, ['关注'], uid: uid);
    final followers = _numberFor(doc, text, ['粉丝'], uid: uid);
    final threads = _numberFor(doc, text, ['主题数', '主题'], uid: uid);
    final replies = _numberFor(doc, text, ['回帖数', '回帖'], uid: uid);
    final credits = await _fetchCreditBalance(doc, text, uid);
    final points = _numberFor(doc, text, ['积分'], uid: uid, rejectUid: true);
    final me = AuthService.instance.uid ?? 0;
    final followedByMe = me > 0 && RegExp(r'(?:取消关注|已关注)').hasMatch(text);

    return ProfileData(uid: uid, username: name, avatar: avatar, group: group, signature: signature, threads: threads, replies: replies, following: following, followers: followers, credits: credits, points: points, followingMe: false, followedByMe: followedByMe);
  }

  Future<int> _fetchCreditBalance(dynamic profileDoc, String text, int uid) async {
    // 个人资料页有时只显示积分而不输出可提现星币。优先从专门的 credit 页面读取，避免 UID 被当余额。
    final direct = _numberFor(profileDoc, text, ['星币', '源币'], uid: uid, rejectUid: true);
    if (direct > 0) return direct;
    try {
      final html = await _get('home.php?mod=spacecp&ac=credit&mobile=2');
      final doc = parser.parse(html);
      for (final node in doc.querySelectorAll('li,dt,dd,tr,td,th,div,span,p,strong,em')) {
        final value = _clean(node.text ?? '');
        if (value.isEmpty || value.length > 120 || !RegExp(r'(星币|源币)').hasMatch(value)) continue;
        final m = RegExp(r'(?:星币|源币)\s*[:：]?\s*([0-9]{1,12})').firstMatch(value);
        if (m != null) {
          final n = int.tryParse(m.group(1)!);
          if (n != null && n != uid) return n;
        }
        final n = RegExp(r'([0-9]{1,12})\s*(?:星币|源币)').firstMatch(value);
        if (n != null) {
          final v = int.tryParse(n.group(1)!);
          if (v != null && v != uid) return v;
        }
      }
    } catch (_) {}
    return 0;
  }

  static int _numberFor(dynamic doc, String text, List<String> labels, {required int uid, bool rejectUid = false}) {
    for (final element in doc.querySelectorAll('li,dt,dd,div,span,p,a,em,strong')) {
      final value = _clean(element.text ?? '');
      if (value.isEmpty || value.length > 80 || !labels.any(value.contains)) continue;
      if (RegExp(r'UID\s*[:：]?', caseSensitive: false).hasMatch(value)) continue;
      final m = RegExp(r'(?:${labels.map(RegExp.escape).join('|')})\s*[:：]?\s*([0-9]{1,12})').firstMatch(value);
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && (!rejectUid || n != uid)) return n;
      }
      final tail = RegExp(r'(?:^|[^0-9])([0-9]{1,12})(?:\s*(?:个|枚|点)?\s*)$').firstMatch(value);
      if (tail != null) {
        final n = int.tryParse(tail.group(1)!);
        if (n != null && (!rejectUid || n != uid)) return n;
      }
    }
    for (final label in labels) {
      for (final m in RegExp('${RegExp.escape(label)}\\s*[:：]?\\s*([0-9]{1,12})').allMatches(text)) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && (!rejectUid || n != uid)) return n;
      }
    }
    return 0;
  }

  static String? _labelValue(dynamic doc, List<String> labels) {
    for (final node in doc.querySelectorAll('li,dt,dd,th,td,p,div,span')) {
      final text = _clean(node.text ?? '');
      for (final label in labels) {
        if (!text.contains(label)) continue;
        final value = _clean(text.replaceFirst(label, '').replaceFirst(':', '').replaceFirst('：', ''));
        if (_validName(value)) return value;
      }
    }
    return null;
  }

  static String? _visibleName(dynamic doc) {
    for (final selector in ['.vwmy a', '.vwmy', '.pf_username', '.userinfo a', '.user-info a', '.member-name', '.username', '.nickname', '[class*="username"]', '[class*="nickname"]']) {
      final value = _clean(doc.querySelector(selector)?.text ?? '');
      if (_validName(value)) return value;
    }
    return null;
  }

  static bool _validName(String? value) {
    if (value == null) return false;
    final v = _clean(value);
    return v.isNotEmpty && v.length <= 32 && !RegExp(r'^(UID|用户名|昵称|登录|注册|退出|主题|回帖)\s*[:：]?$', caseSensitive: false).hasMatch(v);
  }

  Future<List<ThreadItem>> fetchThreads(int uid, {bool replies = false}) {
    final path = replies ? 'home.php?mod=space&do=thread&view=me&type=reply&uid=$uid&mobile=2' : 'home.php?mod=space&do=thread&view=me&uid=$uid&mobile=2';
    return MemberServiceV2.instance.fetchThreads(path);
  }

  Future<String?> setFollow(int uid, bool follow) async {
    final cookie = AuthService.instance.authCookie;
    if ((cookie ?? '').isEmpty) return '请先登录论坛';
    final client = await NetClient.instance.client;
    try {
      final page = await _get('home.php?mod=space&do=profile&uid=$uid&mobile=2');
      final formhash = _hidden(page, 'formhash');
      if (formhash == null || formhash.isEmpty) return '未取得操作令牌，请刷新后重试';
      final r = await client.post(Uri.parse('$_base' 'home.php?mod=spacecp&ac=friend&op=${follow ? 'add' : 'ignore'}&uid=$uid&inajax=1'), headers: {'User-Agent': NetClient.ua, 'Accept': '*/*', 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Referer': '$_base' 'home.php?mod=space&do=profile&uid=$uid&mobile=2', 'X-Requested-With': 'XMLHttpRequest', 'Cookie': cookie ?? ''}, body: {'formhash': formhash, 'uid': '$uid', 'handlekey': 'follow_$uid'}).timeout(const Duration(seconds: 20));
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
  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  static String _abs(String u) { if (u.isEmpty) return ''; if (u.startsWith('http')) return u; if (u.startsWith('//')) return 'https:$u'; if (u.startsWith('/')) return _base + u.substring(1); return _base + u; }
}
