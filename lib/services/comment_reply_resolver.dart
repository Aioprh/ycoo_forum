import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// Resolves the real Discuz post id for a comment when the normalized
/// native comment card does not contain the original pid attribute.
class CommentReplyResolver {
  CommentReplyResolver._();
  static final instance = CommentReplyResolver._();

  static String get _base => SiteConfig.base;

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
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
    };
    final cookie = AuthService.instance.authCookie;
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;

    final response = await NetClient.retry(
      () => client.get(uri, headers: headers).timeout(NetClient.timeout),
    );
    if (response.statusCode != 200) return 0;

    final doc = parser.parse(NetClient.decode(response.bodyBytes));
    final posts = doc.querySelectorAll(
      '.comiis_postli, #postlist .plhin, #postlist .plc, #postlist > div[id^="post_"], div[id^="postmessage_"]',
    );
    if (posts.isEmpty) return 0;

    // NativeCommentList renders posts.skip(1), so its zero-based comment
    // index maps directly to the second and subsequent server posts.
    final serverIndex = commentIndex + 1;
    if (serverIndex < posts.length) {
      final pid = _postPid(posts[serverIndex]);
      if (pid > 0) return pid;
    }

    // Fallback for pages whose post ordering differs slightly.
    final normalizedAuthor = _normalize(author);
    final floorNumber = _firstInt(floor);
    for (var i = 1; i < posts.length; i++) {
      final post = posts[i];
      final pid = _postPid(post);
      if (pid <= 0) continue;
      final postAuthor = _normalize(post.querySelector('.top_user, .authi .xw1, .authi a')?.text ?? '');
      final postFloor = _firstInt(
        post.querySelector('.f_d.y, .pi .authi em, .pls .authi em')?.text ?? '',
      );
      if (normalizedAuthor.isNotEmpty && postAuthor == normalizedAuthor &&
          (floorNumber == null || postFloor == floorNumber)) {
        return pid;
      }
    }
    return 0;
  }

  static int _postPid(dynamic post) {
    final attrs = <String>['data-pid', 'data-post-id', 'data-id', 'pid'];
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