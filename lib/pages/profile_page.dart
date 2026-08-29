import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'login_page.dart';
import 'webview_page.dart';

/// 我的页:登录态 / 站点信息 / 关于。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _username;
  bool _ready = false;

  static const _loginMessage =
      '登录后可回帖、发帖、打卡、评分等(网页登录)';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AuthService.instance.init();
    if (!mounted) return;
    setState(() {
      _username = AuthService.instance.username;
      _ready = true;
    });
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) {
      await _load();
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    setState(() {
      _username = null;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _username != null;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionHeader(context, '帐号'),
          if (loggedIn)
            _buildAccountTile()
          else
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('登录 / 注册'),
              subtitle: const Text(_loginMessage),
              trailing: const Icon(Icons.chevron_right),
              onTap: _ready ? _openLogin : null,
            ),
          if (loggedIn)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _logout,
            )
          else
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('说明'),
              subtitle: Text('本站为「源论坛」民间移动端;发布、回帖等需先登录(网页)'),
            ),
          const Divider(),
          _sectionHeader(context, '关于'),
          const ListTile(
            leading: Icon(Icons.apps),
            title: Text('源论坛'),
            subtitle: Text('YcoForum · 非官方客户端'),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('电脑版官网'),
            subtitle: const Text('https://www.ycoo.net'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _openWeb(context, 'https://www.ycoo.net', '源论坛'),
          ),
          ListTile(
            leading: const Icon(Icons.android),
            title: const Text('版本'),
            subtitle: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile() {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(_username ?? '已登录'),
      subtitle: const Text('已通过网页登录'),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _openWeb(BuildContext context, String url, String title) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebViewPage(url: url, title: title)));
  }
}