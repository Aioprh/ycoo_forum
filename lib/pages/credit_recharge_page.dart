import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_service.dart';

/// 源币充值使用真实论坛页面，而不是把包含 JS/支付流程的页面静态解析成 Flutter 表单。
/// 这样可以完整保留原站的 formhash、订单、支付二维码/跳转和充值状态。
class CreditRechargePage extends StatefulWidget {
  const CreditRechargePage({super.key});

  @override
  State<CreditRechargePage> createState() => _CreditRechargePageState();
}

class _CreditRechargePageState extends State<CreditRechargePage> {
  static const _base = 'https://www.ycoo.net/';
  static const _path =
      'home.php?ac=plugin&id=boan_buycredit:buycredit&mod=spacecp&op=credit';

  final _cookieManager = WebViewCookieManager();
  WebViewController? _controller;
  bool _loading = true;
  int _progress = 0;
  String? _error;

  Uri get _uri => Uri.parse('$_base$_path');

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      await AuthService.instance.init();
      final cookie = AuthService.instance.authCookie?.trim() ?? '';
      if (!AuthService.instance.isLoggedIn || cookie.isEmpty) {
        throw Exception('请先登录论坛');
      }

      // Native HTTP 请求和 WebView 不共享 Cookie 存储，因此充值页必须把当前
      // 登录会话显式注入 WebView，否则原站会把用户当游客并重新跳登录页。
      for (final part in cookie.split(';')) {
        final item = part.trim();
        final index = item.indexOf('=');
        if (index <= 0) continue;
        final name = item.substring(0, index).trim();
        final value = item.substring(index + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        await _cookieManager.setCookie(
          WebViewCookie(
            name: name,
            value: value,
            domain: 'www.ycoo.net',
            path: '/',
          ),
        );
      }

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress.clamp(0, 100));
          },
          onPageStarted: (_) {
            if (mounted)
              setState(() {
                _loading = true;
                _error = null;
              });
          },
          onPageFinished: (_) {
            if (mounted)
              setState(() {
                _loading = false;
                _progress = 100;
              });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (mounted)
              setState(() {
                _loading = false;
                _error = error.description;
              });
          },
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      );
      _controller = controller;
      await controller.loadRequest(_uri);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) {
      await _initWebView();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('源币充值'),
        actions: [
          IconButton(
            tooltip: '刷新充值页面',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading && _progress > 0 && _progress < 100)
            LinearProgressIndicator(value: _progress / 100),
          Expanded(
            child: _error != null && _controller == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 52,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _initWebView,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller!),
          ),
        ],
      ),
    );
  }
}
