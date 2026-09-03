import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../models/thread_item.dart';
import '../services/site_config.dart';
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
    if (referer != null) 'Referer': referer,
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
      final searchUri = Uri.parse(SiteConfig.resolve('search.php')).replace(
        queryParameters: {'mod': 'forum', 'mobile': '2'},
      );

      final formResponse = await NetClient.retry(
        () => client.get(searchUri, headers: _headers(cookie)).timeout(NetClient.timeout),
        times: 3,
      );
      if (formResponse.statusCode != 200) {
        throw Exception('搜索页面 HTTP ${formResponse.statusCode}');
      }

      final formHtml = NetClient.decode(formResponse.bodyBytes);
      final formDoc = parser.parse(formHtml);
      _removeNoise(formDoc);
      final formhash = _firstValue(formDoc, 'formhash') ?? _extractFormhash(formHtml);
      final action = _searchAction(formDoc) ?? searchUri;

      // 某些移动模板把搜索表单放到脚本/异步区域，直接使用带关键词的 GET 作为兜底。
      if (formhash == null || formhash.isEmpty) {
        final fallback = await _searchGet(client, keyword, cookie, searchUri);
        if (fallback.isNotEmpty) {
          if (mounted) setState(() { _results = fallback; _loading = false; });
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
        () => client.post(
          action,
          headers: {
            ..._headers(cookie, referer: searchUri.toString()),
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Origin': SiteConfig.base.replaceFirst(RegExp(r'/$'), ''),
          },
          body: fields,
        ).timeout(NetClient.timeout),
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
      searchUri.replace(queryParameters: {
        'mod': 'forum',
        'mobile': '2',
        'searchsubmit': 'yes',
        'srchtxt': keyword,
      }),
      searchUri.replace(queryParameters: {
        'mod': 'forum',
        'srchtxt': keyword,
      }),
    ];
    for (final uri in urls) {
      try {
        final response = await NetClient.retry(
          () => client.get(uri, headers: _headers(cookie, referer: searchUri.toString())).timeout(NetClient.timeout),
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
      '.pbm li', '.comiis_searchlist li', '.search_list li', '.sclist li',
      'li', 'tr', '.threadlist li',
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
    final match = RegExp(r'(?:thread-|[?&]tid=)(\d+)', caseSensitive: false).firstMatch(href);
    if (match == null) return null;
    final tid = int.tryParse(match.group(1)!) ?? 0;
    final title = _cleanTitle(a);
    if (tid <= 0 || title.length < 2 || !seen.add(tid) || _navigationTitle(title)) return null;

    // 循父向上定位承载"发帖时间/作者/版块"的条目容器 (xunsearch 模板为 <dl>,
    // 元信息在 <p class="field-info"> 里)。取不到就保持空, 不破坏其它搜索模板。
    var container = parent;
    for (var depth = 0; depth < 8 && container != null; depth++) {
      if (container.querySelector('.field-info') != null) break;
      container = container.parent;
    }
    var author = '', timeStr = '', board = '';
    var fid = 0;
    final fieldInfo = container?.querySelector('.field-info');
    if (fieldInfo != null) {
      for (final span in fieldInfo.querySelectorAll('span')) {
        final strong = span.querySelector('strong');
        final label = strong?.text ?? '';
        var txt = _clean(span.text);
        if (strong != null) txt = _clean(span.text.replaceFirst(strong.text, ''));
        if (label.contains('时间')) {
          timeStr = txt.replaceAll('发帖时间:', '').trim();
        } else if (label.contains('作者')) {
          author = _clean(span.querySelector('a')?.text ?? '');
          if (author.isEmpty) author = txt;
        } else {
          final boardA = span.querySelector('a[href*="fid="]');
          if (boardA != null) {
            board = _clean(boardA.text);
            final m = RegExp(r'(?:forum-|[?&]fid=)(\d+)', caseSensitive: false)
                .firstMatch(boardA.attributes['href'] ?? '');
            fid = int.tryParse(m?.group(1) ?? '') ?? 0;
          }
        }
      }
    }

    final parentText = _clean((container ?? parent)?.text ?? '');
    final subtitle = parentText == title ? '' : parentText.replaceFirst(title, '').trim();
    return ThreadItem(
      tid: tid,
      title: title,
      author: author,
      avatar: '',
      fid: fid,
      boardName: board,
      level: '',
      time: timeStr,
      subtitle: subtitle,
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
      RegExp(r'''<input\b[^>]*name=["']formhash["'][^>]*value=["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''<input\b[^>]*value=["']([^"']+)["'][^>]*name=["']formhash["']''', caseSensitive: false),
      RegExp(r'''(?:formhash|formHash)\s*[:=]\s*["']([A-Za-z0-9]+)["']''', caseSensitive: false),
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
        if (action.isEmpty) return Uri.parse('${SiteConfig.base}search.php?mod=forum&mobile=2');
        if (action.startsWith('http')) return Uri.parse(action);
        return Uri.parse(SiteConfig.resolve(action));
      }
    }
    return null;
  }

  void _removeNoise(dynamic doc) {
    for (final node in doc.querySelectorAll('script,style,noscript,template,iframe')) {
      node.remove();
    }
  }

  bool _looksLikeLogin(String html) {
    final text = _clean(parser.parse(html).body?.text ?? '');
    return RegExp(r'(用户名|登录密码)').hasMatch(text) && text.contains('登录') && !html.contains('action=logout');
  }

  bool _navigationTitle(String text) => const {
        '下一页','上一页','首页','尾页','更多','回复','查看','详情','登录','注册','搜索','高级搜索'
      }.contains(text);

  Widget _meta(IconData icon, String text) {
    final hint = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: hint),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 11.5, color: hint)),
    ]);
  }

  String _cleanTitle(dynamic a) {
    var text = a.text ?? '';
    if (a.querySelector('h4') != null) {
      // xunsearch 模板: 去掉序号前缀与相关度 <small>[NN%]</small> 噪音。
      text = text.replaceAll(RegExp(r'\s*\[\d+%\]'), '');
      text = text.replaceFirst(RegExp(r'^\s*\d+\s+'), '');
    }
    return _clean(text);
  }

  String _clean(String text) => text
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD□]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('搜索'),
          actions: [IconButton(onPressed: _loading ? null : _search, icon: const Icon(Icons.search))],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '输入关键词搜索帖子',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: _loading ? null : _search, icon: const Icon(Icons.arrow_forward_rounded)),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(leading: const Icon(Icons.error_outline), title: Text(_error!)),
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
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = _results[i];
                          return Card(
                            child: ListTile(
                              title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.subtitle.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ),
                                  if (item.author.isNotEmpty || item.time.isNotEmpty || item.boardName.isNotEmpty)
                                    Wrap(spacing: 12, runSpacing: 4, children: [
                                      if (item.author.isNotEmpty) _meta(Icons.person_outline_outlined, item.author),
                                      if (item.time.isNotEmpty) _meta(Icons.schedule_outlined, item.time),
                                      if (item.boardName.isNotEmpty) _meta(Icons.forum_outlined, item.boardName),
                                    ]),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: item.title))),
                            ),
                          );
                        },
                      ),
          ),
        ]),
      );
}
