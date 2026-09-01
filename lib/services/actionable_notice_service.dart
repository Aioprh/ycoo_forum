import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'member_service_v2.dart';
import 'net_client.dart';
import 'site_config.dart';

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

    // 只有页面确实是登录表单时才判定登录失效，不能仅凭“登录”文字判断。
    if (_isLoginPage(html)) {
      throw Exception('登录态已失效，请重新登录论坛');
    }
    return html;
  }

  static bool _isLoginPage(String html) {
    final lower = html.toLowerCase();
    final hasLogout = lower.contains('action=logout') || html.contains('退出登录');
    if (hasLogout) return false;

    // 分开检测 form 和 input，避免复杂引号正则在 Dart 字符串中造成解析问题。
    // Discuz/Comiis 的登录表单通常会出现 logging 页面动作或 login/loginform ID。
    final forms = RegExp(r'<form\b[^>]*>', caseSensitive: false).allMatches(html);
    var hasLoginForm = false;
    for (final match in forms) {
      final tag = match.group(0) ?? '';
      final action = RegExp(r'\baction\s*=\s*["\']?[^\s>]*', caseSensitive: false).firstMatch(tag)?.group(0) ?? '';
      final id = RegExp(r'\bid\s*=\s*["\']?[^\s>"\']+', caseSensitive: false).firstMatch(tag)?.group(0) ?? '';
      if (action.toLowerCase().contains('logging') || id.toLowerCase().contains('login')) {
        hasLoginForm = true;
        break;
      }
    }
    final hasLoginInput = RegExp(
      r'<input\b[^>]*\bname\s*=\s*["\']?(?:username|password|loginfield)\b',
      caseSensitive: false,
    ).hasMatch(html);
    return hasLoginForm && hasLoginInput;
  }

  Future<List<NativeNotice>> fetch({String view = 'all'}) async {
    final path = 'home.php?mod=space&do=notice&view=$view';
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

    final nodes = doc.querySelectorAll('.comiis_notice_list li, li.b_b.bg_f.cl, .ntc_list li, .comiis_nts li, .pmlist li, li');
    for (final node in nodes) {
      final text = _clean(node);
      if (text.length < 2 || text.length > 800 || _navigation(text)) continue;
      final href = _bestHref(node);
      final tid = _tid(href.isNotEmpty ? href : _allHref(node));
      final uid = _uid(href.isNotEmpty ? href : _allHref(node));
      final title = _clean(node.querySelector('h2,.ntc_title,.nts_title,dt,strong'));
      final body = _clean(node.querySelector('.ntc_body,.nts_body,dd') ?? node);
      final time = _clean(node.querySelector('em,time,.xg1,.xg2,[class*="time"],[class*="date"]'));
      final displayTitle = title.isEmpty ? (body.length > 60 ? body.substring(0, 60) : body) : title;
      final subtitle = time.isNotEmpty && !body.contains(time) ? '$time $body' : body;
      final key = '$href|$displayTitle|$body';
      if (!seen.add(key)) continue;
      final keyword = RegExp(r'(回复|评论|提到|通知|系统|赞了|收藏|提醒|关注|好友|主题|购买|充值|任务|注册|订单|经验|积分|星币|升级|留言|打招呼)').hasMatch(text);
      if (view != 'all' && !keyword) continue;
      result.add(NativeNotice(title: displayTitle, subtitle: subtitle, href: href, body: body, uid: uid, tid: tid));
      if (result.length >= 100) break;
    }

    if (result.isEmpty && firstError != null) throw Exception(firstError.toString().replaceFirst('Exception: ', ''));
    return result;
  }

  static String _clean(dynamic node) {
    if (node == null) return '';
    return node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _bestHref(dynamic node) {
    final candidates = <String>[];
    for (final a in node.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
      if (_tid(href) > 0) return href;
      if (_uid(href) > 0) candidates.add(href);
      if (href.contains('notice') || href.contains('space') || href.contains('thread') || href.contains('mod=')) candidates.add(href);
    }
    return candidates.isEmpty ? '' : candidates.first;
  }

  static String _allHref(dynamic node) => node.querySelector('a[href]')?.attributes['href'] ?? '';

  static int _tid(String href) {
    final m = RegExp(r'(?:thread-|[?&]tid=|[?&]topicid=)(\d+)', caseSensitive: false).firstMatch(href);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  static int _uid(String href) {
    final m = RegExp(r'(?:[?&]|%3F|%26)uid=(\d+)', caseSensitive: false).firstMatch(href);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  static bool _navigation(String text) => RegExp(r'^(首页|登录|注册|退出|下一页|上一页|更多|设置|通知|好友|关注|粉丝)$').hasMatch(text);
}
