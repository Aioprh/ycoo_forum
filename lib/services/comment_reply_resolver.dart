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

  Future<String> _fetchThreadHtml(int tid, {int page = 1}) async {
    if (tid <= 0) return '';
    final client = await NetClient.instance.client;
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final p = page < 1 ? 1 : page;
    final urls = <Uri>[
      Uri.parse('${_base}forum.php').replace(queryParameters: {
        'mod': 'viewthread', 'tid': '$tid', 'page': '$p', '_ycoo_reply_page': stamp,
      }),
      Uri.parse('${_base}thread-$tid-$p-1.html').replace(queryParameters: {
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
    int page = 1,
    String author = '',
    String floor = '',
  }) async {
    if (tid <= 0 || commentIndex < 0) return 0;
    final html = await _fetchThreadHtml(tid, page: page);
    if (html.isEmpty) return 0;
    final posts = _collectPosts(parser.parse(html));
    if (posts.isEmpty) return 0;
    final wantedAuthor = _normalize(author);
    final wantedFloor = _firstInt(floor);
    if (wantedAuthor.isNotEmpty || wantedFloor != null) {
      for (final post in posts) {
        final pid = _postPid(post);
        if (pid <= 0) continue;
        final authorOk = wantedAuthor.isEmpty || _normalize(_postAuthor(post)) == wantedAuthor;
        final floorOk = wantedFloor == null || _postFloor(post) == wantedFloor;
        if (authorOk && floorOk) return pid;
      }
    }
    final candidates = posts.where((post) => _postPid(post) > 0).toList();
    return commentIndex < candidates.length ? _postPid(candidates[commentIndex]) : 0;
  }

  List<dom.Element> _collectPosts(dom.Document doc) {
    final result = <dom.Element>[];
    final seen = <int>{};
    for (final selector in [
      '#postlist > div[id^="post_"]', '.comiis_postli', '#postlist .plhin',
      '#postlist .plc', 'div[id^="postmessage_"]',
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
    for (final selector in ['.top_user', '.authi .xw1', '.authi a', 'a[href*="uid="]']) {
      final node = post.querySelector(selector);
      final text = node?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  int? _postFloor(dom.Element post) {
    for (final selector in ['.f_d.y', '.pi .authi em', '.pls .authi em']) {
      final number = _firstInt(post.querySelector(selector)?.text ?? '');
      if (number != null) return number;
    }
    final match = RegExp(r'(\d+)\s*#').firstMatch(post.text.replaceAll(RegExp(r'\s+'), ' '));
    return int.tryParse(match?.group(1) ?? '');
  }

  /// 拉取指定父楼 pid 的全部楼中楼，自动翻页拼接。
  ///
  /// replyfloor 插件接口按 ~5 条/页分页，且第 1 页底部有一个
  /// `div.replyfloor_content_showmore`(含 rel=...page=N 的"更多 N 条回复"链接)。
  /// 如果软件端只请求 page=1，则用户在后面的页写下的新回复永远拉不到，
  /// 即使刷新/重进也无效。这里必须逐页抓取并合并所有 li，网页端能看到的回复
  /// 软件端才能看到。
  Future<String> fetchReplies({required int tid, required int pid}) async {
    if (tid <= 0 || pid <= 0) return '';
    final client = await NetClient.instance.client;
    final mergedUl = <String>[];
    const maxPages = 50;
    for (var page = 1; page <= maxPages; page++) {
      final params = <String, String>{
        'id': 'replyfloor:index', 'tid': '$tid', 'pid': '$pid',
        'inajax': '1', 'page': '$page',
      };
      final urls = <Uri>[
        Uri.parse('${_base}plugin.php').replace(queryParameters: {
          ...params, '_ycoo_replyfloor': DateTime.now().millisecondsSinceEpoch.toString(),
        }),
        Uri.parse('${_base}plugin.php').replace(queryParameters: params),
      ];
      String? pageHtml;
      for (final uri in urls) {
        if (pageHtml != null) break;
        try {
          final response = await NetClient.retry(
            () => client.get(uri, headers: _headers(referer: '${_base}thread-$tid-1-1.html')).timeout(NetClient.timeout),
          );
          if (response.statusCode == 200) {
            pageHtml = _unwrapReplyResponse(NetClient.decode(response.bodyBytes).trim());
          }
        } catch (_) {}
      }
      if (pageHtml == null || pageHtml.trim().isEmpty) break;
      if (!_containsReplyNode(pageHtml)) {
        // 没有任何楼中楼(第 1 页即空)。
        if (page == 1) return '';
        break;
      }
      final liDoc = parser.parseFragment(pageHtml);
      final lis = <dom.Element>[];
      for (final selector in [
        '.replyfloor_content_ul > .replyfloor_content_li',
        '.replyfloor_content_ul > li', '.replyfloor_content_li',
        'li.replyfloor_li', '.replyfloor_box li', 'li[id*="replyfloor_content_li"]',
      ]) {
        for (final li in liDoc.querySelectorAll(selector)) {
          if (li.querySelector('div[class*="replyfloor_content_li"]') != null) continue;
          if (!lis.contains(li)) lis.add(li);
        }
      }
      // 当前页能抽取到具体 li 才拼接；否则交回携分页标记的原始 HTML 缓存。
      if (lis.isNotEmpty) {
        for (final li in lis) {
          // 保留 li 的 id(如 replyfloor_content_li_20606)与全部属性，
          // 因为 _extractReplyPid / _parseReplies 依赖 id 后缀提取该条回复的 PID。
          mergedUl.add(li.outerHtml);
        }
      }
      // 判断是否还有后续页：存在 rel=...page=N 的"更多回复"链接或 replyfloor 分页器。
      final hasMore = pageHtml.contains('replyfloor_content_showmore') &&
          pageHtml.contains('class="replyfloor_content_more"');
      final nextPageMatch = hasMore
          ? RegExp(r'replyfloor_content_showmore[^>]*rel\s*=\s*"([^"]*)"').firstMatch(pageHtml)
          : null;
      if (nextPageMatch != null) {
        final pageParam = RegExp(r'[?&]page=(\d+)').firstMatch(nextPageMatch.group(1)!);
        final next = int.tryParse(pageParam?.group(1) ?? '');
        // 服务器页码可能跳跃，用 rel 里的真实页码直接推进。
        if (next != null && next > page) {
          page = next - 1; // for 循环尾部 +1 后跳到 next
          continue;
        }
      }
      // 没有明确的下一页页码 => 无法安全继续，终止。
      break;
    }

    final combined = mergedUl.isEmpty
        ? ''
        : '<div class="replyfloor_content_ul">${mergedUl.join()}</div>';
    if (combined.isNotEmpty) return _normalizeReplyPidHtml(combined);

    // 接口逐页拉取失败时，回退到从完整帖子页提取全部楼中楼。
    final html = await _fetchThreadHtml(tid);
    if (html.isNotEmpty) {
      final doc = parser.parse(html);
      final post = _findPostByPid(doc, pid);
      if (post != null) {
        final nested = _extractNestedReplyHtml(post);
        // 回退提取到的必须是"真正含回复条目 li"的内容; 若只是空外壳
        // (replyfloor_box 等固定渲染容器)则视为无回复, 返回空。
        if (nested.isNotEmpty && _containsReplyNode(nested)) {
          return _normalizeReplyPidHtml(nested);
        }
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
    return raw.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'").replaceAll('&amp;', '&').trim();
  }

  /// 是否真的存在楼中楼回复条目, 而不是只存在 replyfloor 外壳。
  ///
  /// 关键: 无回复的楼层也会有固定渲染的外壳 (.replyfloor_box / .replyfloor_bd /
  /// .replyfloor_content / .replyfloor_content_ul), 只是里面没有回复条目 li。
  /// 入口与内容判据必须以"存在回复条目 li"为准, 绝不能因为外壳存在就当作
  /// 有回复, 否则会让没有楼中楼的楼层也出现空的展开入口。
  bool _containsReplyNode(String html) {
    if (html.trim().isEmpty) return false;
    final doc = parser.parseFragment(html);
    // 1) 标准回复叶子节点
    for (final selector in [
      '.replyfloor_content_li', '.replyfloor_content_ul > li',
      'li.replyfloor_li', 'li[class*="replyfloor_content_li"]',
      'li[id*="replyfloor_content_li"]',
    ]) {
      if (doc.querySelector(selector) != null) return true;
    }
    // 2) 兼容回复条目不是 <li> 而是 <div class="replyfloor_content_li"> 的情况
    for (final node in doc.querySelectorAll('*')) {
      final cls = (node.attributes['class'] ?? '').toLowerCase();
      final id = (node.attributes['id'] ?? '').toLowerCase();
      if (cls.contains('replyfloor_content_li') || id.contains('replyfloor_content_li')) {
        return true;
      }
    }
    // 3) 回复条目兜底: 非空的 texts, 排除纯外壳/按钮/分页器
    for (final selector in [
      '.replyfloor_reply', '.replyfloor_item', '.replyfloor_content_user',
      '.replyfloor_content_text', '.replyfloor_msg', '.replyfloor_message',
      '.replyfloor_content_main', '.replyfloor_content_avatar',
    ]) {
      final node = doc.querySelector(selector);
      if (node != null && node.text.trim().isNotEmpty) return true;
    }
    return false;
  }

  /// Comiis 不同手机版样式会把目标 PID 放在 href、onclick、data-*、rel、
  /// title 或其他自定义属性中的 repquote。这里扫描每个元素的全部属性，
  /// 并同时绑定按钮、最近回复 li，避免 Flutter 层拿到 0。
  String _normalizeReplyPidHtml(String html) {
    if (html.trim().isEmpty) return html;
    final doc = parser.parseFragment(html);

    int? extractRepquote(String raw) {
      if (raw.isEmpty) return null;
      for (final pattern in <RegExp>[
        RegExp(r'(?:[?&]|%3F|%26|&amp;)repquote(?:=|%3D)(\d+)', caseSensitive: false),
        RegExp(r'''\brepquote\s*[:=]\s*["']?(\d+)''', caseSensitive: false),
        RegExp(r'\brepquote[^0-9]{0,30}(\d+)', caseSensitive: false),
        RegExp(r'''replyfloor_reply\s*\(\s*["']?(\d+)''', caseSensitive: false),
        // Comiis mobile: li id="replyfloor_content_li_<PID>" 后缀即该条楼中楼回复的 PID
        RegExp(r'replyfloor_content_li_(\d+)', caseSensitive: false),
        // Comiis mobile: 按钮 onclick="replyfloor_editor('<postPid>', <PID>, ...)" / report('<postPid>', <PID>)，
        // 第二个整型参数即该条楼中楼回复的 PID
        RegExp(r'''replyfloor_(?:editor|report)\s*\(\s*["']?\d+["']?\s*,\s*["']?(\d+)''', caseSensitive: false),
      ]) {
        final match = pattern.firstMatch(raw);
        final value = int.tryParse(match?.group(1) ?? '');
        if (value != null && value > 0) return value;
      }
      return null;
    }

    bool replyLike(dom.Element e) {
      if (e.localName == 'li') return true;
      final cls = (e.attributes['class'] ?? '').toLowerCase();
      final id = (e.attributes['id'] ?? '').toLowerCase();
      return cls.contains('replyfloor') || cls.contains('reply_floor') ||
          id.contains('replyfloor') || id.contains('reply_floor');
    }

    void bind(dom.Element element, int pid) {
      element.attributes['data-pid'] = '$pid';
      dom.Element? current = element.parent;
      var depth = 0;
      while (current != null && depth++ < 20) {
        if (replyLike(current)) {
          current.attributes['data-pid'] = '$pid';
          if (current.localName == 'li') break;
        }
        current = current.parent;
      }
    }

    // 不再限定属性名：只要任意属性值里出现 repquote=PID 就绑定。
    for (final element in doc.querySelectorAll('*')) {
      int? pid;
      for (final value in element.attributes.values) {
        pid = extractRepquote(value);
        if (pid != null) break;
      }
      if (pid != null && pid > 0) bind(element, pid);
    }

    // 如果按钮不在标准 li 内，再从标准楼中楼节点的全部后代属性补一次。
    final selectors = <String>[
      '.replyfloor_content_ul > .replyfloor_content_li', '.replyfloor_content_ul > li',
      '.replyfloor_content_li', '.replyfloor_content li', 'li.replyfloor_li',
      '.replyfloor_box li', '.replyfloor_reply', '.replyfloor_item',
      'li[class*="replyfloor"]', 'li[id*="replyfloor"]',
    ];
    final nodes = <dom.Element>[];
    for (final selector in selectors) {
      for (final node in doc.querySelectorAll(selector)) {
        if (!nodes.contains(node)) nodes.add(node);
      }
    }
    for (final node in nodes) {
      if ((node.attributes['data-pid'] ?? '').isNotEmpty) continue;
      for (final child in node.querySelectorAll('*')) {
        for (final value in child.attributes.values) {
          final pid = extractRepquote(value);
          if (pid != null && pid > 0) {
            node.attributes['data-pid'] = '$pid';
            break;
          }
        }
        if ((node.attributes['data-pid'] ?? '').isNotEmpty) break;
      }
    }

    return doc.nodes.map((node) => node is dom.Element ? node.outerHtml : node.text).join();
  }

  dom.Element? _findPostByPid(dom.Document doc, int pid) {
    for (final selector in ['#post_$pid', '#postmessage_$pid', '[data-pid="$pid"]', '[data-post-id="$pid"]']) {
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
      '.replyfloor_box', '.replyfloor_content', '.replyfloor_content_ul',
      '[class*="replyfloor"]', '[id*="replyfloor"]', '[class*="reply_floor"]',
      '[id*="reply_floor"]', '[class*="replybox"]', '[id*="replybox"]',
    ]) {
      for (final node in post.querySelectorAll(selector)) {
        if (!roots.contains(node)) roots.add(node);
      }
    }
    return roots.map((node) => node.outerHtml).join();
  }

  static int _postPid(dom.Element post) {
    for (final key in ['data-pid', 'data-post-id', 'data-id', 'pid']) {
      final pid = int.tryParse(post.attributes[key] ?? '');
      if (pid != null && pid > 0) return pid;
    }
    for (final value in [post.id, post.attributes['name'] ?? '']) {
      final match = RegExp(r'(?:post_|pid)(\d+)', caseSensitive: false).firstMatch(value);
      final pid = int.tryParse(match?.group(1) ?? '');
      if (pid != null && pid > 0) return pid;
    }
    return 0;
  }

  static String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  static int? _firstInt(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }
}
