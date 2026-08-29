import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';

class ProfileIdentity {
  final String? username;
  final int? uid;
  final String? avatar;
  const ProfileIdentity({this.username, this.uid, this.avatar});
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
    final urls = <String>[
      '${_base}home.php?mod=space&uid=$uid&do=profile&mobile=2',
      '${_base}home.php?mod=space&uid=$uid&mobile=2',
      '${_base}home.php?mod=space&uid=$uid',
      '${_base}forum.php?mobile=2',
    ];
    for (final url in urls) {
      try {
        final response = await client.get(Uri.parse(url), headers: {
          'User-Agent': NetClient.ua,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        }).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) continue;

        final html = NetClient.decode(response.bodyBytes);
        final doc = parser.parse(html);
        for (final n in doc.querySelectorAll('script,style,noscript,template')) n.remove();

        String? name;
        final uidPatterns = <RegExp>[
          RegExp(r'(?:uid=|uid%3D|uid/|uid-)' + uid.toString(), caseSensitive: false),
          RegExp(r'(?:space|member).*' + uid.toString(), caseSensitive: false),
        ];
        for (final a in doc.querySelectorAll('a[href]')) {
          final href = a.attributes['href'] ?? '';
          if (!href.contains('space') && !href.contains('member')) continue;
          if (!uidPatterns.any((p) => p.hasMatch(href))) continue;
          final text = _clean(a.text);
          if (_validName(text)) {
            name = text;
            break;
          }
        }

        name ??= _firstValid([
          _titleName(doc),
          _meta(doc, 'og:title'),
          _meta(doc, 'description'),
          _meta(doc, 'keywords'),
          _findLabelValue(doc, '用户名'),
          _findLabelValue(doc, '昵称'),
          _findLabelValue(doc, '用户名：'),
          _findLabelValue(doc, '昵称：'),
          _findVisibleName(doc),
        ]);

        final avatar = _firstAvatar(doc) ?? '${_base}uc_server/avatar.php?uid=$uid&size=middle';
        if (_validName(name)) {
          return ProfileIdentity(username: name, uid: uid, avatar: avatar);
        }
      } catch (_) {}
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

  String? _meta(dynamic doc, String key) {
    final n = doc.querySelector('meta[property="$key"],meta[name="$key"]');
    final v = _clean(n?.attributes['content'] ?? '');
    return _validName(v) ? v : null;
  }

  String? _findLabelValue(dynamic doc, String label) {
    for (final node in doc.querySelectorAll('li,dt,dd,th,td,p,div,span')) {
      final text = _clean(node.text);
      if (!text.contains(label)) continue;
      final value = _clean(text
          .replaceFirst(label, '')
          .replaceFirst(':', '')
          .replaceFirst('：', ''));
      if (_validName(value)) return value;
    }
    return null;
  }

  String? _findVisibleName(dynamic doc) {
    const selectors = [
      '.vwmy',
      '.pf_username',
      '.userinfo a',
      '.user-info a',
      '.member-name',
      '.username',
      '.nickname',
      '[class*="username"]',
      '[class*="nickname"]',
    ];
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
    for (final v in values) {
      if (_validName(v)) return v!.trim();
    }
    return null;
  }

  String _clean(String s) => s
      .replaceAll(RegExp(r'[\uE000-\uF8FF]'), '')
      .replaceAll('\uFFFD', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _validName(String? s) {
    if (s == null) return false;
    final v = _clean(s);
    if (v.isEmpty || v.length > 32) return false;
    if (const {
      'X', 'x', '×', '登录', '注册', '退出', '退出登录', '个人主页', '资料',
      '主题', '回帖', '用户名', '昵称', '首页', '搜索', '设置',
    }.contains(v)) return false;
    if (v.contains('�') || v.contains('Ã') || v.contains('Â') || v.contains('â')) return false;
    return true;
  }
}
