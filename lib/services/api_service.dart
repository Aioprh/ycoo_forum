import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/board.dart';
import '../models/thread_detail.dart';
import '../models/thread_item.dart';
import 'net_client.dart';

/// 源论坛(https://www.ycoo.net)移动端数据抓取与解析。
/// 站点为 Discuz!X + comiis 手机模板,本层只做「阅读侧」的只读抓取。
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const String _base = 'https://www.ycoo.net/';

  static const Duration _timeout = Duration(seconds: 20);

  /// 把相对路径补全成绝对地址(基于站点根,忽略 comiis 的 `./` 前缀)。
  static String _abs(String u) {
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return _base + u.replaceFirst(RegExp(r'^\./'), '');
  }

  Future<String> _get(String url, {Map<String, String>? query}) async {
    final client = await NetClient.instance.client;
    final uri = Uri.parse(url).replace(queryParameters: query);
    // 弱网/瞬时断连(ERR_CONNECTION_CLOSED)做自动重试,GET 无副作用。
    final resp = await NetClient.retry(() => client
        .get(uri, headers: {'User-Agent': NetClient.ua})
        .timeout(_timeout));
    if (resp.statusCode != 200) {
      throw Exception('请求失败 HTTP ${resp.statusCode}');
    }
    return NetClient.decode(resp.bodyBytes);
  }

  // ------------------------------------------------------------------
  // 列表数据源
  // ------------------------------------------------------------------

  /// 导读类列表 URL(首页各 Tab)。
  static String guideUrl(String view) =>
      '$_base' 'forum.php?mod=guide&view=$view&mobile=2';

  /// 版块帖子列表 URL(分页)。
  static String forumUrl(int fid, int page) =>
      '$_base' 'forum.php?mod=forumdisplay&fid=$fid&mobile=2&page=$page';

  /// 抓取并解析一份「帖子列表」(li.forumlist_li),用于导读 / 版块列表。
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

    /// 底部点赞 / 回复 / 浏览三个数字(均为 comiis_tm)。
    final nums = li
        .querySelectorAll('.comiis_xznalist_bottom span.comiis_tm')
        .map((e) => int.tryParse(e.text.trim()) ?? 0)
        .toList();

    final topAuthor = li.querySelector('.forumlist_li_top .top_user');

    return ThreadItem(
      tid: tid,
      title: title,
      author: _normSpace(topAuthor?.text ?? ''),
      avatar: _abs(
          li.querySelector('.forumlist_li_top .top_tximg')?.attributes['src'] ??
              ''),
      fid: _firstInt(RegExp(r'forum-(\d+)'), boardHref) ?? 0,
      boardName: _normSpace(boardA?.text ?? ''),
      level: _normSpace(li.querySelector('.forumlist_li_top .top_lev')?.text ??
          ''),
      time: _normSpace(li.querySelector('.forumlist_li_time .f_d')?.text ?? ''),
      subtitle: _normSpace(li.querySelector('.list_body a')?.text ?? ''),
      cover: _abs(li
                  .querySelector('.comiis_pyqlist_img img')
                  ?.attributes['src'] ??
              ''),
      likeCount: nums.isNotEmpty ? nums[0] : 0,
      replyCount: nums.length > 1 ? nums[1] : 0,
      viewCount: nums.length > 2 ? nums[2] : 0,
    );
  }

  // ------------------------------------------------------------------
  // 版块列表
  // ------------------------------------------------------------------

  static String get boardUrl => '$_base' 'forum.php?forumlist=1&mobile=2';

  /// 抓取版块分类列表。
  Future<List<ForumCategory>> fetchBoards() async {
    final html = await _get(boardUrl);
    final doc = parser.parse(html);

    final names = doc
        .querySelectorAll('.comiis_bbs_show h2')
        .map((e) => _normSpace(e.text))
        .where((e) => e.isNotEmpty)
        .toList();
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
      if (boards.isNotEmpty) {
        cats.add(ForumCategory(name: name, boards: boards));
      }
    }
    if (cats.isEmpty) throw Exception('未解析到版块数据');
    return cats;
  }

  // ------------------------------------------------------------------
  // 帖子详情
  // ------------------------------------------------------------------

  static String detailUrl(int tid) => '$_base' 'thread-$tid-1-1.html';

  /// 抓取帖子详情:原生头部信息 + 正文 HTML。
  Future<ThreadDetail> fetchThreadDetail(int tid) async {
    final html = await _get(detailUrl(tid));
    final doc = parser.parse(html);

    final boardLink = doc.querySelector('.comiis_bankuai .bankuai_tit a');

    // 先取版块名,再据此去掉标题里的「 - 版块名 / 源论坛」后缀。
    final boardName = _normSpace(boardLink?.text ?? '');

    var title = _firstMeta(doc, 'og:title') ?? _firstMeta(doc, 'title') ?? '';
    final titleMatch = RegExp(r'<title>(.*?)</title>').firstMatch(html);
    if (title.isEmpty && titleMatch != null) {
      title = titleMatch.group(1)!;
    }
    if (boardName.isNotEmpty) {
      // 兼容「 - 版块名」与「-版块名」两种后缀写法。
      title = title
          .replaceAll(' - $boardName', '')
          .replaceAll('-$boardName', '');
    }
    title = title
        .replaceAll(' - 源论坛', '')
        .replaceAll('- 源论坛', '')
        .trim();

    // 楼主 + 全部回复楼层拼成完整评论区 HTML(交给 WebView 渲染)。
    final body = _collectPosts(doc).join();

    return ThreadDetail(
      tid: tid,
      title: title,
      author: _normSpace(doc.querySelector('.top_user')?.text ?? ''),
      avatar: _abs(doc.querySelector('img.top_tximg')?.attributes['src'] ?? ''),
      level: _normSpace(doc.querySelector('.top_lev')?.text ?? ''),
      time: _normSpace(
          doc.querySelector('.comiis_postli_time .kmtime')?.text ?? ''),
      fid: _firstInt(RegExp(r'forum-(\d+)'), boardLink?.attributes['href'] ?? '') ??
          0,
      boardName: boardName,
      bodyHtml: body,
    );
  }

  /// 收集帖子全部回帖楼层(每层一个 `comiis_postli`),拼成带楼头样式的一段 HTML。
  ///
  /// 楼层号/作者/等级/时间位于所在 `comiis_postli` 的头部节点,正文是
  /// 其中的 `.comiis_message_table`。图片等相对路径依赖 WebView 的
  /// `<base href>` 解析,故此处不逐个补全。
  static List<String> _collectPosts(dom.Document doc) {
    final tables = doc.querySelectorAll('.comiis_message_table');
    final out = <String>[];
    for (final t in tables) {
      final content = t.innerHtml.trim();
      var author = '', level = '', floor = '', time = '';
      dom.Element? post = t.parent;
      while (post != null && !post.classes.contains('comiis_postli')) {
        post = post.parent;
      }
      if (post != null) {
        author = _normSpace(post.querySelector('.top_user')?.text ?? '');
        level = _normSpace(post.querySelector('.top_lev')?.text ?? '');
        floor = _normSpace(post.querySelector('.f_d.y')?.text ?? '');
        time = _normSpace(
                post.querySelector('.kmtime')?.text ??
                    post.querySelector('.comiis_tm')?.text ??
                    '');
      }
      if (floor.isEmpty) floor = out.isEmpty ? '楼主' : '${out.length + 1}楼';
      out.add('<div class="post-card">'
          '<div class="post-hd">'
          '<span class="p-floor">$floor</span>'
          '<b class="p-author">$author</b>'
          '${level.isEmpty ? '' : '<span class="p-level">$level</span>'}'
          '</div>'
          '${time.isEmpty ? '' : '<div class="p-time">$time</div>'}'
          '<div class="p-body">$content</div>'
          '</div>');
    }
    return out;
  }

  // ------------------------------------------------------------------
  // 工具
  // ------------------------------------------------------------------

  static String _normSpace(String s) {
    // 去掉 comiis 字体图标私有区字符(0xE000-0xF8FF),再压缩空白。
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