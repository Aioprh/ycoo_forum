import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
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

  static const _base = 'https://www.ycoo.net/';

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
    final uri = Uri.parse('$_base$path').replace(queryParameters: {
      ...Uri.parse('$_base$path').queryParameters,
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
    return NetClient.decode(response.bodyBytes);
  }

  Future<List<ThreadItem>> fetchThreads(String path) async {
    final html = await _get(path);
    final doc = parser.parse(html);
    final result = <ThreadItem>[];
    final seen = <int>{};
    final nodes = <dynamic>[...doc.querySelectorAll('li'), ...doc.querySelectorAll('article'), ...doc.querySelectorAll('.threadlist li')];
    for (final node in nodes) {
      for (final a in node.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        final match = RegExp(r'(?:thread-|[?&]tid=)(\d+)').firstMatch(href);
        if (match == null) continue;
        final tid = int.tryParse(match.group(1)!) ?? 0;
        final title = _clean(a.text);
        if (tid == 0 || title.isEmpty || seen.contains(tid)) continue;
        if (_looksLikeNavigation(title)) continue;
        seen.add(tid);
        result.add(ThreadItem(
          tid: tid,
          title: title,
          author: '',
          avatar: '',
          fid: 0,
          boardName: '',
          level: '',
          time: '',
          subtitle: '',
          cover: '',
          likeCount: 0,
          replyCount: 0,
          viewCount: 0,
        ));
        break;
      }
    }
    return result;
  }

  Future<List<MemberNotice>> fetchNotices() async {
    final html = await _get('home.php?mod=space&do=notice&mobile=2');
    final doc = parser.parse(html);
    final result = <MemberNotice>[];
    final seen = <String>{};
    for (final node in doc.querySelectorAll('li, .nts, .notice, .notice_li, .comiis_notice')) {
      final text = _clean(node.text);
      if (text.length < 2 || text.length > 240) continue;
      if (!RegExp(r'(回复|评论|提到|通知|系统|赞了|收藏|提醒)').hasMatch(text)) continue;
      if (!seen.add(text)) continue;
      final parts = text.split(RegExp(r'\s+'));
      final title = parts.isEmpty ? text : parts.take(2).join(' ');
      result.add(MemberNotice(title: title, subtitle: text));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<CreditSummary> fetchCredits() async {
    final html = await _get('home.php?mod=spacecp&ac=credit&mobile=2');
    final doc = parser.parse(html);
    final text = _clean(doc.body?.text ?? '');
    final records = <String>[];
    for (final line in text.split(RegExp(r'\s{2,}|\n'))) {
      final value = _clean(line);
      if (value.isEmpty) continue;
      if (RegExp(r'(星币|积分|余额|充值|消费|交易|收入|支出)').hasMatch(value)) {
        if (!records.contains(value)) records.add(value);
      }
    }
    final balanceMatch = RegExp(r'(?:星币|余额)\s*[:：]?\s*(\d+(?:\.\d+)?)').firstMatch(text);
    return CreditSummary(
      balance: balanceMatch?.group(1) ?? '—',
      records: records.take(30).toList(),
    );
  }

  static String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _looksLikeNavigation(String text) {
    const nav = {'下一页', '上一页', '首页', '更多', '回复', '查看', '详情'};
    return nav.contains(text);
  }
}
