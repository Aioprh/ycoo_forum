import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/board.dart';
import '../models/thread_detail.dart';
import '../models/thread_item.dart';
import 'auth_service.dart';
import 'net_client.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();
  static const String _base = 'https://www.ycoo.net/';
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
  static String detailUrl(int tid) => '$_base' 'thread-$tid-1-1.html';
  static String get boardUrl => '$_base' 'forum.php?forumlist=1&mobile=2';

  Future<List<ThreadItem>> fetchThreads(String url) async {
    final doc = parser.parse(await _get(url));
    final items = <ThreadItem>[];
    for (final li in doc.querySelectorAll('li.forumlist_li')) {
      final item = _parseThreadItem(li);
      if (item != null) items.add(item);
    }
    return items.isNotEmpty ? items : _parseGenericThreads(doc);
  }

  ThreadItem? _parseThreadItem(dom.Element li) {
    final a = li.querySelector('.mmlist_li_box h2 a');
    final title = _normSpace(a?.text ?? '');
    final href = a?.attributes['href'] ?? '';
    final tid = _firstInt(RegExp(r'thread-(\d+)'), href) ?? 0;
    if (tid <= 0 || title.isEmpty) return null;
    final board = li.querySelector('.comiis_xznalist_bk a');
    final nums = li.querySelectorAll('.comiis_xznalist_bottom span.comiis_tm').map((e) => int.tryParse(e.text.trim()) ?? 0).toList();
    return ThreadItem(
      tid: tid,
      title: title,
      author: _normSpace(li.querySelector('.forumlist_li_top .top_user')?.text ?? ''),
      avatar: _abs(li.querySelector('.forumlist_li_top .top_tximg')?.attributes['src'] ?? ''),
      fid: _firstInt(RegExp(r'forum-(\d+)'), board?.attributes['href'] ?? '') ?? 0,
      boardName: _normSpace(board?.text ?? ''),
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
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final match = RegExp(r'(?:thread-|[?&](?:tid|ptid)=)(\d+)', caseSensitive: false).firstMatch(href);
      if (match == null) continue;
      final tid = int.tryParse(match.group(1)!) ?? 0;
      final title = _normSpace(a.text);
      if (tid <= 0 || title.length < 2 || !seen.add(tid) || _navigationTitle(title)) continue;
      final parent = _threadContainer(a);
      final parentText = _normSpace(parent?.text ?? '');
      result.add(ThreadItem(
        tid: tid,
        title: title,
        author: _normSpace(parent?.querySelector('.top_user,.author,.by,.xw1')?.text ?? ''),
        avatar: _abs(parent?.querySelector('img')?.attributes['src'] ?? ''),
        fid: _firstInt(RegExp(r'(?:forum-|[?&]fid=)(\d+)'), parent?.outerHtml ?? '') ?? 0,
        boardName: _normSpace(parent?.querySelector('.forumname,.from,.comiis_xznalist_bk a')?.text ?? ''),
        level: '',
        time: _normSpace(parent?.querySelector('.f_d,.time,time,.kmtime')?.text ?? ''),
        subtitle: parentText == title ? '' : parentText.replaceFirst(title, '').trim(),
        cover: '',
        likeCount: _numberAfter(parentText, ['点赞']) ?? 0,
        replyCount: _numberAfter(parentText, ['回复', '评论']) ?? 0,
        viewCount: _numberAfter(parentText, ['浏览', '查看']) ?? 0,
      ));
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

  Future<List<ForumCategory>> fetchBoards() async {
    final doc = parser.parse(await _get(boardUrl));
    final names = doc.querySelectorAll('.comiis_bbs_show h2').map((e) => _normSpace(e.text)).where((e) => e.isNotEmpty).toList();
    final groups = doc.querySelectorAll('.comiis_forum_nbox');
    final cats = <ForumCategory>[];
    for (var i = 0; i < groups.length; i++) {
      final boards = <ForumBoard>[];
      for (final li in groups[i].querySelectorAll('li')) {
        final a = li.querySelector('a');
        final href = a?.attributes['href'] ?? '';
        final fid = _firstInt(RegExp(r'forum-(\d+)'), href) ?? 0;
        final name = _normSpace(a?.querySelector('span')?.text ?? a?.text ?? '');
        if (fid > 0 && name.isNotEmpty) {
          boards.add(ForumBoard(fid: fid, name: name, icon: _abs(a?.querySelector('img')?.attributes['src'] ?? ''), today: _normSpace(a?.querySelector('p')?.text ?? '')));
        }
      }
      if (boards.isNotEmpty) cats.add(ForumCategory(name: i < names.length ? names[i] : '其他', boards: boards));
    }
    if (cats.isEmpty) throw Exception('未解析到版块数据');
    return cats;
  }

  Future<ThreadDetail> fetchThreadDetail(int tid) async {
    final html = await _get(detailUrl(tid), query: {'mobile': '2'});
    final doc = parser.parse(html);
    final boardLink = doc.querySelector('.comiis_bankuai .bankuai_tit a, .comiis_bankuai a[href*="forum-"], a[href*="forum-"]');
    final boardName = _normSpace(boardLink?.text ?? '');
    var title = _firstMeta(doc, 'og:title') ?? _firstMeta(doc, 'title') ?? '';
    final titleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html);
    if (title.isEmpty && titleMatch != null) title = _stripTags(titleMatch.group(1)!);
    if (boardName.isNotEmpty) title = title.replaceAll(' - $boardName', '').replaceAll('-$boardName', '');
    title = title.replaceAll(' - 源论坛', '').replaceAll('- 源论坛', '').trim();

    final posts = _collectPosts(doc);
    final first = _firstPostNode(doc);
    final fid = _firstInt(RegExp(r'(?:forum-|[?&]fid=)(\d+)'), boardLink?.attributes['href'] ?? '') ?? _firstInt(RegExp(r'(?:forum-|[?&]fid=)(\d+)'), first?.outerHtml ?? '') ?? 0;
    final firstPid = _firstInt(RegExp(r'id="pid(\d+)"'), first?.outerHtml ?? '') ?? _firstInt(RegExp(r'id="post_(\d+)"'), first?.outerHtml ?? '') ?? 0;
    final myUid = AuthService.instance.uid ?? 0;
    final likeCount = _firstInt(RegExp(r'comiis_recommend_nums[^>]*>\s*(\d+)'), html) ?? doc.querySelectorAll('.comiis_recommend_list_a li').length;
    final likedByMe = myUid > 0 && doc.querySelectorAll('.comiis_recommend_list_a a[href*="uid=$myUid"]').isNotEmpty;
    final comments = posts.length > 1 ? '<div class="comments-section" data-tid="$tid" data-fid="$fid"><div class="comments-title">评论 / 回复</div>${posts.skip(1).join()}</div>' : '';
    final paid = _parsePaidState(doc);

    return ThreadDetail(
      tid: tid,
      title: title.isEmpty ? '帖子详情' : title,
      author: _normSpace(first?.querySelector('.top_user, .authi .xw1, .authi a')?.text ?? doc.querySelector('.top_user, .authi .xw1')?.text ?? ''),
      avatar: _abs(first?.querySelector('img.top_tximg, .avatar img, .avtm img')?.attributes['src'] ?? doc.querySelector('img.top_tximg, .avatar img, .avtm img')?.attributes['src'] ?? ''),
      level: _normSpace(first?.querySelector('.top_lev, .p_pop')?.text ?? doc.querySelector('.top_lev')?.text ?? ''),
      time: _normSpace(first?.querySelector('.comiis_postli_time .kmtime, .authi em, .pti .authi')?.text ?? ''),
      fid: fid,
      boardName: boardName,
      bodyHtml: posts.isEmpty ? '' : '<div class="content-section">${posts.first}</div>',
      commentsHtml: comments,
      isPaid: paid.isPaid,
      price: paid.price,
      currency: paid.currency,
      purchaseUrl: paid.purchaseUrl.isEmpty ? detailUrl(tid) : paid.purchaseUrl,
      firstPid: firstPid,
      likeCount: likeCount,
      likedByMe: likedByMe,
    );
  }

  dom.Element? _firstPostNode(dom.Document doc) => doc.querySelector('.comiis_postli, #postlist .plhin, #postlist .plc, #postlist > div[id^="post_"], div[id^="postmessage_"]');

  List<String> _collectPosts(dom.Document doc) {
    final nodes = doc.querySelectorAll('.comiis_postli');
    if (nodes.isNotEmpty) return nodes.map((e) => e.outerHtml).toList();
    return doc.querySelectorAll('#postlist > div[id^="post_"], #postlist .plhin').map((e) => e.outerHtml).toList();
  }

  _PaidState _parsePaidState(dom.Document doc) {
    final first = _firstPostNode(doc);
    final text = _normSpace(first?.text ?? '');
    final root = first ?? doc.body;
    if (root != null) {
      for (final e in root.querySelectorAll('a,button,input,form')) {
        final all = '${_normSpace(e.text)} ${e.attributes['value'] ?? ''} ${e.attributes['title'] ?? ''} ${e.attributes['onclick'] ?? ''} ${e.attributes['href'] ?? ''}';
        final lower = all.toLowerCase();
        if (!all.contains('购买主题') && !all.contains('本主题需向作者支付') && !lower.contains('buythread') && !lower.contains('action=pay')) continue;
        final price = _firstInt(RegExp(r'(?:支付|需要)\s*(\d+)\s*星币'), all);
        final href = _abs(e.attributes['href'] ?? '');
        if (href.isNotEmpty && !href.startsWith('javascript:')) return _PaidState(true, price, '星币', href);
        final action = _abs(e.attributes['action'] ?? '');
        if (action.isNotEmpty) return _PaidState(true, price, '星币', action);
        return _PaidState(true, price, '星币', '');
      }
    }
    if (text.contains('本主题需向作者支付') && text.contains('星币')) return _PaidState(true, _firstInt(RegExp(r'支付\s*(\d+)\s*星币'), text), '星币', '');
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
      final sourceDoc = parser.parse(NetClient.decode(sourceResp.bodyBytes));
      if (_isUnlocked(sourceDoc)) return const PurchaseResult(true, '主题已经购买，正在刷新正文');

      final form = _findPurchaseForm(sourceDoc);
      final href = _findPurchaseHref(sourceDoc);
      String result;
      if (form != null) {
        final fields = <String, String>{...form.fields};
        fields['tid'] = fields['tid']?.isNotEmpty == true ? fields['tid']! : '$tid';
        final formhash = fields['formhash']?.isNotEmpty == true ? fields['formhash']! : (_firstInputValue(sourceDoc, 'formhash') ?? '');
        if (formhash.isEmpty) return const PurchaseResult(false, '未取得购买令牌，请刷新帖子后重试');
        fields['formhash'] = formhash;
        final response = await client.post(Uri.parse(_abs(form.action)), headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: fields).timeout(_timeout);
        result = NetClient.decode(response.bodyBytes);
      } else if (href.isNotEmpty) {
        final response = await client.get(Uri.parse(_abs(href)), headers: headers).timeout(_timeout);
        result = NetClient.decode(response.bodyBytes);
        final resultDoc = parser.parse(result);
        final confirm = _findPurchaseForm(resultDoc);
        if (confirm != null) {
          final fields = <String, String>{...confirm.fields};
          fields['tid'] = fields['tid']?.isNotEmpty == true ? fields['tid']! : '$tid';
          final formhash = fields['formhash']?.isNotEmpty == true ? fields['formhash']! : (_firstInputValue(resultDoc, 'formhash') ?? '');
          if (formhash.isEmpty) return const PurchaseResult(false, '购买确认页缺少 formhash，请刷新帖子后重试');
          fields['formhash'] = formhash;
          final submit = await client.post(Uri.parse(_abs(confirm.action)), headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: fields).timeout(_timeout);
          result = NetClient.decode(submit.bodyBytes);
        }
      } else {
        return const PurchaseResult(false, '未找到购买入口，请刷新帖子后重试');
      }

      final resultDoc = parser.parse(result);
      if (!_looksLikePurchaseSuccess(resultDoc) && !_isUnlocked(resultDoc)) return PurchaseResult(false, _purchaseFailure(resultDoc) ?? '购买失败，请检查星币余额或论坛提示');
      return const PurchaseResult(true, '购买成功，正在刷新正文');
    } catch (e) {
      return PurchaseResult(false, '购买请求失败：${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  dom.Element? _findPurchaseForm(dom.Document doc) {
    for (final form in doc.querySelectorAll('form')) {
      final text = _normSpace(form.text).toLowerCase();
      final html = form.outerHtml.toLowerCase();
      if (text.contains('购买主题') || text.contains('支付') || html.contains('buythread') || html.contains('action=pay')) return form;
    }
    return null;
  }

  String _findPurchaseHref(dom.Document doc) {
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final text = _normSpace(a.text).toLowerCase();
      final all = '$text ${a.attributes['title'] ?? ''} $href'.toLowerCase();
      if (text.contains('购买主题') || all.contains('buythread') || all.contains('action=pay')) return href;
    }
    return '';
  }

  String? _firstInputValue(dom.Document doc, String name) {
    for (final input in doc.querySelectorAll('input')) {
      if (input.attributes['name'] == name) return input.attributes['value'];
    }
    return null;
  }

  bool _isUnlocked(dom.Document doc) {
    final text = _normSpace(doc.body?.text ?? '');
    if (text.contains('本主题需向作者支付') || text.contains('购买后查看完整内容')) return false;
    return _collectPosts(doc).any((p) => _normSpace(parser.parseFragment(p).text).length > 20);
  }

  bool _looksLikePurchaseSuccess(dom.Document doc) {
    final text = _normSpace(doc.body?.text ?? '');
    return text.contains('购买成功') || text.contains('支付成功') || text.contains('购买完成') || text.contains('交易成功');
  }

  String? _purchaseFailure(dom.Document doc) {
    final text = _normSpace(doc.body?.text ?? '');
    for (final key in ['星币不足', '余额不足', 'formhash', '无权购买', '购买失败']) {
      if (text.contains(key)) return text.length > 180 ? text.substring(0, 180) : text;
    }
    return null;
  }

  static String _normSpace(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static int? _firstInt(RegExp re, String s) {
    final m = re.firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1) ?? '');
  }

  static int? _numberAfter(String text, List<String> labels) {
    for (final label in labels) {
      final value = _firstInt(RegExp('${RegExp.escape(label)}\\s*[:：]?\\s*(\\d+)'), text);
      if (value != null) return value;
    }
    return null;
  }

  static bool _navigationTitle(String title) {
    const blocked = {'首页', '论坛', '版块', '社区', '搜索', '登录', '注册', '下一页', '上一页'};
    return blocked.contains(title.trim());
  }

  static String? _firstMeta(dom.Document doc, String name) {
    final meta = doc.querySelector('meta[property="$name"], meta[name="$name"]');
    return meta?.attributes['content']?.trim();
  }

  static String _stripTags(String html) => parser.parseFragment(html).text.trim();
}

class PurchaseResult {
  final bool success;
  final String message;
  const PurchaseResult(this.success, this.message);
}

class _PaidState {
  final bool isPaid;
  final int? price;
  final String currency;
  final String purchaseUrl;
  const _PaidState(this.isPaid, this.price, this.currency, this.purchaseUrl);
}
