import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
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
  const NativeMessage({required this.title, required this.subtitle});
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
  static const _base = 'https://www.ycoo.net/';

  Future<String> _get(String path) async {
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final parsed = Uri.parse('$_base$path');
    final uri = parsed.replace(queryParameters: {
      ...parsed.queryParameters,
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

  /// 解析前移除脚本、样式和模板节点，彻底避免把 JS 源码当成页面正文。
  static dynamic _doc(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) {
      node.remove();
    }
    return doc;
  }

  Future<List<ThreadItem>> fetchThreads(String path) async {
    final html = await _first([path, _withoutMobile(path)]);
    final doc = _doc(html);
    final result = <ThreadItem>[];
    final seen = <int>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'(?:thread-|[?&]tid=)(\d+)', caseSensitive: false).firstMatch(href);
      if (m == null) continue;
      final tid = int.tryParse(m.group(1)!) ?? 0;
      final title = _clean(a.text);
      if (tid <= 0 || title.length < 2 || seen.contains(tid) || _looksLikeNavigation(title)) continue;
      seen.add(tid);
      final parent = _clean(a.parent?.text ?? '');
      result.add(ThreadItem(tid: tid, title: title, author: '', avatar: '', fid: 0, boardName: '', level: '', time: '', subtitle: parent == title ? '' : parent.replaceFirst(title, '').trim(), cover: '', likeCount: 0, replyCount: 0, viewCount: 0));
    }
    return result;
  }

  Future<List<NativeNotice>> fetchNotices() async {
    final html = await _first(['home.php?mod=space&do=notice&mobile=2', 'home.php?mod=space&do=notice']);
    final doc = _doc(html);
    final result = <NativeNotice>[];
    final seen = <String>{};
    for (final node in doc.querySelectorAll('li,tr,article,.nts,.notice,.notice_li,.comiis_notice,.ntc_list')) {
      final text = _clean(node.text);
      if (text.length < 2 || text.length > 500 || !seen.add(text)) continue;
      if (!RegExp(r'(回复|评论|提到|通知|系统|赞了|收藏|提醒|关注|好友|主题)').hasMatch(text)) continue;
      result.add(NativeNotice(title: text.length > 60 ? text.substring(0, 60) : text, subtitle: text));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<List<NativeMessage>> fetchMessages() async {
    final html = await _first(['home.php?mod=space&do=pm&mobile=2', 'home.php?mod=space&do=pm']);
    final doc = _doc(html);
    final result = <NativeMessage>[];
    final seen = <String>{};
    for (final node in doc.querySelectorAll('li,tr,article,.pm_list,.pml,.comiis_pm,.list')) {
      final text = _clean(node.text);
      if (text.length < 2 || text.length > 500 || !seen.add(text)) continue;
      final links = node.querySelectorAll('a[href]');
      final title = links.isNotEmpty ? _clean(links.first.text) : (text.length > 50 ? text.substring(0, 50) : text);
      if (title.isEmpty || _looksLikeNavigation(title)) continue;
      result.add(NativeMessage(title: title, subtitle: text == title ? '站内消息' : text));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<List<NativeFriend>> fetchFriends() async {
    final html = await _first(['home.php?mod=space&do=friend&mobile=2', 'home.php?mod=space&do=friend']);
    final doc = _doc(html);
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
    final html = await _first(['home.php?mod=spacecp&ac=credit&mobile=2', 'home.php?mod=spacecp&ac=credit']);
    final doc = _doc(html);
    final text = _clean(doc.body?.text ?? '');
    final records = <String>[];
    for (final node in doc.querySelectorAll('table tr,li,p,.credit_box,.comiis_credit,.credit_list,.mt')) {
      final value = _clean(node.text);
      if (value.isEmpty || value.length > 300) continue;
      if (RegExp(r'(星币|积分|余额|充值|消费|交易|收入|支出)').hasMatch(value) && !records.contains(value)) records.add(value);
    }
    if (records.isEmpty) {
      for (final line in text.split(RegExp(r'\s{2,}|\n'))) {
        final value = _clean(line);
        if (value.isNotEmpty && value.length <= 300 && RegExp(r'(星币|积分|余额|充值|消费|交易|收入|支出)').hasMatch(value) && !records.contains(value)) records.add(value);
      }
    }
    final balance = RegExp(r'(?:星币(?:余额)?|余额)\s*[:：]?\s*(\d+(?:\.\d+)?)').firstMatch(text)?.group(1) ?? '—';
    return NativeCreditSummary(balance: balance, records: records.take(30).toList());
  }

  /// 原生发送站内私信（Discuz spacecp.pm）。返回 null 表示成功，否则返回失败原因。
  Future<String?> sendMessage({required String to, required String message}) async {
    final target = to.trim();
    final text = message.trim();
    if (target.isEmpty) return '请输入收件人用户名';
    if (text.isEmpty) return '请输入私信内容';
    if ((AuthService.instance.authCookie ?? '').isEmpty) return '请先登录论坛';
    try {
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
      final sendPath = 'home.php?mod=spacecp&ac=pm&op=send&mobile=2';
      // 先取发送页取得最新 formhash（同时维持会话）。
      final pageResp = await NetClient.retry(() => client.get(Uri.parse('$_base$sendPath'), headers: headers).timeout(const Duration(seconds: 20)));
      final page = NetClient.decode(pageResp.bodyBytes);
      final formhash = _hiddenValue(page, 'formhash');
      if (formhash == null || formhash.isEmpty) {
        if (_looksLikeLogin(page)) return '登录态已失效，请重新登录论坛';
        return '未取得私信令牌(formhash)，请稍后重试';
      }
      final resp = await NetClient.retry(() => client.post(
        Uri.parse('$_base$sendPath'),
        headers: {...headers, 'Referer': '$_base$sendPath', 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest'},
        body: <String, String>{
          'formhash': formhash,
          'username': target,
          'message': text,
          'pmsubmit': 'yes',
          'sendpm': 'true',
        },
      ).timeout(const Duration(seconds: 20)));
      final body = NetClient.decode(resp.bodyBytes);
      if (body.contains('succeed') || body.contains('发送成功') || body.contains('操作成功') || body.contains('do_success')) {
        return null;
      }
      if (body.contains('请先登录') || body.contains('登录后才能')) return '登录态已失效，请重新登录论坛';
      final msg = RegExp(r'''showError\(\s*['"]([^'"]+)['"]''').firstMatch(body)?.group(1);
      if (msg != null) return msg.trim();
      if (body.contains('不允许') || body.contains('没有权限')) return '当前账号不允许发送私信';
      return '私信发送失败，请稍后重试';
    } catch (_) {
      return '私信请求失败，请检查网络后重试';
    }
  }

  /// 从页面 HTML 中提取指定 name 的隐藏字段值（兼容 name/value 顺序互换）。
  static String? _hiddenValue(String html, String name) {
    final escaped = RegExp.escape(name);
    final nameFirst = RegExp(
      'name\\s*=\\s*[\"\\\']$escaped[\"\\\'][^>]*value\\s*=\\s*[\"\\\']([^\"\\\']+)[\"\\\']',
      caseSensitive: false,
    );
    final valueFirst = RegExp(
      'value\\s*=\\s*[\"\\\']([^\"\\\']+)[\"\\\'][^>]*name\\s*=\\s*[\"\\\']$escaped[\"\\\']',
      caseSensitive: false,
    );
    return nameFirst.firstMatch(html)?.group(1) ?? valueFirst.firstMatch(html)?.group(1);
  }

  static String _withoutMobile(String path) {
    final uri = Uri.tryParse('$_base$path');
    if (uri == null) return path;
    final q = <String, String>{...uri.queryParameters}..remove('mobile');
    return uri.replace(queryParameters: q).path + (q.isEmpty ? '' : '?${Uri(queryParameters: q).query}');
  }

  static String _clean(String text) => text.replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) node.remove();
    final t = _clean(doc.body?.text ?? '');
    if (t.isEmpty) return true;
    return RegExp(r'(用户名|登录密码)').hasMatch(t) && RegExp(r'登录').hasMatch(t) && !html.contains('action=logout');
  }

  static bool _looksLikeNavigation(String text) => const {'下一页','上一页','首页','更多','回复','查看','详情','登录','注册'}.contains(text);
}
