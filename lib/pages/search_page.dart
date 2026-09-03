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

  /// xunsearch 每页结果数与最多拉取页数。
  static const int _perPage = 10;
  static const int _maxPages = 7;

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

  /// 源论坛搜索实际由 xunsearch 插件提供, 直接请求插件页拿到稳定的
  /// `<dl class="result-list">` 结果, 不再走 Discuz 原生 search.php 表单流程
  /// (该流程会经 searchid 多次跳转, 元信息解析不可靠)。
  Uri _xunsearchUrl(String keyword, int page) =>
      Uri.parse(SiteConfig.resolve('plugin.php')).replace(queryParameters: {
        'id': 'twpx_xunsearch',
        'mod': 'forum',
        'q': keyword,
        'f': '_all',
        's': 'relevance',
        'syn': 'yes',
        'p': '$page',
      });

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
      final results = await _fetchAllPages(client, keyword, cookie);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        if (results.isEmpty) _error = '没有找到相关帖子';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<List<ThreadItem>> _fetchAllPages(
    dynamic client,
    String keyword,
    String? cookie,
  ) async {
    final results = <ThreadItem>[];
    final seen = <int>{};
    for (var page = 1; page <= _maxPages; page++) {
      final response = await NetClient.retry(
        () => client
            .get(_xunsearchUrl(keyword, page),
                headers: _headers(cookie, referer: SiteConfig.base))
            .timeout(NetClient.timeout),
        times: 2,
      );
      if (response.statusCode != 200) break;
      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      _removeNoise(doc);
      final items = _parseXunsearch(doc);
      if (items.isEmpty) break;
      for (final item in items) {
        if (seen.add(item.tid)) results.add(item);
      }
      if (items.length < _perPage) break;
    }
    return results;
  }

  /// 解析 xunsearch 搜索结果模板:
  /// `<dl class="result-list">` 下按 `<dt>`(标题) / `<dd>`(摘要+元信息) 严格交替排列。
  List<ThreadItem> _parseXunsearch(dynamic doc) {
    final dts = doc.querySelectorAll('dl.result-list > dt');
    final dds = doc.querySelectorAll('dl.result-list > dd');
    final list = <ThreadItem>[];
    final count = dts.length < dds.length ? dts.length : dds.length;
    for (var i = 0; i < count; i++) {
      final a = dts[i].querySelector('a[href]');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'(?:thread-|[?&]tid=)(\d+)', caseSensitive: false).firstMatch(href);
      if (m == null) continue;
      final tid = int.tryParse(m.group(1)!) ?? 0;
      final title = _cleanTitle(a);
      if (tid <= 0 || title.isEmpty) continue;
      final info = _fieldInfo(dds[i]);
      list.add(ThreadItem(
        tid: tid,
        title: title,
        author: info.$1,
        avatar: '',
        fid: info.$2,
        boardName: info.$3,
        level: '',
        time: info.$4,
        subtitle: _summaryFromDd(dds[i], title),
        cover: '',
        likeCount: 0,
        replyCount: 0,
        viewCount: 0,
      ));
    }
    return list;
  }

  /// 从 [container] 的 .field-info 提取 (作者, fid, 版块, 发帖时间)。
  (String, int, String, String) _fieldInfo(dynamic container) {
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
    return (author, fid, board, timeStr);
  }

  /// 摘要: 取 dd 中第一个非 field-info 的 <p> 文本(可能是带高亮的正文片段)。
  String _summaryFromDd(dynamic dd, String title) {
    for (final p in dd.querySelectorAll('p')) {
      if (p.classes.join(' ').contains('field-info')) continue;
      final text = _clean(p.text);
      if (text.isNotEmpty && text != title) {
        return text.length > 180 ? text.substring(0, 180) : text;
      }
    }
    return '';
  }

  void _removeNoise(dynamic doc) {
    for (final node in doc.querySelectorAll('script,style,noscript,template,iframe')) {
      node.remove();
    }
  }

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