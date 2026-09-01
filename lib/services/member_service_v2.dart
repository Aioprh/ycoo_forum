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
      result.add(ThreadItem(tid: tid, title: title, author: '', avatar: '', fid: 0, boardName: '', level: '', time: '', subtitle: parent == title ? '' : parent.replaceFirst(title, '').trim(), cover: '', likeCount: 0, replyCount: 0, viewCount: 0));
    }
    return result;
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

      // 帖子链接（thread / 提醒指向的主题）
      int tid = 0;
      for (final a in li.querySelectorAll('a[href]')) {
        final h = a.attributes['href'] ?? '';
        final m = RegExp(r'(?:thread-|[?&]tid=)(\d+)', caseSensitive: false).firstMatch(h);
        if (m != null) { final v = int.tryParse(m.group(1)!); if (v != null && v > 0) { tid = v; break; } }
      }
      // 作者 uid（notice_imgs / notice_img 头像、作者链接）
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
      // 通用回退：站内私信入口
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
      final headers = <String, String>{'User-Agent': NetClient.ua,'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8','Accept-Language': 'zh-CN,zh;q=0.9','Cache-Control': 'no-cache, no-store','Pragma': 'no-cache',if (cookie.isNotEmpty) 'Cookie': cookie};
      String? formhash;
      String? referer;
      for (final path in ['home.php?mod=spacecp&ac=pm&op=send&mobile=2','home.php?mod=space&do=pm&mobile=2','forum.php?mobile=2']) {
        try {
          final uri = Uri.parse('$_base$path').replace(queryParameters: {...Uri.parse('$_base$path').queryParameters,'_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString()});
          final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
          final html = NetClient.decode(response.bodyBytes);
          if (_looksLikeLogin(html)) return '登录态已失效，请重新登录论坛';
          final candidate = _formhashFromHtml(html);
          if (candidate.isNotEmpty) { formhash = candidate; referer = uri.toString(); break; }
        } catch (_) {}
      }
      if (formhash == null || formhash.isEmpty) return '未取得私信令牌(formhash)，请刷新登录状态后重试';
      final sendUri = Uri.parse('$_base/home.php?mod=spacecp&ac=pm&op=send&mobile=2');
      final response = await client.post(sendUri, headers: {...headers,'Referer': referer ?? '$_base','Origin': _base,'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With': 'XMLHttpRequest'}, body: {'formhash': formhash,'username': target,'message': text,'pmsubmit': 'yes','sendpm': 'true'}).timeout(const Duration(seconds: 20));
      final body = NetClient.decode(response.bodyBytes);
      if (_looksLikeSuccess(body)) return null;
      if (body.contains('请先登录') || body.contains('登录后才能')) return '登录态已失效，请重新登录论坛';
      if (body.contains('formhash') || body.contains('操作令牌')) return '私信令牌已失效，请刷新登录状态后重试';
      return _messageFromResponse(body) ?? '私信发送失败，请稍后重试';
    } catch (_) { return '私信请求失败，请检查网络后重试'; }
  }

  static String _formhashFromHtml(String html) {
    final doc = parser.parse(html);
    final input = doc.querySelector('input[name="formhash"]');
    final v = (input?.attributes['value'] ?? '').trim();
    if (v.isNotEmpty) return v;
    final m = RegExp(r'''(?:formhash|formHash)\s*[:=]\s*["']([A-Za-z0-9_-]{6,64})["']''', caseSensitive: false).firstMatch(html);
    return m?.group(1)?.trim() ?? '';
  }

  static String? _messageFromResponse(String body) {
    final match = RegExp(r'''showError\(\s*['"]([^'"]+)['"]''').firstMatch(body);
    return match?.group(1)?.trim();
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
