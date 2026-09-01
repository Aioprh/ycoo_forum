import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'member_service_v2.dart';
import 'net_client.dart';
import 'site_config.dart';

class InteractiveNoticeAction {
  final String label;
  final String href;
  const InteractiveNoticeAction({required this.label, required this.href});
}

class InteractiveNotice {
  final NativeNotice notice;
  final String actor;
  final String time;
  final bool unread;
  final List<InteractiveNoticeAction> actions;

  const InteractiveNotice({
    required this.notice,
    this.actor = '',
    this.time = '',
    this.unread = false,
    this.actions = const [],
  });
}

class InteractiveNoticePage {
  final List<InteractiveNotice> items;
  final int page;
  final int totalPages;
  final bool hasNext;

  const InteractiveNoticePage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.hasNext,
  });
}

/// Reads notification pages while preserving the original action href.
class ActionableNoticeService {
  ActionableNoticeService._();
  static final instance = ActionableNoticeService._();

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final baseUri = Uri.parse('${SiteConfig.base}$path');
    final uri = baseUri.replace(queryParameters: {
      ...baseUri.queryParameters,
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final response = await NetClient.retry(() => client.get(uri, headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': '${SiteConfig.base}forum.php?mobile=2',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
    final html = NetClient.decode(response.bodyBytes);
    if (_isLoginPage(html)) throw Exception('登录态已失效，请重新登录论坛');
    return html;
  }

  static String _attr(Element element, String name) {
    final value = element.attributes[name];
    return value == null ? '' : value;
  }

  static bool _has(String value, String part) => value.toLowerCase().indexOf(part.toLowerCase()) >= 0;

  static bool _isLoginPage(String html) {
    final doc = parser.parse(html);
    final hasLogout = doc.querySelectorAll('a[href],form[action]').any((element) {
      final hrefText = _attr(element, 'href');
      final actionText = _attr(element, 'action');
      return _has(hrefText, 'action=logout') || _has(actionText, 'action=logout');
    }) || _has(doc.text.toString(), '退出登录');
    if (hasLogout) return false;
    final hasLoginForm = doc.querySelectorAll('form').any((form) {
      final actionText = _attr(form, 'action');
      final idText = _attr(form, 'id');
      final classText = _attr(form, 'class');
      return _has(actionText, 'logging') || _has(actionText, 'login') || idText.toLowerCase() == 'login' || _has(idText, 'loginform') || _has(classText, 'login');
    });
    final hasLoginInput = doc.querySelectorAll('input[name]').any((input) {
      final normalized = _attr(input, 'name').toLowerCase();
      return normalized == 'username' || normalized == 'password' || normalized == 'loginfield';
    });
    return hasLoginForm && hasLoginInput;
  }

  Future<InteractiveNoticePage> fetchInteractivePage({required String type, int page = 1}) async {
    final safePage = page < 1 ? 1 : page;
    final query = <String, String>{
      'mod': 'space',
      'do': 'notice',
      'view': 'interactive',
      'type': type,
      'mobile': '2',
      if (safePage > 1) 'page': '$safePage',
    };
    final path = Uri(path: 'home.php', queryParameters: query).toString();
    String html;
    Object? firstError;
    try {
      html = await _get(path);
    } catch (e) {
      firstError = e;
      try {
        html = await _get(Uri(path: 'home.php', queryParameters: query).toString());
      } catch (e2) {
        throw Exception(e2.toString().replaceFirst('Exception: ', ''));
      }
    }

    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) node.remove();

    // Discuz/Comiis 的消息提醒列表明确位于 .comiis_notice_list > ul。
    // 不能使用全局 li，否则会把“任务中心、主题专区”等页面导航误解析成提醒。
    final list = doc.querySelector('.comiis_notice_list > ul') ??
        doc.querySelector('.comiis_notice_list ul') ??
        doc.querySelector('.ntc_list, .comiis_nts, .pmlist');
    final nodes = list == null
        ? const <Element>[]
        : list.children.where((e) => e.localName == 'li').toList();

    final result = <InteractiveNotice>[];
    final seen = <String>{};
    for (final node in nodes) {
      final parsed = _parseInteractiveNode(node);
      if (parsed == null) continue;
      final key = '${parsed.notice.href}|${parsed.notice.title}|${parsed.notice.body}';
      if (!seen.add(key)) continue;
      result.add(parsed);
      if (result.length >= 100) break;
    }

    final totalPages = _totalPages(doc);
    final hasNext = _hasNextPage(doc, safePage, totalPages, result.length);
    if (result.isEmpty && firstError != null) {
      throw Exception(firstError.toString().replaceFirst('Exception: ', ''));
    }
    return InteractiveNoticePage(items: result, page: safePage, totalPages: totalPages, hasNext: hasNext);
  }

  InteractiveNotice? _parseInteractiveNode(Element node) {
    final text = _clean(node);
    if (text.length < 2 || text.length > 1200 || _navigation(text)) return null;

    final actorAnchor = node.querySelector('a[href*="uid="],a[href*="mod=space"],a[href*="username="]');
    final actor = _clean(actorAnchor);
    final href = _bestHref(node);
    final fallbackHref = href.isNotEmpty ? href : _allHref(node);
    final tid = _tid(fallbackHref);
    final uid = _uid(fallbackHref);
    final titleNode = node.querySelector('h2,.ntc_title,.nts_title,dt,strong');
    final bodyNode = node.querySelector('.ntc_body,.nts_body,dd,.comiis_notice_txt,.comiis_notice_content') ?? node;
    final body = _clean(bodyNode);
    final titleText = _clean(titleNode);
    final displayTitle = titleText.isNotEmpty ? titleText : _fallbackTitle(body);
    final time = _clean(node.querySelector('em,time,.xg1,.xg2,[class*="time"],[class*="date"]'));
    final subtitle = time.isNotEmpty && !body.contains(time) ? '$time $body' : body;
    final unread = _has(_attr(node, 'class'), 'new') || _has(_attr(node, 'class'), 'unread') || node.querySelector('.new,.unread,[class*="new"],[class*="unread"]') != null;

    return InteractiveNotice(
      notice: NativeNotice(title: displayTitle, subtitle: subtitle, href: fallbackHref, body: body, uid: uid, tid: tid),
      actor: actor,
      time: time,
      unread: unread,
      actions: _actions(node),
    );
  }

  List<InteractiveNoticeAction> _actions(Element node) {
    final result = <InteractiveNoticeAction>[];
    final seen = <String>{};
    for (final a in node.querySelectorAll('a[href]')) {
      final href = _attr(a, 'href').trim();
      final label = _clean(a);
      if (href.isEmpty || label.isEmpty || href.startsWith('#') || href.toLowerCase().startsWith('javascript:')) continue;
      if (_navigation(label) || label.length > 30) continue;
      if (!seen.add('$label|$href')) continue;
      result.add(InteractiveNoticeAction(label: label, href: href));
      if (result.length >= 4) break;
    }
    return result;
  }

  int _totalPages(Document doc) {
    final options = doc.querySelectorAll('#dumppage option');
    if (options.isNotEmpty) {
      final values = options.map((e) => int.tryParse(_clean(e))).whereType<int>().toList();
      if (values.isNotEmpty) return values.reduce((a, b) => a > b ? a : b);
    }
    var maxPage = 1;
    for (final a in doc.querySelectorAll('.pg a[href*="page="]')) {
      final uri = Uri.tryParse(_attr(a, 'href'));
      final p = int.tryParse(uri?.queryParameters['page'] ?? '');
      if (p != null && p > maxPage) maxPage = p;
    }
    return maxPage;
  }

  bool _hasNextPage(Document doc, int page, int totalPages, int count) {
    if (totalPages > page) return true;
    if (doc.querySelector('.pg a.nxt, a.nxt') != null) return true;
    return count >= 20 && totalPages == page;
  }

  String _fallbackTitle(String body) => body.length > 60 ? body.substring(0, 60) : body;

  static String _clean(Element? node) => node == null ? '' : node.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _bestHref(Element node) {
    final candidates = <String>[];
    for (final a in node.querySelectorAll('a[href]')) {
      final href = _attr(a, 'href').trim();
      if (href.isEmpty || href.startsWith('#') || href.toLowerCase().startsWith('javascript:')) continue;
      if (_tid(href) > 0) return href;
      if (_uid(href) > 0) candidates.add(href);
      if (_has(href, 'notice') || _has(href, 'space') || _has(href, 'thread') || _has(href, 'mod=')) candidates.add(href);
    }
    return candidates.isEmpty ? '' : candidates.first;
  }

  static String _allHref(Element node) => _attr(node.querySelector('a[href]') ?? Element.tag('a'), 'href');

  static int _tid(String href) {
    final raw = href.trim();
    if (raw.isEmpty) return 0;
    final uri = Uri.tryParse(raw);
    final queryTid = uri?.queryParameters['tid'] ?? uri?.queryParameters['topicid'];
    final queryValue = int.tryParse(queryTid ?? '');
    if (queryValue != null && queryValue > 0) return queryValue;
    final decoded = Uri.decodeFull(raw);
    final m = RegExp(r'(?:thread-|[?&]tid=|[?&]topicid=)(\d+)', caseSensitive: false).firstMatch(decoded);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  static int _uid(String href) {
    final raw = href.trim();
    if (raw.isEmpty) return 0;
    final candidates = <String>[raw];
    try { candidates.add(Uri.decodeFull(raw)); } catch (_) {}
    for (final candidate in candidates) {
      final uri = Uri.tryParse(candidate);
      final parsed = int.tryParse(uri?.queryParameters['uid'] ?? '');
      if (parsed != null && parsed > 0) return parsed;
      final m = RegExp(r'(?:[?&]|%3F|%26)uid(?:=|%3D)(\d+)', caseSensitive: false).firstMatch(candidate);
      final value = int.tryParse(m?.group(1) ?? '');
      if (value != null && value > 0) return value;
      final space = RegExp(r'(?:space|user)[-_](\d+)', caseSensitive: false).firstMatch(candidate);
      final spaceUid = int.tryParse(space?.group(1) ?? '');
      if (spaceUid != null && spaceUid > 0) return spaceUid;
    }
    return 0;
  }

  static bool _navigation(String text) => RegExp(r'^(首页|登录|注册|退出|下一页|上一页|更多|设置|通知|好友|关注|粉丝|任务中心|主题专区)$').hasMatch(text);

  Future<List<NativeNotice>> fetch({String view = 'all', String? type}) async {
    final query = StringBuffer('home.php?mod=space&do=notice&view=$view');
    if (type != null && type.isNotEmpty) query.write('&type=$type');
    final path = query.toString();
    String html;
    Object? firstError;
    try {
      html = await _get('$path&mobile=2');
    } catch (e) {
      firstError = e;
      try {
        html = await _get(path);
      } catch (e2) {
        throw Exception(e2.toString().replaceFirst('Exception: ', ''));
      }
    }

    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) node.remove();
    final result = <NativeNotice>[];
    final seen = <String>{};
    final list = doc.querySelector('.comiis_notice_list > ul') ?? doc.querySelector('.comiis_notice_list ul') ?? doc.querySelector('.ntc_list,.comiis_nts,.pmlist');
    final nodes = list == null ? const <Element>[] : list.children.where((e) => e.localName == 'li').toList();
    for (final node in nodes) {
      final text = _clean(node);
      if (text.length < 2 || text.length > 800 || _navigation(text)) continue;
      final href = _bestHref(node);
      final fallbackHref = href.isNotEmpty ? href : _allHref(node);
      final tid = _tid(fallbackHref);
      final uid = _uid(fallbackHref);
      final title = _clean(node.querySelector('h2,.ntc_title,.nts_title,dt,strong'));
      final body = _clean(node.querySelector('.ntc_body,.nts_body,dd,.comiis_notice_txt,.comiis_notice_content') ?? node);
      final time = _clean(node.querySelector('em,time,.xg1,.xg2,[class*="time"],[class*="date"]'));
      final displayTitle = title.isEmpty ? (body.length > 60 ? body.substring(0, 60) : body) : title;
      final subtitle = time.isNotEmpty && !body.contains(time) ? '$time $body' : body;
      final key = '$fallbackHref|$displayTitle|$body';
      if (!seen.add(key)) continue;
      result.add(NativeNotice(title: displayTitle, subtitle: subtitle, href: fallbackHref, body: body, uid: uid, tid: tid));
      if (result.length >= 100) break;
    }
    if (result.isEmpty && firstError != null) throw Exception(firstError.toString().replaceFirst('Exception: ', ''));
    return result;
  }
}
