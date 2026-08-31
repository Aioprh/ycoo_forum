import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/board.dart';
import '../models/thread_item.dart';
import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 兼容 ycoo.net 模板变化的兜底解析器。
class SiteFallbackService {
  SiteFallbackService._();
  static final instance = SiteFallbackService._();

  static String get _base => SiteConfig.base;

  Future<String> _get(String url) async {
    final client = await NetClient.instance.client;
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
    };
    final cookie = AuthService.instance.authCookie;
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    final parsed = Uri.parse(url);
    final uri = parsed.replace(queryParameters: {
      ...parsed.queryParameters,
      '_ycoo_fallback': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final response = await NetClient.retry(() => client.get(uri, headers: headers));
    if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
    return NetClient.decode(response.bodyBytes);
  }

  Future<List<ThreadItem>> fetchThreads(String url) async {
    var result = _parseThreads(parser.parse(await _get(url)));
    if (result.isNotEmpty) return result;
    final uri = Uri.parse(url);
    if (uri.queryParameters.containsKey('mobile')) {
      final params = <String, String>{...uri.queryParameters}..remove('mobile');
      result = _parseThreads(parser.parse(await _get(uri.replace(queryParameters: params).toString())));
    }
    return result;
  }

  List<ThreadItem> _parseThreads(dom.Document doc) {
    final result = <ThreadItem>[];
    final seen = <int>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      final tid = _id(RegExp(r'(?:thread-|[?&](?:tid|ptid)=)(\d+)', caseSensitive: false), href);
      if (tid == null || seen.contains(tid)) continue;

      var title = _clean(a.text);
      final root = _container(a);
      if (!_validTitle(title)) {
        title = _firstText(root, ['h1', 'h2', 'h3', '.title', '.subject', '.mmlist_li_box h2 a']);
      }
      if (!_validTitle(title)) continue;

      final text = _clean(root?.text ?? '');
      final author = _firstText(root, ['.top_user', '.author', '.by', '.xw1']);
      final avatar = _abs(root?.querySelector('img')?.attributes['src'] ?? '');
      final fid = _id(RegExp(r'(?:forum-|[?&]fid=)(\d+)', caseSensitive: false), root?.outerHtml ?? '') ?? 0;
      final board = _firstText(root, ['.comiis_xznalist_bk a', '.forumname', '.from']);
      final level = _firstText(root, ['.top_lev', '.level']);
      final time = _firstText(root, ['.f_d', '.time', 'time', '.kmtime']);

      seen.add(tid);
      result.add(ThreadItem(
        tid: tid,
        title: title,
        author: author,
        avatar: avatar,
        fid: fid,
        boardName: board,
        level: level,
        time: time,
        subtitle: text.length > title.length ? _trimSubtitle(text, title) : '',
        cover: avatar,
        likeCount: 0,
        replyCount: _numberAfter(text, ['回复', '评论']) ?? 0,
        viewCount: _numberAfter(text, ['浏览', '查看']) ?? 0,
      ));
      if (result.length >= 50) break;
    }
    return result;
  }

  Future<List<ForumCategory>> fetchBoards() async {
    final doc = parser.parse(await _get('${_base}forum.php?forumlist=1&mobile=2'));
    final boards = <int, ForumBoard>{};
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      final fid = _id(RegExp(r'(?:forum-|[?&]fid=)(\d+)', caseSensitive: false), href);
      if (fid == null || fid == 0) continue;
      var name = _clean(a.text);
      if (name.isEmpty) name = _clean(a.querySelector('span')?.text ?? '');
      if (!_validBoardName(name)) {
        final parent = _container(a);
        name = _clean(parent?.querySelector('span')?.text ?? parent?.text ?? '');
      }
      if (!_validBoardName(name)) continue;
      final img = a.querySelector('img') ?? _container(a)?.querySelector('img');
      final today = _firstText(_container(a), ['p', '.today', '.num']);
      boards.putIfAbsent(fid, () => ForumBoard(fid: fid, name: name, icon: _abs(img?.attributes['src'] ?? ''), today: today));
    }
    if (boards.isEmpty) throw Exception('未解析到版块数据');
    return [ForumCategory(name: '全部版块', boards: boards.values.toList())];
  }

  dom.Element? _container(dom.Element e) {
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

  static String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _validTitle(String value) {
    if (value.length < 2 || value.length > 300) return false;
    const bad = {'返回', '首页', '登录', '注册', '下一页', '上一页', '查看更多', '查看全部'};
    return !bad.contains(value);
  }

  static bool _validBoardName(String value) {
    if (value.length < 2 || value.length > 60) return false;
    const bad = {'首页', '登录', '注册', '论坛', '返回', '更多', '版块'};
    return !bad.contains(value) && !value.contains('http');
  }

  static String _firstText(dom.Element? root, List<String> selectors) {
    if (root == null) return '';
    for (final selector in selectors) {
      final text = _clean(root.querySelector(selector)?.text ?? '');
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _trimSubtitle(String text, String title) {
    final value = text.replaceFirst(title, '').trim();
    return value.length > 160 ? value.substring(0, 160) : value;
  }

  static int? _numberAfter(String text, List<String> keys) {
    for (final key in keys) {
      final match = RegExp('$key\\s*[:：]?\\s*(\\d+)').firstMatch(text);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static int? _id(RegExp regex, String value) {
    final match = regex.firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String _abs(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:$value';
    return _base + value.replaceFirst(RegExp(r'^\./'), '');
  }
}
