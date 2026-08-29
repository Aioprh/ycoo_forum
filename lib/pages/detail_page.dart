import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/thread_detail.dart';
import '../services/api_service.dart';
import 'thread_list_page.dart';

/// 帖子详情页:原生头部(标题/作者/版块/时间)+ 正文 HTML(WebView 渲染)。
class DetailPage extends StatefulWidget {
  final int tid;
  final String title;

  const DetailPage({super.key, required this.tid, required this.title});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  ThreadDetail? _detail;
  WebViewController? _bodyController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ApiService.instance.fetchThreadDetail(widget.tid);
      if (!mounted) return;
      setState(() => _detail = detail);
      _bodyController = _buildBodyController(detail.bodyHtml);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WebViewController _buildBodyController(String bodyHtml) {
    final doc = '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<base href="https://www.ycoo.net/">
<style>
  body{margin:0;padding:16px;font-size:16px;line-height:1.7;color:#333;word-wrap:break-word;}
  img{max-width:100%!important;height:auto;border-radius:6px;}
  a{color:#4e6ef2;}
  pre,code{white-space:pre-wrap;word-break:break-all;}
  table{width:100%;border-collapse:collapse;}
  .attach-notice{background:#f6f7fb;padding:12px;border-radius:8px;color:#666;margin:8px 0;}
</style>
</head>
<body>
$bodyHtml
</body>
</html>
''';
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..loadHtmlString(doc, baseUrl: 'https://www.ycoo.net/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('详情加载失败'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _fetch, child: const Text('重试')),
          ],
        ),
      );
    }
    final d = _detail!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _header(context, d),
        const Divider(),
        if (d.bodyHtml.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                '该主题可能需登录或购买后才可见正文。',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: WebViewWidget(controller: _bodyController!),
            ),
          ),
      ],
    );
  }

  Widget _header(BuildContext context, ThreadDetail d) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage:
                    d.avatar.isNotEmpty ? NetworkImage(d.avatar) : null,
                child: d.avatar.isNotEmpty ? null : const Icon(Icons.person, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(d.author, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        if (d.level.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(d.level, style: TextStyle(fontSize: 11, color: theme.primaryColor)),
                        ],
                      ],
                    ),
                    if (d.time.isNotEmpty)
                      Text(d.time, style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                ),
              ),
              if (d.boardName.isNotEmpty)
                GestureDetector(
                  onTap: d.fid == 0
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BoardThreadListPage(filter: d.boardName, fid: d.fid),
                            ),
                          ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      d.boardName,
                      style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}