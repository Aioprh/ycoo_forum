import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

class MemberNotice {
  final String title;
  final String subtitle;
  const MemberNotice({required this.title, required this.subtitle});
}

class CreditSummary {
  final String balance;
  final List<String> records;
  const CreditSummary({required this.balance, required this.records});
}

class MemberService {
  MemberService._();
  static final instance = MemberService._();
  static String get _base => SiteConfig.base;

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
    final parsed = Uri.parse('$_base$path');
    final params = <String, String>{...parsed.queryParameters, '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString()};
    final uri = parsed.replace(queryParameters: params);
    final response = await NetClient.retry(() => client.get(uri, headers: headers).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
    final html = NetClient.decode(response.bodyBytes);
    if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
    return html;
  }

  Future<String> _getFirstWorking(List<String> paths) async {
    Object? last;
    for (final path in paths) {
      try {
        final html = await _get(path);
        if (html.trim().isNotEmpty) return html;
      } catch (e) {
        last = e;
      }
    }
    throw Exception(last?.toString().replaceFirst('Exception: ', '') ?? '请求失败');
  }

  Future<List<ThreadItem>> fetchThreads(String path) async {
    final paths = <String>[path];
    // Discuz 主题页在不同模板下对 mobile 参数的输出结构不同，第二次用桌面模板兜底。
    final uri = Uri.tryParse('$_base$path');
    if (uri != null) {
      final q = <String, String>{...uri.queryParameters}..remove('mobile');
      paths.add(uri.replace(queryParameters: q).path + (q.isEmpty ? '' : '?${Uri(queryParameters: q).query}'));
    }
    final html = await _getFirstWorking(paths);
    final collectionPage = _isMemberCollectionPath(path);
    return _parseThreads(html, collectionPage: collectionPage);
  }

  List<ThreadItem> _parseThreads(String html, {bool collectionPage = false}) {
    final doc = parser.parse(html);
    final result = <ThreadItem>[];
    final seen = <int>{};

    // 这里不能无差别扫描页面所有 thread-xxx 链接。
    // 个人主题/收藏页顶部可能带有“发帖前请注意查看【源社区总版规】”的站点公告，
    // 这个链接不是用户自己的主题，也不是用户收藏，旧解析器会把它误当成列表项。
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final match = RegExp(r'(?:thread-|[?&]tid=)(\d+)', caseSensitive: false).firstMatch(href);
      if (match == null) continue;
      final tid = int.tryParse(match.group(1) ?? '') ?? 0;
      final title = _clean(a.text);
      if (tid <= 0 || title.isEmpty || seen.contains(tid)) continue;
      if (_looksLikeNavigation(title) || title.length < 2) continue;
      if (RegExp(r'^(回复|查看|详情|购买主题|下一页|上一页|首页|尾页|分享|收藏)$').hasMatch(title)) continue;
      if (collectionPage && _isSiteWideAnnouncementLink(a, title)) continue;
      seen.add(tid);
      final parentText = _clean(a.parent?.text ?? '');
      final counts = _findThreadCounts(a);
      var board = '';
      dom.Element? cur = a.parent;
      while (cur != null) {
        final forumLink = cur.querySelector('a[href*="forum-"]');
        if (forumLink != null && _clean(forumLink.text).isNotEmpty) {
          board = _clean(forumLink.text);
          break;
        }
        cur = cur.parent;
      }
      result.add(ThreadItem(
        tid: tid,
        title: title,
        author: '',
        avatar: '',
        fid: int.tryParse(RegExp(r'(?:forum-|[?&]fid=)(\d+)').firstMatch(a.parent?.outerHtml ?? '')?.group(1) ?? '') ?? 0,
        boardName: board,
        level: '',
        time: '',
        subtitle: parentText == title ? '' : parentText.replaceFirst(title, '').trim(),
        cover: '',
        likeCount: counts.$1,
        replyCount: counts.$2,
        viewCount: counts.$3,
      ));
    }
    return result;
  }

  static bool _isMemberCollectionPath(String path) {
    final uri = Uri.tryParse('$_base$path');
    if (uri == null) return false;
    final doValue = uri.queryParameters['do']?.toLowerCase() ?? '';
    return doValue == 'thread' || doValue == 'favorite';
  }

  static bool _isSiteWideAnnouncementLink(dom.Element a, String title) {
    final normalized = _clean(title).replaceAll(RegExp(r'\s+'), '');
    if (normalized == '【源社区总版规】' || normalized == '源社区总版规') return true;

    final style = (a.attributes['style'] ?? '').toLowerCase();
    var ancestor = a.parent;
    for (var depth = 0; depth < 5 && ancestor != null; depth++, ancestor = ancestor.parent) {
      final text = _clean(ancestor.text);
      // 站点公告的典型结构：公告提示文字 + 蓝色的版规链接。
      if (text.contains('发帖前请注意查看') && text.contains('版规')) return true;
      if (style.contains('color: blue') && text.contains('版规')) return true;
    }
    return false;
  }

  /// 在 a 的祖先容器里寻找 comiis_tm 数值 spans (comiis 私用图标字体的计数)，
  /// 返回 (点赞数, 回复数, 浏览量)。找不到时 fallback: 用正则扫祖先文本。
  (int, int, int) _findThreadCounts(dom.Element a) {
    dom.Element? cur = a;
    while (cur != null) {
      final spans = cur.querySelectorAll('span[class*="comiis_tm"]');
      final nums = <int>[];
      for (final s in spans) {
        final v = int.tryParse(_clean(s.text));
        if (v != null) nums.add(v);
      }
      if (nums.length >= 2) {
        final views = nums.last;
        final replies = nums[nums.length - 2];
        final likes = nums.length >= 3 ? nums[nums.length - 3] : 0;
        return (likes, replies, views);
      }
      cur = cur.parent;
    }
    var text = '';
    cur = a.parent;
    while (cur != null) {
      final t = _clean(cur.text);
      if (t.length > text.length) text = t;
      cur = cur.parent;
    }
    if (text.isEmpty) return (0, 0, 0);
    int? grab(List<String> keys) {
      for (final k in keys) {
        final m = RegExp('$k\\s*[:：]?\\s*(\\d+)').firstMatch(text);
        if (m != null) return int.tryParse(m.group(1)!);
      }
      return null;
    }
    return (0, grab(const ['回复', '评论', '回帖']) ?? 0, grab(const ['浏览', '查看', '人气']) ?? 0);
  }

  Future<List<MemberNotice>> fetchNotices() async {
    final html = await _getFirstWorking([
      'home.php?mod=space&do=notice&mobile=2',
      'home.php?mod=space&do=notice',
    ]);
    final doc = parser.parse(html);
    final result = <MemberNotice>[];
    final seen = <String>{};
    for (final node in doc.querySelectorAll('li, tr, article, .nts, .notice, .notice_li, .comiis_notice, .ntc_list')) {
      final text = _clean(node.text);
      if (text.length < 2 || text.length > 500) continue;
      if (!RegExp(r'(回复|评论|提到|通知|系统|赞了|收藏|提醒|关注|好友|主题)').hasMatch(text)) continue;
      if (!seen.add(text)) continue;
      final title = text.length > 60 ? text.substring(0, 60) : text;
      result.add(MemberNotice(title: title, subtitle: text));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<CreditSummary> fetchCredits() async {
    final html = await _getFirstWorking([
      'home.php?mod=spacecp&ac=credit&mobile=2',
      'home.php?mod=spacecp&ac=credit',
    ]);
    final doc = parser.parse(html);
    final text = _clean(doc.body?.text ?? '');
    final records = <String>[];
    for (final line in text.split(RegExp(r'\s{2,}|\n'))) {
      final value = _clean(line);
      if (value.isEmpty) continue;
      if (RegExp(r'(星币|积分|余额|充值|消费|交易|收入|支出)').hasMatch(value) && !records.contains(value)) records.add(value);
    }
    final balanceMatch = RegExp(r'(?:星币|余额)\s*[:：]?\s*(\d+(?:\.\d+)?)').firstMatch(text);
    return CreditSummary(balance: balanceMatch?.group(1) ?? '—', records: records.take(30).toList());
  }

  static String _clean(String text) =>
      text
          .replaceAll('\uFFFD', '')
          .replaceAll(RegExp(r'[\uE000-\uF8FF]'), '')
          .replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _looksLikeLogin(String html) {
    final t = _clean(parser.parse(html).body?.text ?? '');
    if (t.isEmpty) return true;
    final hasLoginForm = RegExp(r'(用户名|登录密码)').hasMatch(t) && RegExp(r'登录').hasMatch(t);
    final hasLogout = html.contains('action=logout');
    return hasLoginForm && !hasLogout;
  }

  static bool _looksLikeNavigation(String text) {
    const nav = {'下一页', '上一页', '首页', '更多', '回复', '查看', '详情', '登录', '注册'};
    return nav.contains(text);
  }
}