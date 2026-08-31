import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/site_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// 应用内 WebView 容器。打开网页前显式同步原生保存的登录 Cookie，
/// 避免“App 显示已登录但 WebView 又变成游客”。
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

  bool get _nativePurchase =>
      widget.url.startsWith('ycoo-native-purchase://') ||
      (widget.title == '购买主题' && widget.url.contains('ycoo.net/thread-'));

  @override
  void initState() {
    super.initState();
    if (_nativePurchase) {
      _runNativePurchase();
    } else {
      _initWebView();
    }
  }

  Future<void> _syncCookies() async {
    final raw = AuthService.instance.authCookie;
    if (raw == null || raw.trim().isEmpty) return;
    final manager = WebViewCookieManager();
    for (final part in raw.split(';')) {
      final item = part.trim();
      final eq = item.indexOf('=');
      if (eq <= 0) continue;
      final name = item.substring(0, eq).trim();
      final value = item.substring(eq + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      try {
        await manager.setCookie(WebViewCookie(
          name: name,
          value: value,
          domain: Uri.parse(SiteConfig.base).host,
          path: '/',
        ));
      } catch (_) {}
    }
  }

  Future<void> _initWebView() async {
    try {
      await AuthService.instance.init();
      await _syncCookies();
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFFFFFFF))
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { _loading = true; _error = false; });
          },
          onProgress: (progress) { if (mounted) setState(() {}); },
          onPageFinished: (url) { if (mounted) setState(() => _loading = false); },
          onWebResourceError: (error) { if (mounted) setState(() => _error = true); },
        ));
      await controller.loadRequest(Uri.parse(widget.url));
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; _nativeMessage = '页面加载失败: $e'; });
    }
  }

  Future<void> _runNativePurchase() async {
    int? tid;
    if (widget.url.startsWith('ycoo-native-purchase://')) {
      final raw = widget.url.substring('ycoo-native-purchase://'.length).split('?').first;
      tid = int.tryParse(raw);
    } else {
      final m = RegExp(r'thread-(\d+)').firstMatch(widget.url);
      tid = m == null ? null : int.tryParse(m.group(1)!);
    }
    if (tid == null || tid! <= 0) {
      if (mounted) setState(() { _loading = false; _error = true; _nativeMessage = '无效的主题 ID'; });
      return;
    }
    if (mounted) setState(() { _loading = true; _nativeMessage = '正在读取购买信息…'; });
    final result = await ApiService.instance.purchaseThread(tid!);
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
    await _syncCookies();
    await _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_nativePurchase) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_loading) const CircularProgressIndicator(),
            if (_loading) const SizedBox(height: 20),
            Icon(_error ? Icons.error_outline : Icons.shopping_cart_outlined, size: 48),
            const SizedBox(height: 16),
            Text(_nativeMessage ?? '准备购买…', textAlign: TextAlign.center),
            if (_error) ...[const SizedBox(height: 16), FilledButton(onPressed: _reload, child: const Text('重试'))],
          ]),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: '后退', onPressed: () async { if (await _controller?.canGoBack() == true) await _controller?.goBack(); }, icon: const Icon(Icons.arrow_back_outlined)),
          IconButton(tooltip: '重新加载', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Stack(children: [
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_loading && !_error) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
        if (_error) Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_nativeMessage ?? '页面加载失败'), const SizedBox(height: 8), FilledButton(onPressed: _reload, child: const Text('重试')),
        ])),
      ]),
    );
  }
}