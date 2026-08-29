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
    final params = <String, String>{...?query};
    params['_ycoo_ts'] = DateTime.now().millisecondsSinceEpoch.toString();
    final uri = Uri.parse(url).replace(queryParameters: params);
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
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
    for (final e in doc.querySelectorAll('a,button,input,form')) {
      final text = _normSpace(e.text);
      final value = e.attributes['value'] ?? '';
      final title = e.attributes['title'] ?? '';
      final all = '$text $value $title';
      if (!all.contains('购买主题') && !all.contains('本主题需向作者支付')) continue;
      final price = _firstInt(RegExp(r'(?:支付|需要)\s*(\d+)\s*星币'), all);
      final href = _abs(e.attributes['href'] ?? '');
      if (href.isNotEmpty) return _PaidState(true, price, '星币', href);
      final action = _abs(e.attributes['action'] ?? '');
      if (action.isNotEmpty) return _PaidState(true, price, '星币', action);
      return _PaidState(true, price, '星币', '');
    }
    final allText = _normSpace(doc.body?.text ?? '');
    if (allText.contains('本主题需向作者支付') && allText.contains('星币')) {
      return _PaidState(true, _firstInt(RegExp(r'支付\s*(\d+)\s*星币'), allText), '星币', '');
    }
    return const _PaidState(false, null, '星币', '');
  }

  /// 在原生 HTTP 层完成站点原有的购买主题流程。
  /// 不保存账号密码，只复用 WebView 登录后持久化的 Cookie。
  Future<PurchaseResult> purchaseThread(int tid) async {
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) {
      return const PurchaseResult(false, '请先登录论坛');
    }
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
      final sourceResp = await client.get(
        Uri.parse(detailUrl(tid)),
        headers: headers,
      ).timeout(_timeout);
      final source = NetClient.decode(sourceResp.bodyBytes);
      final sourceDoc = parser.parse(source);
      if (_isUnlocked(sourceDoc)) {
        return const PurchaseResult(true, '主题已经购买，无需重复购买');
      }

      final buy = _findPurchaseForm(sourceDoc, tid);
      if (buy == null) {
        return const PurchaseResult(false, '未找到原站购买表单，可能是站点模板或购买插件已变更');
      }

      final form = <String, String>{...buy.fields};
      form.putIfAbsent('tid', () => '$tid');
      if (form['formhash'] == null || form['formhash']!.isEmpty) {
        final formhash = NetClient.first(
          RegExp(r'''name=["']formhash["'][^>]*value=["']([^"']+)["']''', caseSensitive: false),
          source,
        );
        if (formhash != null && formhash.isNotEmpty) form['formhash'] = formhash;
      }
      final formhash = form['formhash'];
      if (formhash == null || formhash.isEmpty) {
        return const PurchaseResult(false, '未取得购买令牌(formhash)，请重新打开帖子后再试');
      }

      final submit = await client.post(
        Uri.parse(_abs(buy.action)),
        headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded'},
        body: form,
      ).timeout(_timeout);
      final resultHtml = NetClient.decode(submit.bodyBytes);
      final resultDoc = parser.parse(resultHtml);
      final resultText = _normSpace(resultDoc.body?.text ?? resultHtml);

      if (_looksLikePurchaseSuccess(resultText, resultDoc)) {
        // 购买完成后强制重新请求主题，确保拿到服务器解锁后的正文，而不是评论缓存。
        final refreshed = await client.get(
          Uri.parse('${detailUrl(tid)}?refresh=${DateTime.now().millisecondsSinceEpoch}'),
          headers: headers,
        ).timeout(_timeout);
        final refreshedDoc = parser.parse(NetClient.decode(refreshed.bodyBytes));
        if (_isUnlocked(refreshedDoc) && _collectPosts(refreshedDoc).isNotEmpty) {
          return const PurchaseResult(true, '购买成功，正文已解锁');
        }
        return const PurchaseResult(false, '购买请求已返回成功，但帖子正文仍未解锁，请重新进入帖子确认购买状态');
      }

      final failure = _purchaseFailure(resultText);
      return PurchaseResult(false, failure ?? '购买失败，请检查星币余额或论坛提示');
    } catch (_) {
      return const PurchaseResult(false, '购买请求失败，请稍后重试');
    }
  }

  _PurchaseForm? _findPurchaseForm(dom.Document doc, int tid) {
    for (final form in doc.querySelectorAll('form')) {
      final text = _normSpace(form.text);
      final action = form.attributes['action'] ?? '';
      final blob = '${form.innerHtml} $action $text';
      final looksPaid = blob.contains('购买主题') || blob.contains('buythread') ||
          blob.contains('buytopic') || blob.contains('星币') || blob.contains('threadid');
      if (!looksPaid) continue;
      final fields = <String, String>{};
      for (final input in form.querySelectorAll('input')) {
        final name = input.attributes['name'];
        if (name == null || name.isEmpty) continue;
        fields[name] = input.attributes['value'] ?? '';
      }
      final actionUrl = _abs(action.isEmpty ? detailUrl(tid) : action);
      return _PurchaseForm(actionUrl, fields);
    }
    // 有些模板只有购买链接，没有 form。先定位链接；其目标通常是原站确认购买页，
    // 仍然由上层解析确认页的表单，不直接在这里扣费。
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      final text = _normSpace(a.text);
      if (text.contains('购买主题') || href.contains('buythread') || href.contains('buytopic')) {
        return _PurchaseForm(_abs(href), <String, String>{});
      }
    }
    return null;
  }

  bool _isUnlocked(dom.Document doc) {
    final text = _normSpace(doc.body?.text ?? '');
    final paidNotice = text.contains('本主题需向作者支付') || text.contains('购买主题') && text.contains('星币');
    final posts = _collectPosts(doc);
    if (posts.isEmpty) return false;
    // 购买成功后服务端通常不再输出购买提示，同时正文帖仍存在。
    return !paidNotice;
  }

  bool _looksLikePurchaseSuccess(String text, dom.Document doc) {
    if (text.contains('购买成功') || text.contains('购买成功！') || text.contains('操作成功')) return true;
    if (text.contains('已经购买') || text.contains('已购买')) return true;
    if (doc.querySelector('.comiis_message_table') != null && !text.contains('本主题需向作者支付')) return true;
    return false;
  }

  String? _purchaseFailure(String text) {
    const keys = <String>['星币不足', '余额不足', '积分不足', '没有足够', '无权购买', '购买失败', '请先登录', 'formhash', '验证失败'];
    for (final key in keys) {
      if (text.contains(key)) return key;
    }
    return null;
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

class _PurchaseForm {
  final String action;
  final Map<String, String> fields;
  const _PurchaseForm(this.action, this.fields);
}

class PurchaseResult {
  final bool success;
  final String message;
  const PurchaseResult(this.success, this.message);
}