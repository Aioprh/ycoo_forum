import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// Resolves the real forum username independently from the mobile profile
/// page. Some YCC/Discuz mobile templates render an icon + "资料" as the
/// visible text of the profile header, so that text must never be treated as
/// the username.
class ProfileUsernameService {
  ProfileUsernameService._();
  static final instance = ProfileUsernameService._();
  static String get _base => SiteConfig.base;

  Future<String?> resolve(int uid, {String? fallback}) async {
    if (uid <= 0) return _valid(fallback) ? fallback!.trim() : null;
    final paths = <String>[
      'member.php?mod=viewpro&uid=$uid&mobile=2',
      'member.php?mod=viewpro&uid=$uid',
      'home.php?mod=space&uid=$uid&do=profile',
      'home.php?mod=space&uid=$uid&do=profile&mobile=2',
    ];
    for (final path in paths) {
      try {
        final html = await _get(path);
        final name = _parse(html, uid);
        if (_valid(name)) return name;
      } catch (_) {}
    }
    return _valid(fallback) ? fallback!.trim() : null;
  }

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final parsed = Uri.parse('$_base$path');
    final uri = parsed.replace(queryParameters: {
      ...parsed.queryParameters,
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final cookie = AuthService.instance.authCookie;
    final response = await NetClient.retry(() => client.get(uri, headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(const Duration(seconds: 15)));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return NetClient.decode(response.bodyBytes);
  }

  static String? _parse(String html, int uid) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) {
      node.remove();
    }

    // 结构化锚点白名单：只信任模板的真实“用户名”位置，不用通配类名(.username/.nickname)，
    // 它们会误命中导航/UI 词。实测 ycoo comiis 模板真实昵称藏在 .comiis_space_info h2；
    // 标准 Discuz 模板则是 #uhd .vwmy。
    const selectors = <String>[
      '.comiis_space_info h2',
      '#uhd .vwmy a',
      '#uhd .vwmy',
      '.vwmy a',
      '.vwmy',
    ];
    for (final selector in selectors) {
      final value = _stripUi(_clean(doc.querySelector(selector)?.text ?? ''));
      if (_valid(value)) return value;
    }

    // Some templates expose it as a JS variable instead of visible markup.
    for (final pattern in <RegExp>[
      RegExp(r'''(?:spaceusername|space_username|user_name|username)\s*[:=]\s*['"]([^'"]{1,64})['"]''', caseSensitive: false),
      RegExp(r'''data-(?:username|user-name)\s*=\s*['"]([^'"]{1,64})['"]''', caseSensitive: false),
    ]) {
      final match = pattern.firstMatch(html);
      final value = _stripUi(_clean(match?.group(1) ?? ''));
      if (_valid(value)) return value;
    }

    // Discuz frequently puts the username on the exact uid profile link.
    final uidText = uid.toString();
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').toLowerCase();
      final hasUid = href.contains('uid=$uidText') ||
          href.contains('uid%3d$uidText') ||
          href.contains('uid%253d$uidText');
      if (!hasUid || !href.contains('mod=space')) continue;
      final value = _stripUi(_clean(a.text));
      if (_valid(value)) return value;
    }

    for (var value in <String>[
      doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '',
      doc.querySelector('title')?.text ?? '',
    ]) {
      value = _stripUi(_clean(value))
          .replaceFirst(RegExp(r'\s*[-|｜]\s*源论坛\s*$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*的个人资料\s*$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^个人资料\s*[-|｜:]\s*', caseSensitive: false), '')
          .trim();
      if (_valid(value)) return value;
    }
    return null;
  }

  static String _stripUi(String value) {
    var v = _clean(value);
    // Missing icon fonts can become a square/box glyph followed by the label.
    v = v.replaceAll(RegExp(r'^[\u2000-\u206F\u25A0-\u25FF\u2600-\u27BF\uE000-\uF8FF]+'), '').trim();
    v = v.replaceAll(RegExp(r'^(?:[\u25A1\u25A0□■▣▤▥▦▧▨▩×✕✖]+\s*)'), '').trim();
    return v;
  }

  static bool _valid(String? value) {
    if (value == null) return false;
    final v = _stripUi(value);
    if (v.isEmpty || v.length > 32 || v.contains('�') || v.contains('\uFFFD')) return false;
    final compact = v.replaceAll(RegExp(r'[\s\u2000-\u206F\u25A0-\u27BF\uE000-\uF8FF]+'), '');
    if (RegExp(r'^(?:资料|个人资料|用户资料|用户|用户名|昵称|关注|已关注|聊天|私信|回复|主题|回帖|帖子|帖子数|粉丝|积分|星币|登录|注册|退出|刷新|个人中心|Ta的空间|空间|我的|提示信息|系统提示|温馨提示|提示|抱歉|无权|没有权限|不存在|该用户)$', caseSensitive: false).hasMatch(compact)) return false;
    return !RegExp(r'^(?:UID|用户|用户名|昵称)\s*[:：]?$', caseSensitive: false).hasMatch(v);
  }

  static String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
