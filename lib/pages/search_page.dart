import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import '../services/auth_service.dart';
import '../services/net_client.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  List<ThreadItem> _results = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Map<String, String> _headers(String? cookie, {String? referer}) => {
    'User-Agent': NetClient.ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache, no-store',
    'Pragma': 'no-cache',
    'Referer': ?referer,
    if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
  };

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      await AuthService.instance.init();
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie;
      final searchUri = Uri.parse('https://www.ycoo.net/search.php')
          .replace(queryParameters: {'mod': 'forum', 'mobile': '2'});

      final formResponse = await NetClient.retry(
        () => client
            .get(searchUri, headers: _headers(cookie))
            .timeout(NetClient.timeout),
        times: 3,
      );
      if (formResponse.statusCode != 200) {
        throw Exception('搜索页面 HTTP ${formResponse.statusCode}');
      }

      final formHtml = NetClient.decode(formResponse.bodyBytes);
      final formDoc = parser.parse(formHtml);
      _removeNoise(formDoc);
      final formhash =
          _firstValue(formDoc, 'formhash') ?? _extractFormhash(formHtml);
      final action = _searchAction(formDoc) ?? searchUri;

      // 某些移动模板把搜索表单放到脚本/异步区域，直接使用带关键词的 GET 作为兜底。
      if (formhash == null || formhash.isEmpty) {
        final fallback = await _searchGet(client, keyword, cookie, searchUri);
        if (fallback.isNotEmpty) {
          if (mounted)
            setState(() {
              _results = fallback;
              _loading = false;
            });
          return;
        }
        if (_looksLikeLogin(formHtml)) throw Exception('当前登录状态已失效，请重新登录论坛');
        throw Exception('搜索页面暂时未提供有效搜索令牌，请稍后重试');
      }

      final fields = <String, String>{
        'formhash': formhash,
        'srchtxt': keyword,
        'searchsubmit': 'yes',
        'mod': 'forum',
        'mobile': '2',
      };

      final response = await NetClient.retry(
        () => client
            .post(
              action,
              headers: {
                ..._headers(cookie, referer: searchUri.toString()),
                'Content-Type':
                    'application/x-www-form-urlencoded; charset=UTF-8',
                'Origin': 'https://www.ycoo.net',
              },
              body: fields,
            )
            .timeout(NetClient.timeout),
        times: 3,
      );
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw Exception('搜索请求 HTTP ${response.statusCode}');
      }

      var html = NetClient.decode(response.bodyBytes);
      var doc = parser.parse(html);
      _removeNoise(doc);
      var list = _parseResults(doc);

      // 部分 Discuz 模板会把 POST 搜索结果再跳转到带参数的 GET 页面。
      // 如果 POST 没拿到帖子，直接请求最终搜索 URL。
      if (list.isEmpty) {
        final fallback = await _searchGet(client, keyword, cookie, searchUri);
        if (fallback.isNotEmpty) list = fallback;
      }

      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        if (list.isEmpty) _error = '没有找到相关帖子';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<List<ThreadItem>> _searchGet(
    dynamic client,
    String keyword,
    String? cookie,
    Uri searchUri,
  ) async {
    final urls = <Uri>[
      searchUri.replace(
        queryParameters: {
          'mod': 'forum',
          'mobile': '2',
          'searchsubmit': 'yes',
          'srchtxt': keyword,
        },
      ),
      searchUri.replace(queryParameters: {'mod': 'forum', 'srchtxt': keyword}),
    ];
    for (final uri in urls) {
      try {
        final response = await NetClient.retry(
          () => client
              .get(
                uri,
                headers: _headers(cookie, referer: searchUri.toString()),
              )
              .timeout(NetClient.timeout),
          times: 2,
        );
        if (response.statusCode != 200) continue;
        final doc = parser.parse(NetClient.decode(response.bodyBytes));
        _removeNoise(doc);
        final list = _parseResults(doc);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return const [];
  }

  List<ThreadItem> _parseResults(dynamic doc) {
    final seen = <int>{};
    final list = <ThreadItem>[];
    final selectors = <String>[
      '.pbm li',
      '.comiis_searchlist li',
      '.search_list li',
      '.sclist li',
      'li',
      'tr',
      '.threadlist li',
    ];

    for (final selector in selectors) {
      for (final node in doc.querySelectorAll(selector)) {
        for (final a in node.querySelectorAll('a[href]')) {
          final item = _itemFromAnchor(a, node, seen);
          if (item != null) list.add(item);
          if (list.length >= 50) return list;
        }
      }
      if (list.isNotEmpty) return list;
    }

    for (final a in doc.querySelectorAll('a[href]')) {
      final item = _itemFromAnchor(a, a.parent, seen);
      if (item != null) list.add(item);
      if (list.length >= 50) break;
    }
    return list;
  }

  ThreadItem? _itemFromAnchor(dynamic a, dynamic parent, Set<int> seen) {
    final href = a.attributes['href'] ?? '';
    final match = RegExp(
      r'(?:thread-|[?&]tid=)(\d+)',
      caseSensitive: false,
    ).firstMatch(href);
    if (match == null) return null;
    final tid = int.tryParse(match.group(1)!) ?? 0;
    final title = _clean(a.text);
    if (tid <= 0 ||
        title.length < 2 ||
        !seen.add(tid) ||
        _navigationTitle(title))
      return null;
    final parentText = _clean(parent?.text ?? '');
    final boardHref = RegExp(
      r'(?:forum-|[?&]fid=)(\d+)',
      caseSensitive: false,
    ).firstMatch(parent?.outerHtml ?? '')?.group(1);
    return ThreadItem(
      tid: tid,
      title: title,
      author: '',
      avatar: '',
      fid: int.tryParse(boardHref ?? '') ?? 0,
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
    );
  }

  String? _firstValue(dynamic doc, String name) {
    for (final input in doc.querySelectorAll('input[name="$name"]')) {
      final value = input.attributes['value']?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _extractFormhash(String html) {
    final patterns = <RegExp>[
      RegExp(
        r'''<input\b[^>]*name=["']formhash["'][^>]*value=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<input\b[^>]*value=["']([^"']+)["'][^>]*name=["']formhash["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:formhash|formHash)\s*[:=]\s*["']([A-Za-z0-9]+)["']''',
        caseSensitive: false,
      ),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      if (m != null && m.group(1)!.trim().isNotEmpty) return m.group(1)!.trim();
    }
    return null;
  }

  Uri? _searchAction(dynamic doc) {
    for (final form in doc.querySelectorAll('form')) {
      final action = form.attributes['action'] ?? '';
      final text = _clean(form.text);
      if (action.contains('search.php') || text.contains('搜索')) {
        if (action.isEmpty)
          return Uri.parse(
            'https://www.ycoo.net/search.php?mod=forum&mobile=2',
          );
        if (action.startsWith('http')) return Uri.parse(action);
        return Uri.parse(
          'https://www.ycoo.net/$action'.replaceFirst(
            'https://www.ycoo.net//',
            'https://www.ycoo.net/',
          ),
        );
      }
    }
    return null;
  }

  void _removeNoise(dynamic doc) {
    for (final node in doc.querySelectorAll(
      'script,style,noscript,template,iframe',
    )) {
      node.remove();
    }
  }

  bool _looksLikeLogin(String html) {
    final text = _clean(parser.parse(html).body?.text ?? '');
    return RegExp(r'(用户名|登录密码)').hasMatch(text) &&
        text.contains('登录') &&
        !html.contains('action=logout');
  }

  bool _navigationTitle(String text) => const {
    '下一页',
    '上一页',
    '首页',
    '尾页',
    '更多',
    '回复',
    '查看',
    '详情',
    '登录',
    '注册',
    '搜索',
    '高级搜索',
  }.contains(text);

  String _clean(String text) => text
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD□]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('搜索'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _search,
          icon: const Icon(Icons.search),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '输入关键词搜索帖子',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
              ? const Center(child: Text('输入关键词开始搜索'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final item = _results[i];
                    return Card(
                      child: ListTile(
                        title: Text(item.title),
                        subtitle: item.subtitle.isEmpty
                            ? null
                            : Text(
                                item.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DetailPage(tid: item.tid, title: item.title),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
