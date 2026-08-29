import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 应用内 WebView 容器:带返回栏、加载进度、出错提示与后退能力。
/// 用于打开原站搜索 / 登录 / 官网等页面,无需跳出到外部浏览器。
class WebViewPage extends StatefulWidget {
  final String url;
  final String title;

  const WebViewPage({super.key, required this.url, required this.title});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = false;
              });
            }
          },
          onProgress: (progress) {
            if (mounted) setState(() {});
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _error = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _reload() async {
    setState(() {
      _error = false;
      _loading = true;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '后退',
            onPressed: () async {
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              }
            },
            icon: const Icon(Icons.arrow_back_outlined),
          ),
          IconButton(tooltip: '重新加载', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading && !_error)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('页面加载失败'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}