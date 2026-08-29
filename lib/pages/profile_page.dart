import 'package:flutter/material.dart';

import 'webview_page.dart';

/// 我的页:站点信息 / 登录 / 关于。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const _loginUrl =
      'https://www.ycoo.net/member.php?mod=logging&action=login&mobile=2';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionHeader(context, '帐号'),
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('登录 / 注册'),
            subtitle: const Text('在原站页面登录后,可查看需登录资源'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openWeb(context, _loginUrl, '登录'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('说明'),
            subtitle: Text('本站为「源论坛」民间移动端,仅做阅读展示;发布、回帖等请用网页端'),
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
            onTap: () => _openWeb(context, 'https://www.ycoo.net', '源论坛'),
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
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WebViewPage(url: url, title: title)));
  }
}