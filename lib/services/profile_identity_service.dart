import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';

class ProfileIdentity {
  final String? username;
  final int? uid;
  final String? avatar;
  final String? nickname;
  final String? level;
  final String? rank;
  final int? points;
  final int? coins;

  const ProfileIdentity({
    this.username,
    this.uid,
    this.avatar,
    this.nickname,
    this.level,
    this.rank,
    this.points,
    this.coins,
  });
}

class ProfileIdentityService {
  ProfileIdentityService._();
  static final instance = ProfileIdentityService._();
  static const _base = 'https://www.ycoo.net/';

  Future<ProfileIdentity?> fetch() async {
    final uid = AuthService.instance.uid;
    if (uid == null || uid <= 0) return null;
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final headers = {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };

    String? nickname;
    String? username;
    String? avatar;
    String? level;
    String? rank;
    int? points;
    int? coins;

    final urls = <String>[
      '${_base}home.php?mod=space&uid=$uid&do=profile&mobile=2',
      '${_base}home.php?mod=space&uid=$uid&mobile=2',
      '${_base}home.php?mod=space&uid=$uid',
    ];

    for (final url in urls) {
      try {
        final response = await client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) continue;
        final doc = parser.parse(NetClient.decode(response.bodyBytes));
        for (final n in doc.querySelectorAll('script,style,noscript,template')) n.remove();

        nickname ??= _firstValid([
          _findLabelValue(doc, '昵称'),
          _findLabelValue(doc, '昵称：'),
          _findNicknameNode(doc),
        ]);
        username ??= _firstValid([
          _findLabelValue(doc, '用户名'),
          _findLabelValue(doc, '用户名：'),
          _findProfileLinkName(doc, uid),
          _titleName(doc),
          _findVisibleName(doc),
        ]);
        avatar ??= _firstAvatar(doc) ?? '${_base}uc_server/avatar.php?uid=$uid&size=middle';
        level ??= _findLevel(doc);
        rank ??= _findRank(doc);
        points ??= _findNumberByLabels(doc, ['积分', '总积分']);
        coins ??= _findNumberByLabels(doc, ['星币', '源币']);

        if (username != null && level != null && rank != null && (points != null || coins != null)) break;
      } catch (_) {}
    }

    try {
      final response = await client.get(
        Uri.parse('${_base}home.php?mod=spacecp&ac=credit&showcredit=1&inajax=1&ajaxtarget=extcreditmenu_menu'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final doc = parser.parse(NetClient.decode(response.bodyBytes));
        // 不要写死 hcredit_2 —— 该论坛 hcredit_2 可能是“经验”。按名称标签匹配真正的星币/源币。
        coins ??= _findNumericByLabelsInCreditMenu(doc, ['星币', '源币']);
        points ??= _findNumberByLabels(doc, ['积分', '总积分']);
        points ??= _elementNumber(doc, 'hcredit_1');
      }
    } catch (_) {}

    if (username == null && nickname == null && avatar == null) return null;
    nickname = _stripAccountMeta(nickname, level: level, rank: rank, points: points);
    return ProfileIdentity(
      username: username,
      uid: uid,
      avatar: avatar,
      nickname: nickname,
      level: level,
      rank: rank,
      points: points,
      coins: coins,
    );
  }

  String? _stripAccountMeta(String? value, {String? level, String? rank, int? points}) {
    if (value == null) return null;
    var text = _clean(value);

    // 网页某些主题会把昵称、等级、品级、积分全部放在同一个节点：
    // “烟雨客Lv.1 童生 积分:138”。昵称只取前面的真实昵称。
    final metaStart = RegExp(r'Lv\.?\s*\d+', caseSensitive: false).firstMatch(text);
    if (metaStart != null) {
      text = text.substring(0, metaStart.start).trim();
    } else {
      // 没有 Lv 标记时，也处理“昵称 童生 积分:138”的主题结构。
      final pointsStart = RegExp(r'积分\s*[:：]?\s*\d+', caseSensitive: false).firstMatch(text);
      if (pointsStart != null) text = text.substring(0, pointsStart.start).trim();
      if (rank != null && rank.isNotEmpty) {
        final rankIndex = text.indexOf(rank);
        if (rankIndex > 0) text = text.substring(0, rankIndex).trim();
      }
    }

    if (level != null && level.isNotEmpty) {
      text = text.replaceAll(RegExp(RegExp.escape(level), caseSensitive: false), ' ');
    }
    text = text.replaceAll(RegExp(r'Lv\.?\s*\d+', caseSensitive: false), ' ');
    if (rank != null && rank.isNotEmpty) {
      text = text.replaceAll(RegExp(RegExp.escape(rank)), ' ');
    }
    text = text.replaceAll(RegExp(r'积分\s*[:：]?\s*\d+'), ' ');
    if (points != null) {
      text = text.replaceAll(RegExp(r'积分\s*[:：]?\s*' + points.toString()), ' ');
    }
    text = _clean(text);
    return text.isEmpty ? null : text;
  }

  String? _findLevel(dynamic doc) {
    for (final node in doc.querySelectorAll('.comiis_space_level, .user-level, .level, [class*="level"], [class*="group"]')) {
      final text = _clean(node.text);
      final m = RegExp(r'Lv\.?\s*([0-9]+)', caseSensitive: false).firstMatch(text);
      if (m != null) return 'Lv.${m.group(1)}';
    }
    final text = _clean(doc.body?.text ?? '');
    final m = RegExp(r'\bLv\.?\s*([0-9]+)', caseSensitive: false).firstMatch(text);
    return m == null ? null : 'Lv.${m.group(1)}';
  }

  String? _findRank(dynamic doc) {
    const selectors = [
      '.comiis_space_level', '.user-level', '.user-group', '.group-name',
      '[class*="level"]', '[class*="group"]', '[class*="rank"]',
    ];
    for (final selector in selectors) {
      for (final node in doc.querySelectorAll(selector)) {
        final text = _clean(node.text);
        if (text.isEmpty) continue;
        final value = text.replaceFirst(RegExp(r'Lv\.?\s*\d+', caseSensitive: false), '').trim();
        if (_validBadge(value)) return value;
      }
    }
    final text = _clean(doc.body?.text ?? '');
    final m = RegExp(r'Lv\.?\s*\d+\s+([^\s|｜·•]{1,12})', caseSensitive: false).firstMatch(text);
    return m == null ? null : m.group(1);
  }

  int? _findNumberByLabels(dynamic doc, List<String> labels) {
    for (final node in doc.querySelectorAll('li,dt,dd,th,td,p,div,span,a')) {
      final text = _clean(node.text);
      if (!labels.any(text.startsWith)) continue;
      final m = RegExp(r'(?:^|[:：\s])([0-9]{1,12})(?:\s|$)').firstMatch(text);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  int? _elementNumber(dynamic doc, String id) {
    final text = _clean(doc.querySelector('#$id')?.text ?? '');
    final m = RegExp(r'([0-9]{1,12})').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  // 在扩展积分菜单里按名称标签（如“星币/源币”）匹配真正的 hcredit 元素，
  // 而不是写死 hcredit_2（该论坛 hcredit_2 可能是“经验”）。
  int? _findNumericByLabelsInCreditMenu(dynamic doc, List<String> labels) {
    for (final node in doc.querySelectorAll('[id^="hcredit_"]')) {
      final text = _clean(node.text);
      if (!labels.any(text.contains)) continue;
      final m = RegExp(r'([0-9]{1,12})').lastMatch(text);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  String? _findNicknameNode(dynamic doc) {
    const selectors = [
      '.nickname', '.nick-name', '.pf_nickname', '.userinfo .name',
      '.user-info .name', '[class*="nickname"]', '[class*="nick"]',
    ];
    for (final selector in selectors) {
      for (final node in doc.querySelectorAll(selector)) {
        final text = _clean(node.text);
        if (_validName(text)) return text;
      }
    }
    return null;
  }

  String? _findProfileLinkName(dynamic doc, int uid) {
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('space') && !href.contains('member')) continue;
      if (!RegExp(r'(?:uid=|uid%3D|uid/|uid-)' + uid.toString(), caseSensitive: false).hasMatch(href)) continue;
      final text = _clean(a.text);
      if (_validName(text)) return text;
    }
    return null;
  }

  String? _titleName(dynamic doc) {
    final title = _clean(doc.querySelector('title')?.text ?? '');
    for (final p in [
      RegExp(r'^(.+?)的(?:个人主页|个人资料|空间)'),
      RegExp(r'^(.+?)\s*[-|｜]\s*源论坛$'),
      RegExp(r'^(.+?)\s*的空间$'),
    ]) {
      final m = p.firstMatch(title);
      if (m != null && _validName(m.group(1))) return m.group(1)!.trim();
    }
    return null;
  }

  String? _findLabelValue(dynamic doc, String label) {
    for (final node in doc.querySelectorAll('li,dt,dd,th,td,p,div,span')) {
      final text = _clean(node.text);
      if (!text.contains(label)) continue;
      final value = _clean(text.replaceFirst(label, '').replaceFirst(':', '').replaceFirst('：', ''));
      if (_validName(value)) return value;
    }
    return null;
  }

  String? _findVisibleName(dynamic doc) {
    const selectors = ['.vwmy', '.pf_username', '.userinfo a', '.user-info a', '.member-name', '.username', '[class*="username"]'];
    for (final selector in selectors) {
      for (final node in doc.querySelectorAll(selector)) {
        final text = _clean(node.text);
        if (_validName(text)) return text;
      }
    }
    return null;
  }

  String? _firstAvatar(dynamic doc) {
    for (final img in doc.querySelectorAll('img[src],img[data-src]')) {
      final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
      if (src.isEmpty || !src.toLowerCase().contains('avatar')) continue;
      if (src.startsWith('http')) return src;
      if (src.startsWith('//')) return 'https:$src';
      if (src.startsWith('/')) return '$_base${src.substring(1)}';
    }
    return null;
  }

  String? _firstValid(List<String?> values) {
    for (final v in values) if (_validName(v)) return v!.trim();
    return null;
  }

  String _clean(String s) => s.replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _validName(String? s) {
    if (s == null) return false;
    final v = _clean(s);
    if (v.isEmpty || v.length > 32) return false;
    if (const {'X', 'x', '×', '登录', '注册', '退出', '退出登录', '个人主页', '资料', '主题', '回帖', '用户名', '昵称', '首页', '搜索', '设置'}.contains(v)) return false;
    return !v.contains('�') && !v.contains('Ã') && !v.contains('Â') && !v.contains('â');
  }

  bool _validBadge(String value) {
    final v = _clean(value);
    if (v.isEmpty || v.length > 16) return false;
    if (RegExp(r'^\d+$').hasMatch(v)) return false;
    return !{'用户', '会员', '等级', '用户组', '用户组别'}.contains(v);
  }
}
