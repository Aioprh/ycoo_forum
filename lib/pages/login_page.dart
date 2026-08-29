import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_service.dart';
import '../services/login_log.dart';

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
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => _checkLogin()));
    _load();
  }

  Future<void> _load() async {
    try {
      await _controller.loadRequest(Uri.parse('${AuthService.base}${AuthService.loginPath}'));
      LoginLog.instance.add('WebView 加载登录页 ${AuthService.loginPath}');
    } catch (e) {
      if (mounted) setState(() => _status = '加载失败:$e');
    }
  }

  Future<void> _checkLogin() async {
    if (_resolved) return;
    final cookies = await WebViewCookieManager().getCookies(domain: Uri.parse(AuthService.base));
    final cookieStr = cookies.where((c) => c.value.isNotEmpty).map((c) => '${c.name}=${c.value}').join('; ');
    final authed = cookies.any((c) => c.name.toLowerCase().endsWith('auth'));
    if (!authed) return;

    _resolved = true;
    final identity = await _extractIdentity();
    LoginLog.instance.add('WebView 检测到 auth Cookie,判定已登录');
    await AuthService.instance.markLoggedInFromWeb(identity.username, cookieStr, uid: identity.uid);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<_Identity> _extractIdentity() async {
    try {
      final r = await _controller.runJavaScriptReturningResult("""
        (function(){
          var username=''; var uid='';
          var links=document.querySelectorAll('a[href]');
          for(var i=0;i<links.length;i++){
            var a=links[i], h=a.getAttribute('href')||'';
            if(!uid){ var m=h.match(/(?:uid=|home\\.php\\?mod=space&uid=)(\\d+)/); if(m) uid=m[1]; }
            var t=(a.textContent||'').trim();
            if(!username && t && (h.indexOf('mod=space')>=0 || h.indexOf('uid=')>=0)) username=t;
          }
          if(!username){ var el=document.querySelector('.top_user'); if(el) username=(el.textContent||'').trim(); }
          return JSON.stringify({username:username,uid:uid});
        })()
      """);
      var s = r.toString().trim();
      s = s.replaceAll(RegExp(r'^"|"$'), '').replaceAll(r'\"', '"');
      final username = RegExp(r'"username"\s*:\s*"([^"]*)"').firstMatch(s)?.group(1) ?? '';
      final uid = int.tryParse(RegExp(r'"uid"\s*:\s*"?(\d+)').firstMatch(s)?.group(1) ?? '');
      return _Identity(username, uid);
    } catch (_) {
      return const _Identity('', null);
    }
  }

  Future<void> _manualDone() async {
    if (_resolved) return;
    setState(() => _status = '正在确认登录态…');
    await _checkLogin();
    if (mounted && !_resolved) setState(() => _status = '尚未检测到登录 Cookie,请确认已在网页里登录成功');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('网页登录'), actions: [IconButton(tooltip: '重新加载', icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: Column(children: [
      Expanded(child: WebViewWidget(controller: _controller)),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _manualDone, icon: const Icon(Icons.check, size: 18), label: const Text('已完成登录,返回应用')),
        ]),
      ),
    ]),
  );
}

class _Identity {
  final String username;
  final int? uid;
  const _Identity(this.username, this.uid);
}