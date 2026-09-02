import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

class NativeNotice {
  final String title;
  final String subtitle;
  final String href;
  final String body;
  final int uid; // 关联作者 uid（可能为 0）
  final int tid; // 关联帖子 tid（可能为 0）
  const NativeNotice({required this.title, required this.subtitle, this.href = '', this.body = '', this.uid = 0, this.tid = 0});
}

class NativeMessage {
  final String title;
  final String subtitle;
  final String sender;
  final String time;
  final int uid;
  const NativeMessage({required this.title, required this.subtitle, this.sender = '', this.time = '', this.uid = 0});
}

class NativeFriend {
  final String name;
  final String subtitle;
  const NativeFriend({required this.name, required this.subtitle});
}

class NativeCreditSummary {
  final String balance;
  final List<String> records;
  const NativeCreditSummary({required this.balance, required this.records});
}

class MemberServiceV2 {
  MemberServiceV2._();
  static final instance = MemberServiceV2._();
  static String get _base => SiteConfig.base;

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final uri = Uri.parse('$_base$path').replace(queryParameters: {
      ...Uri.parse('$_base$path').queryParameters,
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final response = await NetClient.retry(() => client.get(uri, headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
    final html = NetClient.decode(response.bodyBytes);
    if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
    return html;
  }

  Future<String> _first(List<String> paths) async {
    Object? last;
    for (final path in paths) {
      try {
        final html = await _get(path);
        if (html.trim().isNotEmpty) return html;
      } catch (e) { last = e; }
    }
    throw Exception(last?.toString().replaceFirst('Exception: ', '') ?? '请求失败');
  }

  static dynamic _doc(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    return doc;
  }

  Future<List<ThreadItem>> fetchThreads(String path) async {
    final doc = _doc(await _first([path, _withoutMobile(path)]));
    final result = <ThreadItem>[];
    final seen = <int>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'(?:thread-|[?&]tid=)(\d+)', caseSensitive: false).firstMatch(href);
      if (m == null) continue;
      final tid = int.tryParse(m.group(1)!) ?? 0;
      final title = _cleanNodeText(a);
      if (tid <= 0 || title.length < 2 || !seen.add(tid) || _looksLikeNavigation(title)) continue;
      final parent = _cleanNodeText(a.parent);
      // Comiis 个人主页主题列表: 回复/浏览数藏在 li.forumlist_li 容器内的
      // span.comiis_tm 数字集合末尾两个；板名在祖先的 forum-N 链接里。
      final counts = _findThreadCounts(a);
      var boardName = '';
      dom.Element? cur = a.parent;
      while (cur != null) {
        final forumLink = cur.querySelector('a[href*="forum-"]');
        if (forumLink != null && _cleanNodeText(forumLink).isNotEmpty) {
          boardName = _cleanNodeText(forumLink);
          break;
        }
        cur = cur.parent;
      }
      result.add(ThreadItem(
        tid: tid, title: title, author: '', avatar: '',
        fid: int.tryParse(RegExp(r'(?:forum-|[?&]fid=)(\d+)').firstMatch(a.parent?.outerHtml ?? '')?.group(1) ?? '') ?? 0,
        boardName: boardName, level: '', time: '',
        subtitle: parent == title ? '' : parent.replaceFirst(title, '').trim(),
        cover: '', likeCount: counts.$1, replyCount: counts.$2, viewCount: counts.$3,
      ));
    }
    return result;
  }

  /// 在 a 的祖先容器里找 comiis_tm 数值 spans，返回 (点赞, 回复, 浏览)。
  /// 找不到时 fallback: 用正则扫祖先文本里的"回复 N / 浏览 N"。
  (int, int, int) _findThreadCounts(dom.Element a) {
    dom.Element? cur = a;
    while (cur != null) {
      final spans = cur.querySelectorAll('span[class*="comiis_tm"]');
      final nums = <int>[];
      for (final s in spans) {
        final v = int.tryParse(_cleanNodeText(s));
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
      final t = _cleanNodeText(cur);
      if (t.length > text.length) text = t;
      cur = cur.parent;
    }
    if (text.isEmpty) return (0, 0, 0);
    int? grab(List<String> keys) {
      for (final k in keys) {
        final mm = RegExp('$k\\s*[:：]?\\s*(\\d+)').firstMatch(text);
        if (mm != null) return int.tryParse(mm.group(1)!);
      }
      return null;
    }
    return (0, grab(const ['回复', '评论', '回帖']) ?? 0, grab(const ['浏览', '查看', '人气']) ?? 0);
  }

  Future<List<NativeNotice>> fetchNotices({String view = 'all'}) async {
    final path = 'home.php?mod=space&do=notice&view=$view';
    final doc = _doc(await _first(["$path&mobile=2", path]));
    final result = <NativeNotice>[];
    final seen = <String>{};

    // Comiis 移动模板：.comiis_notices_box > .comiis_notice_list ul li.b_b
    for (final li in doc.querySelectorAll('.comiis_notice_list li,li.b_b.bg_f.cl,.ntc_list li,.comiis_nts li,.pmlist li,li')) {
      final bodyNode = li.querySelector('.ntc_body') ?? li.querySelector('dd,dt,.nts_body');
      final body = _cleanNodeText(bodyNode ?? li);
      if (body.length < 2 || body.length > 800 || !seen.add(body)) continue;
      if (_looksLikeNavigation(body)) continue;

      final time = _cleanNodeText(li.querySelector('h2 em,#pt h2 em,h2,.xg1,.xg2,[class*="time"],[class*="date"]'));
      final hasKeyword = RegExp(r'(回复|评论|提到|通知|系统|赞了|收藏|提醒|关注|好友|主题|购买|充值|任务|注册|订单|经验|积分|星币|升级|留言|打招呼)').hasMatch(body);
      if (view != 'all' && !hasKeyword) continue;

      int tid = 0;
      for (final a in li.querySelectorAll('a[href]')) {
        final h = a.attributes['href'] ?? '';
        final m = RegExp(r'(?:thread-|[?&]tid=)(\d+)', caseSensitive: false).firstMatch(h);
        if (m != null) { final v = int.tryParse(m.group(1)!); if (v != null && v > 0) { tid = v; break; } }
      }
      int uid = 0;
      for (final a in li.querySelectorAll('a[href*="mod=space&uid="],a[href*="mod=space%26uid="],a[href*="?uid="],a[href*="&uid="]')) {
        final m = RegExp(r'(?:[?&]|%3F|%26)uid=(\d+)', caseSensitive: false).firstMatch(a.attributes['href'] ?? '');
        final v = int.tryParse(m?.group(1) ?? '');
        if (v != null && v > 0) { uid = v; break; }
      }

      final title = body.length > 60 ? body.substring(0, 60) : body;
      final subtitle = time.isNotEmpty && !body.contains(time) ? '$time $body' : body;
      final href = tid > 0 ? 'thread-$tid-1-1.html' : '';
      result.add(NativeNotice(title: title, subtitle: subtitle, href: href, body: body, uid: uid, tid: tid));
      if (result.length >= 100) break;
    }

    if (result.isEmpty) {
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        if (!_isPmHref(href)) continue;
        final label = _cleanNodeText(a);
        final uid = _uidFromPmHref(href);
        if (label.isEmpty && uid <= 0) continue;
        final key = 'pm:$href:$label';
        if (!seen.add(key)) continue;
        result.add(NativeNotice(title: label.isEmpty ? '站内私信' : label, subtitle: '站内私信', href: href, uid: uid));
        if (result.length >= 100) break;
      }
    }
    return result;
  }

  Future<List<NativeMessage>> fetchMessages() async {
    final doc = _doc(await _first(['home.php?mod=space&do=pm&mobile=2', 'home.php?mod=space&do=pm', 'home.php?mod=spacecp&ac=pm&op=pm']));
    final result = <NativeMessage>[];
    final seen = <String>{};
    for (final node in doc.querySelectorAll('dl.pml,dl[id^="pmlist_"],li.pm_list,li.pml,.pm_list > li,.pml > li')) {
      _addMessage(result, seen, _parseMessage(node));
      if (result.length >= 100) return result;
    }
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (!_isPmHref(href)) continue;
      var node = a.parent;
      dynamic best;
      for (var depth = 0; depth < 6 && node != null; depth++, node = node.parent) {
        final text = _cleanNodeText(node);
        if (text.length >= 2 && text.length <= 500) best = node;
        if (text.length > 500) break;
      }
      _addMessage(result, seen, _parseMessage(best ?? a), fallbackHref: href, fallbackTitle: _cleanNodeText(a));
      if (result.length >= 100) break;
    }
    if (result.isEmpty) {
      for (final node in doc.querySelectorAll('li,article,div')) {
        final text = _cleanNodeText(node);
        if (text.length < 3 || text.length > 300) continue;
        final uid = _pmUid(node);
        if (uid <= 0 || !_looksLikeMessageText(text)) continue;
        _addMessage(result, seen, _parseMessage(node));
        if (result.length >= 100) break;
      }
    }
    return result;
  }

  static void _addMessage(List<NativeMessage> result, Set<String> seen, NativeMessage? message, {String fallbackHref = '', String fallbackTitle = ''}) {
    if (message == null && fallbackHref.isEmpty) return;
    if (message == null) {
      final uid = _uidFromPmHref(fallbackHref);
      final sender = fallbackTitle.isEmpty ? '站内私信' : fallbackTitle;
      message = NativeMessage(title: sender, subtitle: '站内私信', sender: sender, uid: uid);
    }
    final key = '${message.uid}|${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
    if (seen.add(key)) result.add(message);
  }

  NativeMessage? _parseMessage(dynamic node) {
    if (node == null) return null;
    final author = node.querySelector('a[href*="touid="],a[href*="uid="],a[href*="mod=space"],a[href*="username="]');
    var sender = _cleanNodeText(author);
    final time = _cleanNodeText(node.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]'));
    var body = _cleanNodeText(node.querySelector('.ptm,.pml_body,.pm_body,.pm_message,.comiis_pmtext,.comiis_pm_content,.xg2') ?? node);
    if (sender.isNotEmpty) body = body.replaceFirst(sender, '').trim();
    if (time.isNotEmpty) body = body.replaceFirst(time, '').trim();
    body = body.replaceAll(RegExp(r'^[:：\-·\s]+|[:：\-·\s]+$'), '').trim();
    final uid = _pmUid(node);
    if (body.isEmpty || _isUiOnlyMessage(body)) return null;
    if (sender.isEmpty) sender = '站内私信';
    return NativeMessage(title: sender, subtitle: body, sender: sender, time: time, uid: uid);
  }

  static bool _isPmHref(String href) {
    final h = href.toLowerCase();
    return h.contains('do=pm') || h.contains('ac=pm') || h.contains('pmid=') || h.contains('touid=') || h.contains('subop=view');
  }

  static int _uidFromPmHref(String href) {
    for (final key in const ['touid', 'uid']) {
      final m = RegExp('[?&]$key=(\\d+)', caseSensitive: false).firstMatch(href);
      final v = int.tryParse(m?.group(1) ?? '');
      if (v != null && v > 0) return v;
    }
    return 0;
  }

  static int _pmUid(dynamic node) {
    for (final a in node.querySelectorAll('a[href*="touid="]')) {
      final v = _uidFromPmHref(a.attributes['href'] ?? '');
      if (v > 0) return v;
    }
    for (final a in node.querySelectorAll('a[href*="uid="]')) {
      final v = _uidFromPmHref(a.attributes['href'] ?? '');
      if (v > 0) return v;
    }
    return 0;
  }

  static bool _looksLikeMessageText(String text) {
    if (text == '站内私信' || text == '私信' || text == '消息') return false;
    return !RegExp(r'^(首页|登录|注册|退出|下一页|上一页|更多|设置|通知|好友|关注|粉丝)$').hasMatch(text);
  }

  static bool _isUiOnlyMessage(String text) => RegExp(r'^(站内私信|站内消息|私信|消息|查看|详情|回复|删除)$').hasMatch(text.trim());

  Future<List<NativeFriend>> fetchFriends() async {
    final doc = _doc(await _first(['home.php?mod=space&do=friend&mobile=2', 'home.php?mod=space&do=friend']));
    final result = <NativeFriend>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a[href*="uid="],a[href*="username="]')) {
      final name = _cleanNodeText(a);
      if (name.isEmpty || name.length > 40 || _looksLikeNavigation(name) || !seen.add(name)) continue;
      final parent = _cleanNodeText(a.parent);
      result.add(NativeFriend(name: name, subtitle: parent == name ? '好友 / 关注' : parent.replaceFirst(name, '').trim()));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<NativeCreditSummary> fetchCredits() async {
    final doc = _doc(await _first(['home.php?mod=spacecp&ac=credit&mobile=2', 'home.php?mod=spacecp&ac=credit']));
    final text = _cleanNodeText(doc.body);
    final records = <String>[];
    for (final node in doc.querySelectorAll('table tr,li,p,.credit_box,.comiis_credit,.credit_list,.mt')) {
      final value = _cleanNodeText(node);
      if (value.isNotEmpty && value.length <= 300 && RegExp(r'(星币|积分|余额|充值|消费|交易|收入|支出)').hasMatch(value) && !records.contains(value)) records.add(value);
    }
    final balance = RegExp(r'(?:星币(?:余额)?|余额)\s*[:：]?\s*(\d+(?:\.\d+)?)').firstMatch(text)?.group(1) ?? '—';
    return NativeCreditSummary(balance: balance, records: records.take(30).toList());
  }

  Future<String?> sendMessage({required String to, required String message}) async {
    final target = to.trim();
    final text = message.trim();
    if (target.isEmpty) return '请输入收件人用户名';
    if (text.isEmpty) return '请输入私信内容';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final headers = <String, String>{
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if (cookie.isNotEmpty) 'Cookie': cookie,
      };

      String? formhash;
      String? referer;
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final paths = <String>[
        'home.php?mod=spacecp&ac=pm&op=send&username=${Uri.encodeQueryComponent(target)}&mobile=2&_ycoo_ts=$now',
        'home.php?mod=space&do=pm&mobile=2&_ycoo_ts=$now',
        'forum.php?mobile=2&_ycoo_ts=$now',
      ];

      for (final path in paths) {
        try {
          final uri = Uri.parse('$_base$path');
          final response = await client.get(uri, headers: {
            ...headers,
            'Referer': '${_base}home.php?mod=space&do=pm&mobile=2',
          }).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) continue;
          final html = NetClient.decode(response.bodyBytes);
          if (_looksLikeLogin(html)) return '登录态已失效，请重新登录论坛';
          final candidate = _formhashFromHtml(html);
          if (candidate.isNotEmpty) {
            formhash = candidate;
            referer = uri.toString();
            break;
          }
        } catch (_) {}
      }

      if (formhash == null || formhash.isEmpty) return '未取得私信令牌(formhash)，请刷新登录状态后重试';

      final sendUri = Uri.parse('$_base/home.php').replace(queryParameters: {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'send',
        'mobile': '2',
        'inajax': '1',
      });
      final bodyParams = <String, String>{
        'formhash': formhash,
        'username': target,
        'message': text,
        'pmsubmit': 'yes',
        'sendpm': 'true',
        'inajax': '1',
      };

      final response = await client.post(
        sendUri,
        headers: {
          ...headers,
          'Referer': referer ?? '${_base}home.php?mod=space&do=pm&mobile=2',
          'Origin': _base,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: bodyParams,
      ).timeout(const Duration(seconds: 20));
      final responseBody = NetClient.decode(response.bodyBytes);
      if (_looksLikeSuccess(responseBody)) return null;
      if (_looksLikeLogin(responseBody)) return '登录态已失效，请重新登录论坛';
      if (_looksLikeTokenError(responseBody)) {
        // 只在服务器明确返回令牌错误时刷新一次，避免重复发送消息。
        final fresh = await _fetchFreshFormhash(client, headers, target);
        if (fresh != null && fresh.isNotEmpty && fresh != formhash) {
          bodyParams['formhash'] = fresh;
          final retry = await client.post(
            sendUri,
            headers: {
              ...headers,
              'Referer': referer ?? '${_base}home.php?mod=space&do=pm&mobile=2',
              'Origin': _base,
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'X-Requested-With': 'XMLHttpRequest',
            },
            body: bodyParams,
          ).timeout(const Duration(seconds: 20));
          final retryBody = NetClient.decode(retry.bodyBytes);
          if (_looksLikeSuccess(retryBody)) return null;
          if (_looksLikeLogin(retryBody)) return '登录态已失效，请重新登录论坛';
          return _messageFromResponse(retryBody) ?? '私信发送失败，请稍后重试';
        }
        return '私信令牌已失效，请刷新登录状态后重试';
      }
      return _messageFromResponse(responseBody) ?? '私信发送失败，请稍后重试';
    } catch (_) {
      return '私信请求失败，请检查网络后重试';
    }
  }

  Future<String?> _fetchFreshFormhash(dynamic client, Map<String, String> headers, String target) async {
    try {
      final uri = Uri.parse('$_base/home.php').replace(queryParameters: {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'send',
        'username': target,
        'mobile': '2',
        '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      return _formhashFromHtml(NetClient.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String _formhashFromHtml(String html) {
    final inputRe = RegExp(r'<input\b[^>]*>', caseSensitive: false);
    final nameFirst = RegExp(r'''name\s*=\s*["']formhash["'][^>]*value\s*=\s*["']([^"']+)["']''', caseSensitive: false);
    final valueFirst = RegExp(r'''value\s*=\s*["']([^"']+)["'][^>]*name\s*=\s*["']formhash["']''', caseSensitive: false);
    for (final match in inputRe.allMatches(html)) {
      final tag = match.group(0)!;
      final a = nameFirst.firstMatch(tag)?.group(1)?.trim();
      if (a != null && _validFormhash(a)) return a;
      final b = valueFirst.firstMatch(tag)?.group(1)?.trim();
      if (b != null && _validFormhash(b)) return b;
    }

    for (final pattern in <RegExp>[
      RegExp(r'''(?:formhash|formHash)\s*[:=]\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
      RegExp(r'''["']formhash["']\s*[,=:]\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
      RegExp(r'''(?:data-formhash|data-formHash)\s*=\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
    ]) {
      final value = pattern.firstMatch(html)?.group(1)?.trim();
      if (value != null && _validFormhash(value)) return value;
    }

    // 部分模板(如 Comiis)只在链接/JS 里以普通 URL 参数形式渲染 formhash, 没有 hidden input。
    // 复用 NetClient 的 URL/JSON 提取逻辑作为最终兜底。
    final fromNetClient = NetClient.extractFormHash(html);
    if (fromNetClient != null && _validFormhash(fromNetClient)) return fromNetClient;
    return '';
  }

  static bool _validFormhash(String value) => RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(value);

  static bool _looksLikeTokenError(String body) =>
      body.contains('formhash') || body.contains('操作令牌') || body.contains('请求令牌') || body.contains('token');

  static String? _messageFromResponse(String body) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1);
    final source = (cdata ?? body)
        .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (source.isNotEmpty && source.length <= 160 && (source.contains('私信') || source.contains('消息') || source.contains('用户') || source.contains('权限') || source.contains('登录') || source.contains('失败'))) {
      return source;
    }
    final showError = RegExp(r'''showError\(\s*["']([^"']+)["']''').firstMatch(body)?.group(1)?.trim();
    return showError?.isNotEmpty == true ? showError : null;
  }

  static bool _looksLikeSuccess(String body) => body.contains('succeed') || body.contains('do_success') || body.contains('发送成功') || body.contains('操作成功');

  static String _withoutMobile(String path) {
    final uri = Uri.tryParse('$_base$path');
    if (uri == null) return path;
    final q = <String, String>{...uri.queryParameters}..remove('mobile');
    return uri.replace(queryParameters: q).path + (q.isEmpty ? '' : '?${Uri(queryParameters: q).query}');
  }

  static String _cleanNodeText(dynamic node) {
    if (node == null) return '';
    try {
      final clone = node.clone(true);
      for (final icon in clone.querySelectorAll('i.iconfont,i.comiis-icon,i.comiis_icon,.iconfont,.comiis-icon,[class*="iconfont"],[class*="comiis-icon"],[class*="icon-"]')) {
        icon.remove();
      }
      for (final el in clone.querySelectorAll('svg')) { el.remove(); }
      return _clean(clone.text);
    } catch (_) {
      return _clean(node.text ?? '');
    }
  }

  static String _clean(String text) => text.replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    final text = _cleanNodeText(doc.body);
    return text.isNotEmpty && RegExp(r'(用户名|登录密码)').hasMatch(text) && text.contains('登录') && !html.contains('action=logout');
  }

  static bool _looksLikeNavigation(String text) => const {'下一页','上一页','首页','更多','回复','查看','详情','登录','注册','站内私信','私信'}.contains(text);
}
