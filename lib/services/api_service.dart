import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/board.dart';
import '../models/thread_detail.dart';
import '../models/thread_item.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 源论坛移动端数据抓取与解析。
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const String _base = 'https://www.ycoo.net/';
  static const Duration _timeout = Duration(seconds: 20);

  static String _abs(String u) {
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return _base + u.replaceFirst(RegExp(r'^\./'), '');
  }

  Future<String> _get(String url, {Map<String, String>? query}) async {
    final client = await NetClient.instance.client;
    final uri = Uri.parse(url).replace(queryParameters: query);
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache',
    };
    final cookie = AuthService.instance.authCookie;
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;

    final resp = await NetClient.retry(() => client
        .get(uri, headers: headers)
        .timeout(_timeout));
    if (resp.statusCode != 200) {
      throw Exception('请求失败 HTTP ${resp.statusCode}');
    }
    return NetClient.decode(resp.bodyBytes);
  }

  static String guideUrl(String view) =>
      '$_base' 'forum.php?mod=guide&view=$view&mobile=2';

  static String forumUrl(int fid, int page) =>
      '$_base' 'forum.php?mod=forumdisplay&fid=$fid&mobile=2&page=$page';

  Future<List<ThreadItem>> fetchThreads(String url) async {
    final html = await _get(url);
    final doc = parser.parse(html);
    final items = <ThreadItem>[];
    for (final li in doc.querySelectorAll('li.forumlist_li')) {
      final item = _parseThreadItem(li);
      if (item != null) items.add(item);
    }
    return items;
  }

  ThreadItem? _parseThreadItem(dom.Element li) {
    final titleA = li.querySelector('.mmlist_li_box h2 a');
    final title = titleA?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    final href = titleA?.attributes['href'] ?? '';
    final tid = _firstInt(RegExp(r'thread-(\d+)'), href) ?? 0;
    if (tid == 0 || title.isEmpty) return null;
    final boardA = li.querySelector('.comiis_xznalist_bk a');
    final boardHref = boardA?.attributes['href'] ?? '';
    final nums = li.querySelectorAll('.comiis_xznalist_bottom span.comiis_tm')
        .map((e) => int.tryParse(e.text.trim()) ?? 0).toList();
    final topAuthor = li.querySelector('.forumlist_li_top .top_user');
    return ThreadItem(
      tid: tid,
      title: title,
      author: _normSpace(topAuthor?.text ?? ''),
      avatar: _abs(li.querySelector('.forumlist_li_top .top_tximg')?.attributes['src'] ?? ''),
      fid: _firstInt(RegExp(r'forum-(\d+)'), boardHref) ?? 0,
      boardName: _normSpace(boardA?.text ?? ''),
      level: _normSpace(li.querySelector('.forumlist_li_top .top_lev')?.text ?? ''),
      time: _normSpace(li.querySelector('.forumlist_li_time .f_d')?.text ?? ''),
      subtitle: _normSpace(li.querySelector('.list_body a')?.text ?? ''),
      cover: _abs(li.querySelector('.comiis_pyqlist_img img')?.attributes['src'] ?? ''),
      likeCount: nums.isNotEmpty ? nums[0] : 0,
      replyCount: nums.length > 1 ? nums[1] : 0,
      viewCount: nums.length > 2 ? nums[2] : 0,
    );
  }

  static String get boardUrl => '$_base' 'forum.php?forumlist=1&mobile=2';

  Future<List<ForumCategory>> fetchBoards() async {
    final html = await _get(boardUrl);
    final doc = parser.parse(html);
    final names = doc.querySelectorAll('.comiis_bbs_show h2')
        .map((e) => _normSpace(e.text)).where((e) => e.isNotEmpty).toList();
    final groups = doc.querySelectorAll('.comiis_forum_nbox');
    final cats = <ForumCategory>[];
    for (var i = 0; i < groups.length; i++) {
      final name = i < names.length ? names[i] : '其他';
      final boards = <ForumBoard>[];
      for (final li in groups[i].querySelectorAll('li')) {
        final a = li.querySelector('a');
        final href = a?.attributes['href'] ?? '';
        final fid = _firstInt(RegExp(r'forum-(\d+)'), href) ?? 0;
        if (fid == 0) continue;
        boards.add(ForumBoard(
          fid: fid,
          name: _normSpace(a?.querySelector('span')?.text ?? ''),
          icon: _abs(a?.querySelector('img')?.attributes['src'] ?? ''),
          today: _normSpace(a?.querySelector('p')?.text ?? ''),
        ));
      }
      if (boards.isNotEmpty) cats.add(ForumCategory(name: name, boards: boards));
    }
    if (cats.isEmpty) throw Exception('未解析到版块数据');
    return cats;
  }

  static String detailUrl(int tid) => '$_base' 'thread-$tid-1-1.html';

  Future<ThreadDetail> fetchThreadDetail(int tid) async {
    final html = await _get(detailUrl(tid));
    final doc = parser.parse(html);
    final boardLink = doc.querySelector('.comiis_bankuai .bankuai_tit a');
    final boardName = _normSpace(boardLink?.text ?? '');
    var title = _firstMeta(doc, 'og:title') ?? _firstMeta(doc, 'title') ?? '';
    final titleMatch = RegExp(r'<title>(.*?)</title>').firstMatch(html);
    if (title.isEmpty && titleMatch != null) title = titleMatch.group(1)!;
    if (boardName.isNotEmpty) {
      title = title.replaceAll(' - $boardName', '').replaceAll('-$boardName', '');
    }
    title = title.replaceAll(' - 源论坛', '').replaceAll('- 源论坛', '').trim();

    final paid = _parsePaidState(doc);
    final body = _collectPosts(doc).join();
    return ThreadDetail(
      tid: tid,
      title: title,
      author: _normSpace(doc.querySelector('.top_user')?.text ?? ''),
      avatar: _abs(doc.querySelector('img.top_tximg')?.attributes['src'] ?? ''),
      level: _normSpace(doc.querySelector('.top_lev')?.text ?? ''),
      time: _normSpace(doc.querySelector('.comiis_postli_time .kmtime')?.text ?? ''),
      fid: _firstInt(RegExp(r'forum-(\d+)'), boardLink?.attributes['href'] ?? '') ?? 0,
      boardName: boardName,
      bodyHtml: body,
      isPaid: paid.isPaid,
      price: paid.price,
      currency: paid.currency,
      purchaseUrl: paid.purchaseUrl.isEmpty ? detailUrl(tid) : paid.purchaseUrl,
    );
  }

  _PaidState _parsePaidState(dom.Document doc) {
    final nodes = doc.querySelectorAll('body *');
    for (final e in nodes) {
      final text = _normSpace(e.text);
      if (!text.contains('购买主题') || !text.contains('星币')) continue;
      final price = _firstInt(RegExp(r'(\d+)\s*星币'), text);
      String href = '';
      final a = e.querySelector('a') ?? (e.localName == 'a' ? e : null);
      if (a != null) href = _abs(a.attributes['href'] ?? '');
      if (href.isEmpty) {
        final parent = e.parent;
        final pa = parent?.querySelector('a');
        if (pa != null) href = _abs(pa.attributes['href'] ?? '');
      }
      return _PaidState(true, price, '星币', href);
    }
    // 某些模板在正文里只留下“本主题需向作者支付 N 星币”。
    final allText = _normSpace(doc.body?.text ?? '');
    if (allText.contains('本主题需向作者支付') && allText.contains('星币')) {
      return _PaidState(true, _firstInt(RegExp(r'支付\s*(\d+)\s*星币'), allText), '星币', '');
    }
    return const _PaidState(false, null, '星币', '');
  }

  static List<String> _collectPosts(dom.Document doc) {
    final tables = doc.querySelectorAll('.comiis_message_table');
    final out = <String>[];
    for (final t in tables) {
      final content = t.innerHtml.trim();
      var author = '', level = '', floor = '', time = '';
      dom.Element? post = t.parent;
      while (post != null && !post.classes.contains('comiis_postli')) post = post.parent;
      if (post != null) {
        author = _normSpace(post.querySelector('.top_user')?.text ?? '');
        level = _normSpace(post.querySelector('.top_lev')?.text ?? '');
        floor = _normSpace(post.querySelector('.f_d.y')?.text ?? '');
        time = _normSpace(post.querySelector('.kmtime')?.text ?? post.querySelector('.comiis_tm')?.text ?? '');
      }
      if (floor.isEmpty) floor = out.isEmpty ? '楼主' : '${out.length + 1}楼';
      out.add('<div class="post-card"><div class="post-hd"><span class="p-floor">$floor</span><b class="p-author">$author</b>${level.isEmpty ? '' : '<span class="p-level">$level</span>'}</div>${time.isEmpty ? '' : '<div class="p-time">$time</div>'}<div class="p-body">$content</div></div>');
    }
    return out;
  }

  static String _normSpace(String s) {
    s = s.replaceAll(RegExp(r'[\uE000-\uF8FF]+'), '');
    return s.replaceAll(RegExp(r'[ \t\u00A0\u3000]+'), ' ').trim();
  }

  static int? _firstInt(RegExp re, String s) {
    final m = re.firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static String? _firstMeta(dom.Document doc, String property) {
    for (final e in doc.querySelectorAll('meta')) {
      final key = e.attributes['property'] ?? e.attributes['name'] ?? '';
      if (key == property) return e.attributes['content'];
    }
    return null;
  }
}

class _PaidState {
  final bool isPaid;
  final int? price;
  final String currency;
  final String purchaseUrl;
  const _PaidState(this.isPaid, this.price, this.currency, this.purchaseUrl);
}