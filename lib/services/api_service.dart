import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/board.dart';
import '../models/thread_detail.dart';
import '../models/thread_item.dart';
import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 源论坛移动端数据抓取与解析。
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static String get _base => SiteConfig.base;
  static const Duration _timeout = Duration(seconds: 20);

  static String _abs(String u) {
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return _base + u.substring(1);
    return _base + u.replaceFirst(RegExp(r'^\./'), '');
  }

  Future<String> _get(String url, {Map<String, String>? query}) async {
    final client = await NetClient.instance.client;
    final parsed = Uri.parse(url);
    final params = <String, String>{
      ...parsed.queryParameters,
      ...?query,
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    final uri = parsed.replace(queryParameters: params);
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
    };
    final cookie = AuthService.instance.authCookie;
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    final resp = await NetClient.retry(() => client.get(uri, headers: headers).timeout(_timeout));
    if (resp.statusCode != 200) throw Exception('请求失败 HTTP ${resp.statusCode}');
    return NetClient.decode(resp.bodyBytes);
  }

  static String guideUrl(String view) => '$_base' 'forum.php?mod=guide&view=$view&mobile=2';
  static String forumUrl(int fid, int page) => '$_base' 'forum.php?mod=forumdisplay&fid=$fid&mobile=2&page=$page';

  Future<List<ThreadItem>> fetchThreads(String url) async {
    final html = await _get(url);
    final doc = parser.parse(html);
    final items = <ThreadItem>[];
    for (final li in doc.querySelectorAll('li.forumlist_li')) {
      final item = _parseThreadItem(li);
      if (item != null) items.add(item);
    }
    if (items.isNotEmpty) return items;
    return _parseGenericThreads(doc);
  }

  ThreadItem? _parseThreadItem(dom.Element li) {
    final titleA = li.querySelector('.mmlist_li_box h2 a');
    final title = _normSpace(titleA?.text ?? '');
    final href = titleA?.attributes['href'] ?? '';
    final tid = _firstInt(RegExp(r'thread-(\d+)'), href) ?? 0;
    if (tid == 0 || title.isEmpty) return null;
    final boardA = li.querySelector('.comiis_xznalist_bk a');
    final boardHref = boardA?.attributes['href'] ?? '';
    final nums = li.querySelectorAll('.comiis_xznalist_bottom span.comiis_tm').map((e) => int.tryParse(e.text.trim()) ?? 0).toList();
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

  List<ThreadItem> _parseGenericThreads(dom.Document doc) {
    final result = <ThreadItem>[];
    final seen = <int>{};
    final links = doc.querySelectorAll('a[href]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';
      final match = RegExp(r'(?:thread-|[?&](?:tid|ptid)=)(\d+)', caseSensitive: false).firstMatch(href);
      if (match == null) continue;
      final tid = int.tryParse(match.group(1)!) ?? 0;
      if (tid <= 0 || seen.contains(tid)) continue;
      var title = _normSpace(a.text);
      final root = _threadContainer(a);
      if (title.length < 2 || _navigationTitle(title)) title = _normSpace(root?.querySelector('h1, h2, h3, .title, .subject, .mmlist_li_box h2 a')?.text ?? '');
      if (title.length < 2 || _navigationTitle(title)) continue;
      final rootText = _normSpace(root?.text ?? '');
      final fid = _firstInt(RegExp(r'(?:forum-|[?&]fid=)(\d+)'), root?.outerHtml ?? '') ?? 0;
      final author = _normSpace(root?.querySelector('.top_user, .author, .by, .xw1')?.text ?? '');
      final time = _normSpace(root?.querySelector('.f_d, .time, time, .kmtime')?.text ?? '');
      final board = _normSpace(root?.querySelector('.comiis_xznalist_bk a, .forumname, .from')?.text ?? '');
      final subtitle = rootText.isEmpty || rootText == title ? '' : rootText.replaceFirst(title, '').trim();
      seen.add(tid);
      result.add(ThreadItem(tid: tid, title: title, author: author, avatar: _abs(root?.querySelector('img')?.attributes['src'] ?? ''), fid: fid, boardName: board, level: _normSpace(root?.querySelector('.top_lev, .level')?.text ?? ''), time: time, subtitle: subtitle.length > 180 ? subtitle.substring(0, 180) : subtitle, cover: _abs(root?.querySelector('img')?.attributes['src'] ?? ''), likeCount: _numberAfter(rootText, ['点赞']) ?? 0, replyCount: _numberAfter(rootText, ['回复', '评论']) ?? 0, viewCount: _numberAfter(rootText, ['浏览', '查看']) ?? 0));
      if (result.length >= 50) break;
    }
    return result;
  }

  static dom.Element? _threadContainer(dom.Element e) {
    dom.Element? p = e.parent;
    for (var i = 0; i < 6 && p != null; i++, p = p.parent) {
      final tag = p.localName ?? '';
      if (tag == 'li' || tag == 'article' || tag == 'section') return p;
      if (tag == 'div') {
        final cls = p.classes.join(' ');
        if (cls.contains('forumlist') || cls.contains('list') || cls.contains('thread') || cls.contains('post')) return p;
      }
    }
    return e.parent;
  }

  static String get boardUrl => '$_base' 'forum.php?forumlist=1&mobile=2';

  Future<List<ForumCategory>> fetchBoards() async {
    final html = await _get(boardUrl);
    final doc = parser.parse(html);
    final names = doc.querySelectorAll('.comiis_bbs_show h2').map((e) => _normSpace(e.text)).where((e) => e.isNotEmpty).toList();
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
        final boardName = _normSpace(a?.querySelector('span')?.text ?? a?.text ?? '');
        if (boardName.isEmpty) continue;
        boards.add(ForumBoard(fid: fid, name: boardName, icon: _abs(a?.querySelector('img')?.attributes['src'] ?? ''), today: _normSpace(a?.querySelector('p')?.text ?? '')));
      }
      if (boards.isNotEmpty) cats.add(ForumCategory(name: name, boards: boards));
    }
    if (cats.isEmpty) throw Exception('未解析到版块数据');
    return cats;
  }

  static String detailUrl(int tid) => '$_base' 'thread-$tid-1-1.html';

  static String commentListUrl(int tid, int page, {int? authorId}) {
    // “只看楼主” 时原站的过滤链接是 viewthread 查询形式, 带 authorid。
    if (authorId != null && authorId > 0) {
      return '$_base' 'forum.php?mod=viewthread&tid=$tid&page=$page&authorid=$authorId';
    }
    return '$_base' 'thread-$tid-$page-1.html';
  }

  Future<ThreadDetail> fetchThreadDetail(int tid, {int page = 1, int? authorId}) async {
    final html = await _get(commentListUrl(tid, page, authorId: authorId), query: {'mobile': '2'});
    final doc = parser.parse(html);
    final boardLink = doc.querySelector('.comiis_bankuai .bankuai_tit a, .comiis_bankuai a[href*="forum-"], a[href*="forum-"]');
    final boardName = _normSpace(boardLink?.text ?? '');
    var title = _firstMeta(doc, 'og:title') ?? _firstMeta(doc, 'title') ?? '';
    final titleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html);
    if (title.isEmpty && titleMatch != null) title = _stripTags(titleMatch.group(1)!);
    if (boardName.isNotEmpty) title = title.replaceAll(' - $boardName', '').replaceAll('-$boardName', '');
    title = title.replaceAll(' - 源论坛', '').replaceAll('- 源论坛', '').trim();

    final paid = _parsePaidState(doc);
    final posts = _collectPosts(doc);
    // 第 1 页 posts[0] 是楼主正文; 翻页(>1)的页面里没有楼主, 全部是回帖, 不能再次 skip。
    final hasAuthor = page <= 1;
    final body = posts.isEmpty || page > 1 ? '' : '<div class="content-section">${posts.first}</div>';
    final commentFloors = posts.isEmpty
        ? const <String>[]
        : (hasAuthor ? posts.skip(1) : posts).toList();
    final comments = commentFloors.isEmpty
        ? ''
        : '<div class="comments-section"><div class="comments-title">评论 / 回复</div>${commentFloors.join()}</div>';
    // 解析评论分页信息
    final pageInfo = _parseCommentPage(doc, page);
    final firstPost = _firstPostNode(doc);
    final myUid = AuthService.instance.uid ?? 0;
    final firstPid = _firstInt(RegExp(r'id="pid(\d+)"'), html) ?? 0;
    var likeCount = _firstInt(RegExp(r'class="comiis_recommend_nums[^"]*">\s*(\d+)'), html) ?? 0;
    if (likeCount <= 0) likeCount = doc.querySelectorAll('.comiis_recommend_list_a li').length;
    final likedByMe = myUid > 0 && doc.querySelectorAll('.comiis_recommend_list_a a[href*="uid=$myUid"]').isNotEmpty;
    return ThreadDetail(
      tid: tid,
      title: title.isEmpty ? '帖子详情' : title,
      author: _normSpace(firstPost?.querySelector('.top_user, .authi .xw1, .authi a')?.text ?? doc.querySelector('.top_user, .authi .xw1')?.text ?? ''),
      avatar: _abs(firstPost?.querySelector('img.top_tximg, .avatar img, .avtm img')?.attributes['src'] ?? doc.querySelector('img.top_tximg, .avatar img, .avtm img')?.attributes['src'] ?? ''),
      level: _normSpace(firstPost?.querySelector('.top_lev, .p_pop')?.text ?? doc.querySelector('.top_lev')?.text ?? ''),
      time: _normSpace(firstPost?.querySelector('.comiis_postli_time .kmtime, .authi em, .pti .authi')?.text ?? ''),
      fid: _firstInt(RegExp(r'(?:forum-|[?&]fid=)(\d+)'), boardLink?.attributes['href'] ?? '') ?? _firstInt(RegExp(r'(?:forum-|[?&]fid=)(\d+)'), firstPost?.outerHtml ?? '') ?? 0,
      boardName: boardName,
      bodyHtml: body,
      commentsHtml: comments,
      commentPage: pageInfo.$1,
      commentTotalPages: pageInfo.$2,
      authorUid: _parseAuthorUid(html),
      isPaid: paid.isPaid,
      price: paid.price,
      currency: paid.currency,
      purchaseUrl: paid.purchaseUrl.isEmpty ? detailUrl(tid) : paid.purchaseUrl,
      firstPid: firstPid,
      likeCount: likeCount,
      likedByMe: likedByMe,
    );
  }

  dom.Element? _firstPostNode(dom.Document doc) {
    const selectors = '.comiis_postli, #postlist .plhin, #postlist .plc, #postlist > div[id^="post_"], div[id^="postmessage_"]';
    return doc.querySelector(selectors);
  }

  _PaidState _parsePaidState(dom.Document doc) {
    final firstPost = _firstPostNode(doc);
    final firstText = _normSpace(firstPost?.text ?? '');
    final root = firstPost ?? doc.body;
    if (root != null) {
      for (final e in root.querySelectorAll('a,button,input,form')) {
        final all = '${_normSpace(e.text)} ${e.attributes['value'] ?? ''} ${e.attributes['title'] ?? ''} ${e.attributes['onclick'] ?? ''} ${e.attributes['href'] ?? ''}';
        if (!all.contains('购买主题') && !all.contains('本主题需向作者支付') && !all.toLowerCase().contains('action=pay') && !all.toLowerCase().contains('buythread')) continue;
        final price = _firstInt(RegExp(r'(?:支付|需要)\s*(\d+)\s*星币'), all);
        final href = _abs(e.attributes['href'] ?? '');
        if (href.isNotEmpty && !href.startsWith('javascript:')) return _PaidState(true, price, '星币', href);
        final onclick = e.attributes['onclick'] ?? '';
        final jsUrl = _extractUrlFromJavascript(onclick);
        if (jsUrl.isNotEmpty) return _PaidState(true, price, '星币', jsUrl);
        final action = _abs(e.attributes['action'] ?? '');
        if (action.isNotEmpty) return _PaidState(true, price, '星币', action);
        return _PaidState(true, price, '星币', '');
      }
    }
    if (firstText.contains('本主题需向作者支付') && firstText.contains('星币')) {
      return _PaidState(true, _firstInt(RegExp(r'支付\s*(\d+)\s*星币'), firstText), '星币', '');
    }
    return const _PaidState(false, null, '星币', '');
  }

  Future<PurchaseResult> purchaseThread(int tid) async {
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return const PurchaseResult(false, '请先登录论坛');
    final client = await NetClient.instance.client;
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': detailUrl(tid),
      'Cookie': cookie,
    };
    try {
      final sourceResp = await client.get(Uri.parse('${detailUrl(tid)}?mobile=2&_ycoo_buy=${DateTime.now().millisecondsSinceEpoch}'), headers: headers).timeout(_timeout);
      if (sourceResp.statusCode != 200) return PurchaseResult(false, '读取购买页面失败 HTTP ${sourceResp.statusCode}');
      final source = NetClient.decode(sourceResp.bodyBytes);
      final sourceDoc = parser.parse(source);
      if (_isUnlocked(sourceDoc)) return const PurchaseResult(true, '主题已经购买，正在刷新正文');
      final target = await _resolvePurchaseTarget(client, sourceDoc, tid, headers);
      if (target == null) return const PurchaseResult(false, '未找到原站购买入口，请刷新帖子后重试');
      dom.Document resultDoc;
      String resultHtml;
      if (target.form != null) {
        final form = <String, String>{...target.form!.fields};
        form['tid'] = form['tid']?.isNotEmpty == true ? form['tid']! : '$tid';
        form['formhash'] = form['formhash']?.isNotEmpty == true ? form['formhash']! : (_firstInputValue(sourceDoc, 'formhash') ?? '');
        if (form['formhash']!.isEmpty) return const PurchaseResult(false, '未取得购买令牌，请刷新帖子后重试');
        final submit = await client.post(Uri.parse(target.form!.action), headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: form).timeout(_timeout);
        resultHtml = NetClient.decode(submit.bodyBytes);
        resultDoc = parser.parse(resultHtml);
      } else {
        final response = await client.get(Uri.parse(target.url), headers: headers).timeout(_timeout);
        resultHtml = NetClient.decode(response.bodyBytes);
        resultDoc = parser.parse(resultHtml);
        final confirm = _firstPurchaseForm(resultDoc, tid);
        if (confirm != null) {
          final form = <String, String>{...confirm.fields};
          form['tid'] = form['tid']?.isNotEmpty == true ? form['tid']! : '$tid';
          form['formhash'] = form['formhash']?.isNotEmpty == true ? form['formhash']! : (_firstInputValue(resultDoc, 'formhash') ?? '');
          if (form['formhash']!.isEmpty) return const PurchaseResult(false, '购买确认页缺少 formhash，请刷新帖子后重试');
          final submit = await client.post(Uri.parse(confirm.action), headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: form).timeout(_timeout);
          resultHtml = NetClient.decode(submit.bodyBytes);
          resultDoc = parser.parse(resultHtml);
        }
      }
      final resultText = _normSpace(resultDoc.body?.text ?? resultHtml);
      if (!_looksLikePurchaseSuccess(resultText, resultDoc) && !_isUnlocked(resultDoc)) return PurchaseResult(false, _purchaseFailure(resultText) ?? '购买失败，请检查星币余额或论坛提示');
      final refreshed = await client.get(Uri.parse('${detailUrl(tid)}?mobile=2&_ycoo_refresh=${DateTime.now().millisecondsSinceEpoch}'), headers: headers).timeout(_timeout);
      final refreshedDoc = parser.parse(NetClient.decode(refreshed.bodyBytes));
      if (_isUnlocked(refreshedDoc) && _collectPosts(refreshedDoc).isNotEmpty) return const PurchaseResult(true, '购买成功，正文已解锁');
      return const PurchaseResult(false, '购买已返回成功，但正文刷新仍未解锁，请重新进入帖子确认状态');
    } catch (e) {
      return PurchaseResult(false, '购买请求失败：${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<_PurchaseTarget?> _resolvePurchaseTarget(dynamic client, dom.Document doc, int tid, Map<String, String> headers) async {
    final form = _firstPurchaseForm(doc, tid);
    if (form != null) return _PurchaseTarget.form(form);
    for (final e in doc.querySelectorAll('a[href],a[onclick],button[onclick],input[onclick]')) {
      final href = e.attributes['href'] ?? '';
      final onclick = e.attributes['onclick'] ?? '';
      final text = _normSpace(e.text);
      final blob = '$text $href $onclick'.toLowerCase();
      if (!text.contains('购买主题') && !blob.contains('action=pay') && !blob.contains('buythread') && !blob.contains('buytopic')) continue;
      if (href.isNotEmpty && !href.startsWith('javascript:')) return _PurchaseTarget.url(_abs(href));
      final jsUrl = _extractUrlFromJavascript(onclick);
      if (jsUrl.isNotEmpty) return _PurchaseTarget.url(jsUrl);
    }
    return null;
  }

  _PurchaseForm? _firstPurchaseForm(dom.Document doc, int tid) {
    for (final form in doc.querySelectorAll('form')) {
      final text = _normSpace(form.text);
      final action = form.attributes['action'] ?? '';
      final blob = '${form.innerHtml} $action $text'.toLowerCase();
      // 不能只凭 formhash 判断，否则会误把回帖表单当成购买表单。
      final looksPaid = blob.contains('购买主题') || blob.contains('buythread') || blob.contains('buytopic') || blob.contains('action=pay') || blob.contains('付费主题');
      if (!looksPaid) continue;
      final fields = <String, String>{};
      for (final input in form.querySelectorAll('input')) {
        final name = input.attributes['name'];
        if (name == null || name.isEmpty) continue;
        fields[name] = input.attributes['value'] ?? '';
      }
      return _PurchaseForm(_abs(action.isEmpty ? detailUrl(tid) : action), fields);
    }
    return null;
  }

  static String _extractUrlFromJavascript(String js) {
    if (js.isEmpty) return '';
    final patterns = <RegExp>[
      RegExp(r'''['"]((?:forum\.php|thread-[^'"]+)[^'"]*)['"]''', caseSensitive: false),
      RegExp(r'''['"](https?://[^'"]+)['"]''', caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(js);
      if (m != null) return _abs(m.group(1)!);
    }
    return '';
  }

  bool _isUnlocked(dom.Document doc) {
    final firstPost = _firstPostNode(doc);
    final firstText = _normSpace(firstPost?.text ?? '');
    if (firstPost == null) return false;
    final paidNotice = firstText.contains('本主题需向作者支付') || (firstText.contains('购买主题') && firstText.contains('星币'));
    final posts = _collectPosts(doc);
    return posts.isNotEmpty && !paidNotice;
  }

  bool _looksLikePurchaseSuccess(String text, dom.Document doc) {
    if (text.contains('购买成功') || text.contains('购买成功！') || text.contains('操作成功') || text.contains('已经购买') || text.contains('已购买')) return true;
    final message = doc.querySelector('.comiis_message_table, .showmessage, .alert_info');
    return message != null && !text.contains('购买失败') && !text.contains('星币不足');
  }

  String? _purchaseFailure(String text) {
    const keys = <String>['星币不足','余额不足','积分不足','没有足够','无权购买','购买失败','请先登录','formhash','验证失败','非法请求'];
    for (final key in keys) if (text.contains(key)) return key;
    return null;
  }

  /// 从分页控件 `.pg` 解析当前评论页与总页数。
  ///
  /// 结构: `<div class="pg"><strong>1</strong><a href="thread-190-2-1.html">2</a>...
  /// <a href="thread-190-10-1.html" class="last">.. 10</a></div>`。
  /// 当前页取自 `<strong>` 或传入的 page; 总页数优先用 `a.last` 的数字, 否则取页码最大值。
  static (int, int) _parseCommentPage(dom.Document doc, int page) {
    int current = page <= 0 ? 1 : page;
    final pg = doc.querySelector('.pg');
    if (pg != null) {
      final strong = pg.querySelector('strong');
      final strongNum = int.tryParse(strong?.text.trim() ?? '');
      if (strongNum != null && strongNum > 0) current = strongNum;
      final last = pg.querySelector('a.last');
      final lastNum = int.tryParse(last?.text.replaceAll(RegExp(r'[^0-9]'), '') ?? '');
      int maxPage = lastNum ?? 0;
      for (final a in pg.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        final m = RegExp(r'thread-\d+-(\d+)-1\.html').firstMatch(href);
        final n = int.tryParse(m?.group(1) ?? '');
        if (n != null && n > maxPage) maxPage = n;
      }
      if (maxPage < current) maxPage = current;
      return (current, maxPage);
    }
    return (current, current);
  }

  /// 从详情页脚本 `var replyreload, ... authorid = '1', ...` 提取楼主 uid。
  static int _parseAuthorUid(String html) {
    final m = RegExp(r"authorid\s*=\s*'(\d+)'").firstMatch(html);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  static List<String> _collectPosts(dom.Document doc) {
    final out = <String>[];
    final postNodes = doc.querySelectorAll('.comiis_postli, #postlist .plhin, #postlist .plc, #postlist > div[id^="post_"], div[id^="postmessage_"]');
    for (final post in postNodes) {
      dom.Element? content = post.querySelector('.comiis_aimg_show, .comiis_messages, .comiis_message_table');
      content ??= post.querySelector('.t_f, .pcb, .comiis_postcontent, .comiis_message, .message, .postmessage, [id^="postmessage_"]');
      if (content == null && post.localName == 'div' && (post.id.startsWith('postmessage_') || post.id.startsWith('post_'))) content = post;
      if (content == null) continue;
      final html = content.innerHtml.trim();
      if (html.isEmpty) continue;
      // 提取真实楼层 pid(取自容器 id="post_<pid>"/"postmessage_<pid>"),写入卡片供楼中楼回复使用。
      final pid = _postPid(post);
      final pidAttr = pid > 0 ? ' data-pid="$pid"' : '';
      final author = _normSpace(post.querySelector('.top_user, .authi .xw1, .authi a')?.text ?? '');
      final level = _normSpace(post.querySelector('.top_lev, .p_pop')?.text ?? '');
      final floor = _normSpace(post.querySelector('.f_d.y, .pi .authi em, .pls .authi em')?.text ?? '').replaceAll(RegExp(r'[^0-9A-Za-z一二三四五六七八九十楼主]'), '');
      final time = _normSpace(post.querySelector('.kmtime, .comiis_tm, .authi em')?.text ?? '');
      final displayFloor = floor.isEmpty ? (out.isEmpty ? '楼主' : '${out.length + 1}楼') : floor;
      out.add('<div class="post-card"$pidAttr><div class="post-hd"><span class="p-floor">$displayFloor</span>${author.isEmpty ? '' : '<b class="p-author">$author</b>'}${level.isEmpty ? '' : '<span class="p-level">$level</span>'}</div>${time.isEmpty ? '' : '<div class="p-time">$time</div>'}<div class="p-body">${_cleanPostHtml(html)}</div></div>');
    }
    if (out.isNotEmpty) return out;
    for (final selector in ['.comiis_aimg_show', '.comiis_message_table', '.t_f', '.pcb', '.postmessage', '[id^="postmessage_"]']) {
      for (final t in doc.querySelectorAll(selector)) {
        final html = t.innerHtml.trim();
        if (html.isNotEmpty) out.add('<div class="post-card"><div class="p-body">${_cleanPostHtml(html)}</div></div>');
      }
      if (out.isNotEmpty) return out;
    }
    return out;
  }

  static String _cleanPostHtml(String html) {
    var value = html;
    value = value.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');
    return value.trim();
  }

  static String? _firstInputValue(dom.Document doc, String name) => doc.querySelector('input[name="$name"]')?.attributes['value']?.trim();
  static String _normSpace(String s) => s.replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD□]'), '').replaceAll(RegExp(r'[ \t\u00A0\u3000]+'), ' ').replaceAll(RegExp(r'\n{2,}'), '\n').trim();
  static int? _firstInt(RegExp re, String s) { final m = re.firstMatch(s); return m == null ? null : int.tryParse(m.group(1)!); }
  /// 从帖子容器提取真实 pid。容器 id 形如 `post_2634962` / `postmessage_2634962`。
  static int _postPid(dom.Element post) {
    final id = post.id ?? '';
    final idMatch = RegExp(r'(?:post_|postmessage_)(\d+)').firstMatch(id);
    if (idMatch != null) return int.tryParse(idMatch.group(1)!) ?? 0;
    final attrPid = int.tryParse(post.attributes['data-pid'] ?? '');
    if (attrPid != null && attrPid > 0) return attrPid;
    final any = RegExp(r'(?:post_|postmessage_|pid)(\d+)', caseSensitive: false).firstMatch(post.outerHtml);
    return any == null ? 0 : int.tryParse(any.group(1)!) ?? 0;
  }
  static int? _numberAfter(String text, List<String> keys) { for (final key in keys) { final match = RegExp('$key\\s*[:：]?\\s*(\\d+)').firstMatch(text); if (match != null) return int.tryParse(match.group(1)!); } return null; }
  static String? _firstMeta(dom.Document doc, String property) { for (final e in doc.querySelectorAll('meta')) { final key = e.attributes['property'] ?? e.attributes['name'] ?? ''; if (key == property) return e.attributes['content']; } return null; }
  static String _stripTags(String value) => parser.parseFragment(value).text ?? '';
  static bool _navigationTitle(String text) => const {'下一页','上一页','首页','尾页','更多','回复','查看','详情','登录','注册','搜索'}.contains(text);
}

class _PaidState {
  final bool isPaid;
  final int? price;
  final String currency;
  final String purchaseUrl;
  const _PaidState(this.isPaid, this.price, this.currency, this.purchaseUrl);
}

class _PurchaseForm {
  final String action;
  final Map<String, String> fields;
  const _PurchaseForm(this.action, this.fields);
}

class _PurchaseTarget {
  final _PurchaseForm? form;
  final String url;
  const _PurchaseTarget._(this.form, this.url);
  factory _PurchaseTarget.form(_PurchaseForm form) => _PurchaseTarget._(form, '');
  factory _PurchaseTarget.url(String url) => _PurchaseTarget._(null, url);
}

class PurchaseResult {
  final bool success;
  final String message;
  const PurchaseResult(this.success, this.message);
}