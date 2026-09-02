import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// Resolves real Discuz post ids and loads the reply-floor plugin's nested replies.
class CommentReplyResolver {
  CommentReplyResolver._();
  static final instance = CommentReplyResolver._();

  static String get _base => SiteConfig.base;

  Map<String, String> _headers() => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if ((AuthService.instance.authCookie ?? '').isNotEmpty)
          'Cookie': AuthService.instance.authCookie!,
      };

  Future<int> resolvePid({
    required int tid,
    required int commentIndex,
    String author = '',
    String floor = '',
  }) async {
    if (tid <= 0 || commentIndex < 0) return 0;
    final client = await NetClient.instance.client;
    final uri = Uri.parse('${_base}thread-$tid-1-1.html').replace(
      queryParameters: {
        'mobile': '2',
        '_ycoo_reply_resolve': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await NetClient.retry(
      () => client.get(uri, headers: _headers()).timeout(NetClient.timeout),
    );
    if (response.statusCode != 200) return 0;

    final doc = parser.parse(NetClient.decode(response.bodyBytes));
    final rawPosts = <dom.Element>[];
    for (final selector in [
      '#postlist > div[id^="post_"]',
      '.comiis_postli',
      '#postlist .plhin',
      '#postlist .plc',
      'div[id^="postmessage_"]',
    ]) {
      for (final post in doc.querySelectorAll(selector)) {
        if (!rawPosts.contains(post)) rawPosts.add(post);
      }
    }

    final posts = <dom.Element>[];
    final seenPids = <int>{};
    for (final post in rawPosts) {
      final pid = _postPid(post);
      if (pid > 0) {
        if (seenPids.add(pid)) posts.add(post);
      } else if (!posts.contains(post)) {
        posts.add(post);
      }
    }
    if (posts.isEmpty) return 0;

    final normalizedAuthor = _normalize(author);
    final floorNumber = _firstInt(floor);

    // Prefer exact floor + author. The forum displays floors such as “10#”.
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
    if (commentIndex >= 0 && commentIndex < candidates.length) {
      return _postPid(candidates[commentIndex]);
    }
    if (commentIndex + 1 < candidates.length) {
      return _postPid(candidates[commentIndex + 1]);
    }
    return 0;
  }

  String _postAuthor(dom.Element post) {
    for (final selector in [
      '.top_user',
      '.authi .xw1',
      '.authi a',
      '.p-author',
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
      '.p-floor',
    ]) {
      final node = post.querySelector(selector);
      final number = _firstInt(node?.text ?? '');
      if (number != null) return number;
    }
    final text = post.text.replaceAll(RegExp(r'\s+'), ' ');
    final match = RegExp(r'(\d+)\s*#').firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  /// Loads the nested replies rendered by the site's replyfloor plugin.
  Future<String> fetchReplies({required int tid, required int pid}) async {
    if (tid <= 0 || pid <= 0) return '';
    final client = await NetClient.instance.client;
    final uri = Uri.parse('${_base}plugin.php').replace(
      queryParameters: {
        'id': 'replyfloor:index',
        'tid': '$tid',
        'pid': '$pid',
        'inajax': '1',
        '_ycoo_replyfloor': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await NetClient.retry(
      () => client.get(uri, headers: _headers()).timeout(NetClient.timeout),
    );
    if (response.statusCode != 200) return '';

    final body = NetClient.decode(response.bodyBytes).trim();
    if (body.isEmpty) return '';

    final document = parser.parse(body);
    final candidates = document.querySelectorAll(
      '.replyfloor_box, .replyfloor_content, .replyfloor_content_ul, li.replyfloor_li',
    );
    if (candidates.isNotEmpty) {
      return candidates.map((e) => e.outerHtml).join();
    }

    final decodedText = (document.body?.text ?? '').trim();
    if (decodedText.contains('replyfloor') || decodedText.contains('回复 举报')) {
      final decoded = parser.parseFragment(decodedText);
      final decodedCandidates = decoded.querySelectorAll(
        '.replyfloor_box, .replyfloor_content, .replyfloor_content_ul, li.replyfloor_li',
      );
      if (decodedCandidates.isNotEmpty) {
        return decodedCandidates.map((e) => e.outerHtml).join();
      }
      return decodedText;
    }

    for (final node in document.querySelectorAll('root, message, body')) {
      final html = node.innerHtml.trim();
      if (html.contains('replyfloor') || html.contains('回复 举报')) return html;
    }
    return body;
  }

  static int _postPid(dom.Element post) {
    const attrs = ['data-pid', 'data-post-id', 'data-id', 'pid'];
    for (final key in attrs) {
      final pid = int.tryParse(post.attributes[key] ?? '');
      if (pid != null && pid > 0) return pid;
    }
    final values = <String>[post.id, post.attributes['name'] ?? ''];
    for (final value in values) {
      final match = RegExp(r'(?:post_|pid)(\d+)', caseSensitive: false).firstMatch(value);
      final pid = int.tryParse(match?.group(1) ?? '');
      if (pid != null && pid > 0) return pid;
    }
    final match = RegExp(
      r'(?:^|[?#&/_-])pid[=_-]?(\d+)',
      caseSensitive: false,
    ).firstMatch(post.outerHtml);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  static int? _firstInt(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }
}
