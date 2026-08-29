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
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie;
      final uri = Uri.parse('https://www.ycoo.net/search.php').replace(queryParameters: {
        'mod': 'forum', 'searchsubmit': 'yes', 'srchtxt': keyword, 'mobile': '2',
      });
      final response = await client.get(uri, headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      for (final n in doc.querySelectorAll('script,style,noscript,template')) n.remove();
      final seen = <int>{};
      final list = <ThreadItem>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        final m = RegExp(r'(?:thread-|[?&]tid=)(\d+)').firstMatch(href);
        if (m == null) continue;
        final tid = int.tryParse(m.group(1)!) ?? 0;
        final title = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (tid <= 0 || title.length < 2 || !seen.add(tid)) continue;
        final parent = (a.parent?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        list.add(ThreadItem(tid: tid, title: title, author: '', avatar: '', fid: 0, boardName: '', level: '', time: '', subtitle: parent == title ? '' : parent.replaceFirst(title, '').trim(), cover: '', likeCount: 0, replyCount: 0, viewCount: 0));
        if (list.length >= 50) break;
      }
      if (!mounted) return;
      setState(() { _results = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('搜索'), actions: [IconButton(onPressed: _loading ? null : _search, icon: const Icon(Icons.search))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 10), child: TextField(
        controller: _controller, textInputAction: TextInputAction.search, onSubmitted: (_) => _search(),
        decoration: InputDecoration(hintText: '输入关键词搜索帖子', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.arrow_forward_rounded)), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
      )),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Card(color: Theme.of(context).colorScheme.errorContainer, child: ListTile(leading: const Icon(Icons.error_outline), title: Text(_error!)))),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _results.isEmpty ? const Center(child: Text('输入关键词开始搜索')) : ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), itemCount: _results.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) { final item = _results[i]; return Card(child: ListTile(title: Text(item.title), subtitle: item.subtitle.isEmpty ? null : Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: item.title))))); },
      )),
    ]),
  );
}
