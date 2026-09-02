import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 解析 Discuz/Comiis 的真实楼层 PID，并读取楼中楼。
class CommentReplyResolver {
  CommentReplyResolver._();
  static final instance = CommentReplyResolver._();

  static String get _base => SiteConfig.base;

  Map<String, String> _headers({String? referer}) => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
        if ((AuthService.instance.authCookie ?? '').isNotEmpty)
          'Cookie': AuthService.instance.authCookie!,
      };

  Future<String> _fetchThreadHtml(int tid) async {
    if (tid <= 0) return '';
    final client = await NetClient.instance.client;
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final urls = <Uri>[
      Uri.parse('${_base}forum.php').replace(queryParameters: {
        'mod': 'viewthread',
        'tid': '$tid',
        'page': '1',
        '_ycoo_reply_page': stamp,
      }),
      Uri.parse('${_base}thread-$tid-1-1.html').replace(queryParameters: {
        '_ycoo_reply_page': stamp,
      }),
    ];
    for (final uri in urls) {
      try {
        final response = await NetClient.retry(
          () => client.get(uri, headers: _headers(referer: _base)).timeout(NetClient.timeout),
        );
        if (response.statusCode == 200) {
          final html = NetClient.decode(response.bodyBytes);
          if (html.isNotEmpty) return html;
        }
      } catch (_) {}
    }
    return '';
  }

  Future<int> resolvePid({
    required int tid,
    required int commentIndex,
    String author = '',
    String floor = '',
  }) async {
    if (tid <= 0 || commentIndex < 0) return 0;
    final html = await _fetchThreadHtml(tid);
    if (html.isEmpty) return 0;

    final doc = parser.parse(html);
    final posts = _collectPosts(doc);
    if (posts.isEmpty) return 0;

    final normalizedAuthor = _normalize(author);
    final floorNumber = _firstInt(floor);

    if (floorNumber != null || normalizedAuthor.isNotEmpty) {
      for (final post in posts) {
        final pid = _postPid(post);
        if (pid <= 0) continue;
        final postAuthor = _normalize(_postAuthor(post));
        final postFloor = _postFloor(post);
        final authorMatches = normalizedAuthor.isEmpty || postAuthor == normalizedAuthor;
        final floorMatches = floorNumber == null || postFloor == floorNumber;
        if (authorMatches && floorMatches) return pid;
      }
    }

    final candidates = posts.where((p) => _postPid(p) > 0).toList();
    if (commentIndex < candidates.length) return _postPid(candidates[commentIndex]);
    return 0;
  }

  List<dom.Element> _collectPosts(dom.Document doc) {
    final result = <dom.Element>[];
    final seen = <int>{};
    for (final selector in [
      '#postlist > div[id^="post_"]',
      '.comiis_postli',
      '#postlist .plhin',
      '#postlist .plc',
      'div[id^="postmessage_"]',
    ]) {
      for (final post in doc.querySelectorAll(selector)) {
        final pid = _postPid(post);
        if (pid > 0) {
          if (seen.add(pid)) result.add(post);
        } else if (!result.contains(post)) {
          result.add(post);
        }
      }
    }
    return result;
  }

  String _postAuthor(dom.Element post) {
    for (final selector in [
      '.top_user',
      '.authi .xw1',
      '.authi a',
      'a[href*="uid="]',
    ]) {
      final node = post.querySelector(selector);
      final text = node?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  int? _postFloor(dom.Element post) {
    for (final selector in [
      '.f_d.y',
      '.pi .authi em',
      '.pls .authi em',
    ]) {
      final node = post.querySelector(selector);
      final number = _firstInt(node?.text ?? '');
      if (number != null) return number;
    }
    final match = RegExp(r'(\d+)\s*#').firstMatch(post.text.replaceAll(RegExp(r'\s+'), ' '));
    return int.tryParse(match?.group(1) ?? '');
  }

  Future<String> fetchReplies({required int tid, required int pid}) async {
    if (tid <= 0 || pid <= 0) return '';
    final client = await NetClient.instance.client;
    final baseParams = <String, String>{
      'id': 'replyfloor:index',
      'tid': '$tid',
      'pid': '$pid',
      'inajax': '1',
      'page': '1',
    };

    final urls = <Uri>[
      Uri.parse('${_base}plugin.php').replace(queryParameters: {
        ...baseParams,
        '_ycoo_replyfloor': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
      Uri.parse('${_base}plugin.php').replace(queryParameters: baseParams),
    ];

    for (final uri in urls) {
      try {
        final response = await NetClient.retry(
          () => client.get(uri, headers: _headers(referer: '${_base}thread-$tid-1-1.html')).timeout(NetClient.timeout),
        );
        if (response.statusCode != 200) continue;
        final body = NetClient.decode(response.bodyBytes).trim();
        final parsed = _unwrapReplyResponse(body);
        if (_containsReplyNode(parsed)) return parsed;
      } catch (_) {}
    }

    final html = await _fetchThreadHtml(tid);
    if (html.isNotEmpty) {
      final doc = parser.parse(html);
      final post = _findPostByPid(doc, pid);
      if (post != null) {
        final nested = _extractNestedReplyHtml(post);
        if (nested.isNotEmpty) return nested;
      }
    }
    return '';
  }

  String _unwrapReplyResponse(String body) {
    if (body.isEmpty) return '';
    var raw = body;
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(raw);
    if (cdata != null) raw = (cdata.group(1) ?? '').trim();

    final xmlDoc = parser.parse(raw);
    for (final selector in ['root', 'message', 'body']) {
      final node = xmlDoc.querySelector(selector);
      if (node != null && node.innerHtml.trim().isNotEmpty) raw = node.innerHtml.trim();
    }

    raw = raw
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    return raw.trim();
  }

  bool _containsReplyNode(String html) {
    if (html.trim().isEmpty) return false;
    final doc = parser.parseFragment(html);
    return doc.querySelector(
          '.replyfloor_box, .replyfloor_content, .replyfloor_content_ul, '
          '.replyfloor_content_li, li.replyfloor_li, .replyfloor_reply, .replyfloor_item',
        ) !=
        null;
  }

  dom.Element? _findPostByPid(dom.Document doc, int pid) {
    for (final selector in [
      '#post_$pid',
      '#postmessage_$pid',
      '[data-pid="$pid"]',
      '[data-post-id="$pid"]',
    ]) {
      final node = doc.querySelector(selector);
      if (node != null) return node;
    }
    for (final post in _collectPosts(doc)) {
      if (_postPid(post) == pid) return post;
    }
    return null;
  }

  String _extractNestedReplyHtml(dom.Element post) {
    final roots = <dom.Element>[];
    for (final selector in [
      '.replyfloor_box',
      '.replyfloor_content',
      '.replyfloor_content_ul',
      '[class*="replyfloor"]',
      '[id*="replyfloor"]',
      '[class*="reply_floor"]',
      '[id*="reply_floor"]',
      '[class*="replybox"]',
      '[id*="replybox"]',
    ]) {
      for (final node in post.querySelectorAll(selector)) {
        if (!roots.contains(node)) roots.add(node);
      }
    }
    if (roots.isEmpty) return '';
    return roots.map((e) => e.outerHtml).join();
  }

  static int _postPid(dom.Element post) {
    const attrs = ['data-pid', 'data-post-id', 'data-id', 'pid'];
    for (final key in attrs) {
      final value = post.attributes[key];
      final pid = int.tryParse(value ?? '');
      if (pid != null && pid > 0) return pid;
    }
    final values = <String>[post.id, post.attributes['name'] ?? ''];
    for (final value in values) {
      final match = RegExp(r'(?:post_|pid)(\d+)', caseSensitive: false).firstMatch(value);
      final pid = int.tryParse(match?.group(1) ?? '');
      if (pid != null && pid > 0) return pid;
    }
    return 0;
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  static int? _firstInt(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }
}
