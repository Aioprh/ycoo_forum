import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/api_service.dart';

/// 应用内 WebView 容器:带返回栏、加载进度、出错提示与后退能力。
/// 普通 URL 使用 WebView；ycoo-native-purchase://tid 则完全走原生购买请求。
class WebViewPage extends StatefulWidget {
  final String url;
  final String title;

  const WebViewPage({super.key, required this.url, required this.title});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  WebViewController? _controller;
  bool _loading = true;
  bool _error = false;
  String? _nativeMessage;

  bool get _nativePurchase => widget.url.startsWith('ycoo-native-purchase://');

  @override
  void initState() {
    super.initState();
    if (_nativePurchase) {
      _runNativePurchase();
    } else {
      _initWebView();
    }
  }

  void _initWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { _loading = true; _error = false; });
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
    _controller = controller;
  }

  Future<void> _runNativePurchase() async {
    final tidText = widget.url.substring('ycoo-native-purchase://'.length).split('?').first;
    final tid = int.tryParse(tidText);
    if (tid == null || tid <= 0) {
      if (mounted) setState(() { _loading = false; _error = true; _nativeMessage = '无效的主题 ID'; });
      return;
    }
    if (mounted) setState(() { _loading = true; _nativeMessage = '正在读取购买信息…'; });
    final result = await ApiService.instance.purchaseThread(tid);
    if (!mounted) return;
    setState(() { _loading = false; _nativeMessage = result.message; _error = !result.success; });
    if (result.success) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _reload() async {
    if (_nativePurchase) {
      await _runNativePurchase();
      return;
    }
    setState(() { _error = false; _loading = true; });
    await _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_nativePurchase) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading) const CircularProgressIndicator(),
                if (_loading) const SizedBox(height: 20),
                Icon(_error ? Icons.error_outline : Icons.shopping_cart_outlined, size: 48),
                const SizedBox(height: 16),
                Text(_nativeMessage ?? '准备购买…', textAlign: TextAlign.center),
                if (_error) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '后退',
            onPressed: () async {
              if (await _controller?.canGoBack() == true) await _controller?.goBack();
            },
            icon: const Icon(Icons.arrow_back_outlined),
          ),
          IconButton(tooltip: '重新加载', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_loading && !_error)
            const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
          if (_error)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('页面加载失败'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _reload, child: const Text('重试')),
            ])),
        ],
      ),
    );
  }
}