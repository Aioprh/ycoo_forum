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

  Map<String, String> _headers(String? cookie) => {
    'User-Agent': NetClient.ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
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
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie;
      final searchUri = Uri.parse('https://www.ycoo.net/search.php').replace(
        queryParameters: {'mod': 'forum'},
      );

      // Discuz 搜索页需要先拿 formhash，再提交搜索表单。
      final formResponse = await NetClient.retry(
        () => client.get(searchUri, headers: _headers(cookie)).timeout(NetClient.timeout),
        times: 2,
      );
      if (formResponse.statusCode != 200) {
        throw Exception('搜索页面 HTTP ${formResponse.statusCode}');
      }

      final formDoc = parser.parse(NetClient.decode(formResponse.bodyBytes));
      final formhash = _firstValue(formDoc, 'formhash');
      final action = _searchAction(formDoc) ?? searchUri;
      if (formhash == null || formhash.isEmpty) {
        throw Exception('搜索页面缺少 formhash，请稍后重试');
      }

      final fields = <String, String>{
        'formhash': formhash,
        'srchtxt': keyword,
        'searchsubmit': 'yes',
        'mod': 'forum',
      };

      final response = await NetClient.retry(
        () => client.post(
          action,
          headers: {
            ..._headers(cookie),
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': searchUri.toString(),
          },
          body: fields,
        ).timeout(NetClient.timeout),
        times: 2,
      );
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw Exception('搜索请求 HTTP ${response.statusCode}');
      }

      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      for (final n in doc.querySelectorAll('script,style,noscript,template')) {
        n.remove();
      }

      final seen = <int>{};
      final list = <ThreadItem>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        final match = RegExp(r'(?:thread-|[?&]tid=)(\d+)').firstMatch(href);
        if (match == null) continue;
        final tid = int.tryParse(match.group(1)!) ?? 0;
        final title = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (tid <= 0 || title.length < 2 || !seen.add(tid)) continue;
        final parent = (a.parent?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        list.add(ThreadItem(
          tid: tid,
          title: title,
          author: '',
          avatar: '',
          fid: 0,
          boardName: '',
          level: '',
          time: '',
          subtitle: parent == title ? '' : parent.replaceFirst(title, '').trim(),
          cover: '',
          likeCount: 0,
          replyCount: 0,
          viewCount: 0,
        ));
        if (list.length >= 50) break;
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

  String? _firstValue(dynamic doc, String name) {
    for (final input in doc.querySelectorAll('input')) {
      if ((input.attributes['name'] ?? '') == name) {
        final value = input.attributes['value']?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Uri? _searchAction(dynamic doc) {
    for (final form in doc.querySelectorAll('form')) {
      final action = form.attributes['action'] ?? '';
      final text = form.text.toLowerCase();
      if (action.contains('search.php') || text.contains('搜索')) {
        if (action.isEmpty) return Uri.parse('https://www.ycoo.net/search.php?mod=forum');
        if (action.startsWith('http')) return Uri.parse(action);
        return Uri.parse('https://www.ycoo.net/$action');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('搜索'),
      actions: [
        IconButton(onPressed: _loading ? null : _search, icon: const Icon(Icons.search)),
      ],
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
                          title: Text(item.title),
                          subtitle: item.subtitle.isEmpty ? null : Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
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
