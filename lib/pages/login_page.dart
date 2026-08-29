import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_service.dart';
import '../services/login_log.dart';

/// WebView 登录页:直接加载本站移动端登录页面,在系统浏览器内核里完成登录。
///
/// 本站会对 Cronet 的登录 POST 返回 System Error(反爬按连接指纹拦 POST),
/// 但真实浏览器内核(WebView)不受影响。登录成功后读取并保存会话 Cookie,
/// 供回帖等需要登录态的操作继续使用(实现与 shuyuan_app 一致的网页登录体验)。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final WebViewController _controller;
  bool _resolved = false;
  String _status = '请在网页中登录';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _checkLogin(),
      ));
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _controller.loadRequest(
        Uri.parse('${AuthService.base}${AuthService.loginPath}'),
      );
      LoginLog.instance.add('WebView 加载登录页 ${AuthService.loginPath}');
    } catch (e) {
      if (mounted) setState(() => _status = '加载失败:$e');
    }
  }

  /// 在每页加载完成后检查是否已登录(通过是否存在 auth Cookie 判定)。
  Future<void> _checkLogin() async {
    if (_resolved) return;
    final cookies = await WebViewCookieManager()
        .getCookies(domain: 'www.ycoo.net');
    // 每个 WebViewCookie 含 name/value,拼成 "k=v; k2=v2" 的 Cookie 串。
    final cookieStr = cookies
        .where((c) => c.value.isNotEmpty)
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
    final authed =
        cookies.any((c) => c.name.toLowerCase().endsWith('auth'));
    if (!authed) {
      LoginLog.instance.add('WebView 页面完成,但尚无 auth Cookie(未登录),'
          ' Cookie 项=${cookies.length}');
      return;
    }
    _resolved = true;
    if (!mounted) return;
    final username = await _extractUsername();
    LoginLog.instance.add('WebView 检测到 auth Cookie,判定已登录');
    await AuthService.instance.markLoggedInFromWeb(username, cookieStr);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<String> _extractUsername() async {
    try {
      final r = await _controller.runJavaScriptReturningResult("""
        (function(){
          var u='';
          var el=document.querySelector('.top_user');
          if(el) u=(el.textContent||'').trim();
          if(!u){ var a=document.querySelector('a[href*="space"]'); if(a) u=(a.textContent||'').trim(); }
          return u;
        })()
      """);
      // runJavaScriptReturningResult 在当前 webview_flutter 返回非空动态值。
      var s = r.toString().trim();
      if (s == 'null') s = '';
      // 返回值常是带引号的 JSON 字符串。
      return s.replaceAll(RegExp(r'^"|"$'), '').trim();
    } catch (_) {
      return '';
    }
  }

  /// 手动兜底:用户点"已完成登录"时,若检测到 auth Cookie 则保存并退出。
  Future<void> _manualDone() async {
    if (_resolved) return;
    setState(() => _status = '正在确认登录态…');
    await _checkLogin();
    if (!mounted) return;
    if (!_resolved) setState(() => _status = '尚未检测到登录 Cookie,请确认已在网页里登录成功');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('网页登录'),
        actions: [
          IconButton(
            tooltip: '重新加载',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_status,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _manualDone,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('已完成登录,返回应用'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}