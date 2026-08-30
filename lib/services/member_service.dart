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
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
    final parsed = Uri.parse('$_base$path');
    final params = <String, String>{
      ...parsed.queryParameters,
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    final uri = parsed.replace(queryParameters: params);
    final response = await NetClient.retry(
      () => client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20)),
    );
    if (response.statusCode != 200)
      throw Exception('请求失败 HTTP ${response.statusCode}');
    final html = NetClient.decode(response.bodyBytes);
    if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
    return html;
  }

  Future<String> _getFirstWorking(List<String> paths) async {
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

  Future<List<ThreadItem>> fetchThreads(String path) async {
    final paths = <String>[path];
    // Discuz 主题页在不同模板下对 mobile 参数的输出结构不同，第二次用桌面模板兜底。
    final uri = Uri.tryParse('$_base$path');
    if (uri != null) {
      final q = <String, String>{...uri.queryParameters}..remove('mobile');
      paths.add(
        uri.replace(queryParameters: q).path +
            (q.isEmpty ? '' : '?${Uri(queryParameters: q).query}'),
      );
    }
    final html = await _getFirstWorking(paths);
    return _parseThreads(html);
  }

  List<ThreadItem> _parseThreads(String html) {
    final doc = parser.parse(html);
    final result = <ThreadItem>[];
    final seen = <int>{};

    // 不再依赖单一 li/class；Discuz 模板只要保留 thread-xxx 或 tid=xxx 就能解析。
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final match = RegExp(
        r'(?:thread-|[?&]tid=)(\d+)',
        caseSensitive: false,
      ).firstMatch(href);
      if (match == null) continue;
      final tid = int.tryParse(match.group(1) ?? '') ?? 0;
      final title = _clean(a.text);
      if (tid <= 0 || title.isEmpty || seen.contains(tid)) continue;
      if (_looksLikeNavigation(title) || title.length < 2) continue;
      // 排除明显的操作链接，但保留真实主题标题。
      if (RegExp(r'^(回复|查看|详情|购买主题|下一页|上一页|首页|尾页|分享|收藏)$').hasMatch(title))
        continue;
      seen.add(tid);
      final parentText = _clean(a.parent?.text ?? '');
      result.add(
        ThreadItem(
          tid: tid,
          title: title,
          author: '',
          avatar: '',
          fid:
              int.tryParse(
                RegExp(r'(?:forum-|[?&]fid=)(\d+)')
                        .firstMatch(a.parent?.outerHtml ?? '')
                        ?.group(1) ??
                    '',
              ) ??
              0,
          boardName: '',
          level: '',
          time: '',
          subtitle: parentText == title
              ? ''
              : parentText.replaceFirst(title, '').trim(),
          cover: '',
          likeCount: 0,
          replyCount: 0,
          viewCount: 0,
        ),
      );
    }
    return result;
  }

  Future<List<MemberNotice>> fetchNotices() async {
    final html = await _getFirstWorking([
      'home.php?mod=space&do=notice&mobile=2',
      'home.php?mod=space&do=notice',
    ]);
    final doc = parser.parse(html);
    final result = <MemberNotice>[];
    final seen = <String>{};
    for (final node in doc.querySelectorAll(
      'li, tr, article, .nts, .notice, .notice_li, .comiis_notice, .ntc_list',
    )) {
      final text = _clean(node.text);
      if (text.length < 2 || text.length > 500) continue;
      if (!RegExp(r'(回复|评论|提到|通知|系统|赞了|收藏|提醒|关注|好友|主题)').hasMatch(text))
        continue;
      if (!seen.add(text)) continue;
      final title = text.length > 60 ? text.substring(0, 60) : text;
      result.add(MemberNotice(title: title, subtitle: text));
      if (result.length >= 100) break;
    }
    return result;
  }

  Future<CreditSummary> fetchCredits() async {
    final html = await _getFirstWorking([
      'home.php?mod=spacecp&ac=credit&mobile=2',
      'home.php?mod=spacecp&ac=credit',
    ]);
    final doc = parser.parse(html);
    final text = _clean(doc.body?.text ?? '');
    final records = <String>[];
    for (final line in text.split(RegExp(r'\s{2,}|\n'))) {
      final value = _clean(line);
      if (value.isEmpty) continue;
      if (RegExp(r'(星币|积分|余额|充值|消费|交易|收入|支出)').hasMatch(value) &&
          !records.contains(value))
        records.add(value);
    }
    final balanceMatch = RegExp(r'(?:星币|余额)\s*[:：]?\s*(\d+(?:\.\d+)?)')
        .firstMatch(text);
    return CreditSummary(
      balance: balanceMatch?.group(1) ?? '—',
      records: records.take(30).toList(),
    );
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _looksLikeLogin(String html) {
    final t = _clean(parser.parse(html).body?.text ?? '');
    if (t.isEmpty) return true;
    final hasLoginForm =
        RegExp(r'(用户名|登录密码)').hasMatch(t) && RegExp(r'登录').hasMatch(t);
    final hasLogout = html.contains('action=logout');
    return hasLoginForm && !hasLogout;
  }

  static bool _looksLikeNavigation(String text) {
    const nav = {'下一页', '上一页', '首页', '更多', '回复', '查看', '详情', '登录', '注册'};
    return nav.contains(text);
  }
}
