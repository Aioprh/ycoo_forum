import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

class NativeNotice {
  final String title;
  final String subtitle;
  const NativeNotice({required this.title, required this.subtitle});
}

class NativeMessage {
  final String title;
  final String subtitle;
  final String sender;
  final String time;
  const NativeMessage({required this.title, required this.subtitle, this.sender = '', this.time = ''});
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
      } catch (e) {
        last = e;
      }
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
      final title = _clean(a.text);
      if (tid <= 0 || title.length < 2 || !seen.add(tid) || _looksLikeNavigation(title)) continue;
      final parent = _clean(a.parent?.text ?? '');
      result.add(ThreadItem(tid: tid, title: title, author: '', avatar: '', fid: 0, boardName: '', level: '', time: '', subtitle: parent == title ? '' : parent.replaceFirst(title, '').trim(), cover: '', likeCount: 0, replyCount: 0, viewCount: 0));
    }
    return result;
  }

  /// 拉取通知列表。网页端通过 view 参数区分分类：
  ///  all=全部提醒、interactive=坛友互动、system=系统提醒、app=应用提醒、mypost=我的帖子。
  Future<List<NativeNotice>> fetchNotices({String view = 'all'}) async {
    final path = 'home.php?mod=space&do=notice&view=$view';
    final doc = _doc(await _first(['$path&mobile=2', path]));
    final result = <NativeNotice>[];
    final seen = <String>{};
    for (final li in doc.querySelectorAll('li,tr,article,.nts,.notice_li,.comiis_notice,.ntc_list')) {
      // 通知条目通常以 li 承载，内含 dt(时间/屏蔽) 与 dd(内容)
      final dd = li.querySelector('dd');
      final text = _clean(dd?.text ?? li.text);
      if (text.length < 2 || text.length > 500 || !seen.add(text)) continue;
      // 排除导航/功能类 li（子分类 Tab 等）与明显非通知文本
      if (_looksLikeNavigation(text) || !RegExp(r'(回复|评论|提到|通知|系统|赞了|收藏|提醒|关注|好友|主题|购买|充值|任务|注册|订单|经验|积分|星币)').hasMatch(text)) continue;
      final time = _clean(li.querySelector('dt,time,[class*="time"],[class*="date"]')?.text ?? '');
      final subtitle = time.isNotEmpty ? '$time $text' : text;
      result.add(NativeNotice(title: text.length > 60 ? text.substring(0, 60) : text, subtitle: subtitle));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<List<NativeMessage>> fetchMessages() async {
    final doc = _doc(await _first(['home.php?mod=space&do=pm&mobile=2', 'home.php?mod=space&do=pm']));
    final result = <NativeMessage>[];
    final seen = <String>{};
    final nodes = doc.querySelectorAll('dl.pml, dl[id^="pmlist_"]');
    for (final node in nodes) {
      final message = _parseMessage(node);
      if (message == null) continue;
      final key = '${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
      if (!seen.add(key)) continue;
      result.add(message);
      if (result.length >= 100) break;
    }
    if (result.isNotEmpty) return result;
    for (final node in doc.querySelectorAll('li.pm_list,li.pml,.pm_list > li,.pml > li')) {
      final message = _parseMessage(node);
      if (message == null) continue;
      final key = '${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
      if (!seen.add(key)) continue;
      result.add(message);
      if (result.length >= 100) break;
    }
    return result;
  }

  NativeMessage? _parseMessage(dynamic node) {
    final author = node.querySelector('a[href*="uid="],a[href*="mod=space"]');
    var sender = _clean(author?.text ?? '');
    final time = _clean(node.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]')?.text ?? '');
    var body = _clean(node.querySelector('.ptm')?.text ?? node.text);
    if (sender.isNotEmpty) body = body.replaceFirst(sender, '').trim();
    if (time.isNotEmpty) body = body.replaceFirst(time, '').trim();
    body = body.replaceAll(RegExp(r'^[:：\-·\s]+|[:：\-·\s]+$'), '').trim();
    if (body.isEmpty || body == '站内私信' || body == '站内消息' || body == '私信') return null;
    if (sender.isEmpty) sender = '站内私信';
    return NativeMessage(title: sender, subtitle: body, sender: sender, time: time);
  }

  Future<List<NativeFriend>> fetchFriends() async {
    final doc = _doc(await _first(['home.php?mod=space&do=friend&mobile=2', 'home.php?mod=space&do=friend']));
    final result = <NativeFriend>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a[href*="uid="],a[href*="username="]')) {
      final name = _clean(a.text);
      if (name.isEmpty || name.length > 40 || _looksLikeNavigation(name) || !seen.add(name)) continue;
      final parent = _clean(a.parent?.text ?? '');
      result.add(NativeFriend(name: name, subtitle: parent == name ? '好友 / 关注' : parent.replaceFirst(name, '').trim()));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<NativeCreditSummary> fetchCredits() async {
    final doc = _doc(await _first(['home.php?mod=spacecp&ac=credit&mobile=2', 'home.php?mod=spacecp&ac=credit']));
    final text = _clean(doc.body?.text ?? '');
    final records = <String>[];
    for (final node in doc.querySelectorAll('table tr,li,p,.credit_box,.comiis_credit,.credit_list,.mt')) {
      final value = _clean(node.text);
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
      for (final path in [
        'home.php?mod=spacecp&ac=pm&op=send&mobile=2',
        'home.php?mod=space&do=pm&mobile=2',
        'forum.php?mobile=2',
      ]) {
        try {
          final uri = Uri.parse('$_base$path').replace(queryParameters: {
            ...Uri.parse('$_base$path').queryParameters,
            '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
          });
          final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
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
      final sendUri = Uri.parse('$_base/home.php?mod=spacecp&ac=pm&op=send&mobile=2');
      final response = await client.post(sendUri, headers: {
        ...headers,
        'Referer': referer ?? '$_base',
        'Origin': _base,
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
      }, body: {
        'formhash': formhash,
        'username': target,
        'message': text,
        'pmsubmit': 'yes',
        'sendpm': 'true',
      }).timeout(const Duration(seconds: 20));
      final body = NetClient.decode(response.bodyBytes);
      if (_looksLikeSuccess(body)) return null;
      if (body.contains('请先登录') || body.contains('登录后才能')) return '登录态已失效，请重新登录论坛';
      if (body.contains('formhash') || body.contains('操作令牌')) return '私信令牌已失效，请刷新登录状态后重试';
      final error = _messageFromResponse(body);
      return error ?? '私信发送失败，请稍后重试';
    } catch (_) {
      return '私信请求失败，请检查网络后重试';
    }
  }

  static String _formhashFromHtml(String html) {
    final doc = parser.parse(html);
    final input = doc.querySelector('input[name="formhash"]');
    return (input?.attributes['value'] ?? '').trim();
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

  static String _clean(String text) => text.replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    final text = _clean(doc.body?.text ?? '');
    return text.isNotEmpty && RegExp(r'(用户名|登录密码)').hasMatch(text) && text.contains('登录') && !html.contains('action=logout');
  }

  static bool _looksLikeNavigation(String text) => const {'下一页','上一页','首页','更多','回复','查看','详情','登录','注册','站内私信','私信'}.contains(text);
}
