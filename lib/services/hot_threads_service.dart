import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// 专门解析网页端热门导读。
///
/// ycoo 的热门页与普通导读页使用的 DOM 结构并不总是一致，
/// 因此这里不依赖 `li.forumlist_li`，而是从主题链接反向定位帖子容器。
class HotThreadsService {
  HotThreadsService._();
  static final instance = HotThreadsService._();

  static String get _base => SiteConfig.base;
  static const _canonical = '${SiteConfig.base}forum.php?mod=guide&view=hot&index=1';

  Future<List<ThreadItem>> fetch() async {
    final urls = <String>[
      _canonical,
      '$_canonical&mobile=2',
      '$_base' 'forum.php?mod=guide&view=hot&index=1&mobile=2',
    ];
    final seenUrls = <String>{};
    for (final url in urls) {
      if (!seenUrls.add(url)) continue;
      try {
        final html = await _get(url);
        final result = _parse(parser.parse(html));
        if (result.isNotEmpty) return result;
      } catch (_) {
        // 尝试下一种页面形态。
      }
    }
    return const <ThreadItem>[];
  }

  Future<String> _get(String url) async {
    final client = await NetClient.instance.client;
    final parsed = Uri.parse(url);
    final params = <String, String>{
      ...parsed.queryParameters,
      '_ycoo_hot_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    final uri = parsed.replace(queryParameters: params);
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': _base,
    };
    final cookie = AuthService.instance.authCookie;
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    final response = await NetClient.retry(() => client.get(uri, headers: headers));
    if (response.statusCode != 200) throw Exception('热门页请求失败 HTTP ${response.statusCode}');
    return NetClient.decode(response.bodyBytes);
  }

  List<ThreadItem> _parse(dom.Document doc) {
    final result = <ThreadItem>[];
    final seen = <int>{};
    final anchors = doc.querySelectorAll('a[href]').where((a) {
      final href = a.attributes['href'] ?? '';
      return RegExp(r'(?:thread-\d+|[?&](?:tid|ptid)=\d+)', caseSensitive: false).hasMatch(href);
    });

    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      final tid = _tid(href);
      if (tid == null || !seen.add(tid)) continue;

      final root = _container(a);
      var title = _clean(a.text);
      if (!_validTitle(title)) {
        title = _firstText(root, const [
          'h1', 'h2', 'h3',
          '.xst', '.subject', '.title',
          '.mmlist_li_box h2 a',
          'th a',
          'a[href*="tid="]',
        ]);
      }
      if (!_validTitle(title)) continue;

      final rootHtml = root?.outerHtml ?? '';
      final rootText = _clean(root?.text ?? '');
      final boardAnchor = root?.querySelector('.comiis_xznalist_bk a, .forumname a, .from a, a[href*="fid="]');
      final author = _firstText(root, const ['.top_user', '.author', '.by', '.xw1', '.authi a']);
      final avatar = _abs(root?.querySelector('img')?.attributes['src'] ?? '');
      final board = _clean(boardAnchor?.text ?? _firstText(root, const ['.forumname', '.from', '.forum']));
      final fid = _firstInt(RegExp(r'(?:forum-|[?&]fid=)(\d+)', caseSensitive: false), rootHtml) ?? 0;
      final level = _firstText(root, const ['.top_lev', '.level']);
      final time = _firstText(root, const ['.f_d', '.time', 'time', '.kmtime', '.dateline']);

      result.add(ThreadItem(
        tid: tid,
        title: title,
        author: author,
        avatar: avatar,
        fid: fid,
        boardName: board,
        level: level,
        time: time,
        subtitle: _subtitle(rootText, title),
        cover: _abs(root?.querySelector('img')?.attributes['src'] ?? ''),
        likeCount: _numberAfter(rootText, const ['点赞', '喜欢']),
        replyCount: _numberAfter(rootText, const ['回复', '评论']),
        viewCount: _numberAfter(rootText, const ['浏览', '查看']),
      ));
      if (result.length >= 50) break;
    }
    return result;
  }

  dom.Element? _container(dom.Element element) {
    dom.Element? p = element.parent;
    for (var i = 0; i < 8 && p != null; i++, p = p.parent) {
      final tag = p.localName ?? '';
      final cls = p.classes.join(' ').toLowerCase();
      if (tag == 'li' || tag == 'article' || tag == 'tr' || tag == 'section') return p;
      if (tag == 'div' && (cls.contains('forumlist') || cls.contains('thread') || cls.contains('list') || cls.contains('guide') || cls.contains('post'))) return p;
    }
    return element.parent;
  }

  static int? _tid(String href) {
    return _firstInt(RegExp(r'(?:thread-|[?&](?:tid|ptid)=)(\d+)', caseSensitive: false), href);
  }

  static String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _validTitle(String value) {
    if (value.length < 2 || value.length > 300) return false;
    const bad = {'首页', '登录', '注册', '返回', '下一页', '上一页', '查看更多', '查看全部', '热门'};
    return !bad.contains(value);
  }

  static String _firstText(dom.Element? root, List<String> selectors) {
    if (root == null) return '';
    for (final selector in selectors) {
      final value = _clean(root.querySelector(selector)?.text ?? '');
      if (_validTitle(value)) return value;
    }
    return '';
  }

  static String _subtitle(String text, String title) {
    if (text.isEmpty || text == title) return '';
    final value = _clean(text.replaceFirst(title, ''));
    return value.length > 180 ? value.substring(0, 180) : value;
  }

  static int _numberAfter(String text, List<String> keys) {
    for (final key in keys) {
      final match = RegExp('$key\\s*[:：]?\\s*(\\d+)').firstMatch(text);
      if (match != null) return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  static int? _firstInt(RegExp regex, String value) {
    final match = regex.firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String _abs(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return _base + value.substring(1);
    return _base + value.replaceFirst(RegExp(r'^\./'), '');
  }
}
