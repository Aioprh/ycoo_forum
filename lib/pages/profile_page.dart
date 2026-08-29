import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/member_service_v2.dart';
import '../services/profile_identity_service.dart';
import 'login_page.dart';
import 'member_feature_page.dart';
import 'native_site_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _username;
  int? _uid;
  String? _avatarUrl;
  bool _ready = false;
  static const _base = 'https://www.ycoo.net/';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    await AuthService.instance.init();
    if (AuthService.instance.isLoggedIn) {
      await AuthService.instance.checkLoggedIn();
      final identity = await ProfileIdentityService.instance.fetch();
      if (identity != null) {
        _username = identity.username ?? AuthService.instance.username;
        _uid = identity.uid ?? AuthService.instance.uid;
        _avatarUrl = identity.avatar ?? AuthService.instance.avatarUrl;
      }
    }
    _username ??= AuthService.instance.username;
    _uid ??= AuthService.instance.uid;
    _avatarUrl ??= AuthService.instance.avatarUrl;
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (ok == true) await _load();
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    setState(() { _username = null; _uid = null; _avatarUrl = null; _ready = true; });
  }

  void _openNativeSite(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeSitePage(path: path, title: title)));
  }

  void _openNative({required String title, required String path, required MemberFeatureType type}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberFeaturePage(title: title, path: path, type: type)));
  }

  void _openMySpace() {
    final path = _uid != null && _uid! > 0
        ? 'home.php?mod=space&uid=$_uid&mobile=2'
        : 'home.php?mod=space&username=${Uri.encodeQueryComponent(_username ?? '')}&mobile=2';
    _openNativeSite(path, '个人主页');
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Text(text, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
  );

  Widget _featureTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(icon)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ])),
        const Icon(Icons.chevron_right),
      ]),),
    ),
  );

  Widget _avatar(bool loggedIn) {
    if (!loggedIn || _avatarUrl == null || _avatarUrl!.isEmpty) return CircleAvatar(radius: 30, child: Icon(loggedIn ? Icons.person : Icons.login, size: 32));
    return CircleAvatar(radius: 30, backgroundImage: NetworkImage(_avatarUrl!));
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _username != null && _username!.trim().isNotEmpty && AuthService.instance.isLoggedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('我的'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
        _sectionHeader(context, '帐号'),
        Card(margin: EdgeInsets.zero, child: InkWell(
          borderRadius: BorderRadius.circular(16), onTap: loggedIn ? _openMySpace : (_ready ? _openLogin : null),
          child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            _avatar(loggedIn), const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(loggedIn ? _username!.trim() : '登录 / 注册', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(loggedIn ? (_uid != null && _uid! > 0 ? 'UID: $_uid · 个人主页 · 资料 · 主题 · 回帖' : '个人主页 · 资料 · 主题 · 回帖') : '登录后可回帖、发帖、打卡、评分、购买主题等'),
            ])), const Icon(Icons.chevron_right),
          ])),
        )),
        if (loggedIn) ...[
          _sectionHeader(context, '我的社区'),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.55, children: [
            _featureTile(icon: Icons.article_outlined, title: '我的主题', subtitle: '原生帖子列表', onTap: () => _openNative(title: '我的主题', path: 'home.php?mod=space&do=thread&view=me&mobile=2', type: MemberFeatureType.threads)),
            _featureTile(icon: Icons.forum_outlined, title: '我的回帖', subtitle: '原生回复列表', onTap: () => _openNative(title: '我的回帖', path: 'home.php?mod=space&do=thread&view=me&type=reply&mobile=2', type: MemberFeatureType.replies)),
            _featureTile(icon: Icons.bookmark_border, title: '我的收藏', subtitle: '原生收藏列表', onTap: () => _openNative(title: '我的收藏', path: 'home.php?mod=space&do=favorite&view=me&mobile=2', type: MemberFeatureType.favorites)),
            _featureTile(icon: Icons.notifications_none, title: '通知', subtitle: '原生通知列表', onTap: () => _openNative(title: '通知', path: 'home.php?mod=space&do=notice&mobile=2', type: MemberFeatureType.notices)),
            _featureTile(icon: Icons.mail_outline, title: '消息', subtitle: '原生私信列表', onTap: () => _openNative(title: '消息', path: 'home.php?mod=space&do=pm&mobile=2', type: MemberFeatureType.messages)),
            _featureTile(icon: Icons.people_outline, title: '好友 / 关注', subtitle: '原生好友与关注列表', onTap: () => _openNative(title: '好友 / 关注', path: 'home.php?mod=space&do=friend&mobile=2', type: MemberFeatureType.friends)),
          ]),
          _sectionHeader(context, '积分与活动'),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.55, children: [
            _featureTile(icon: Icons.account_balance_wallet_outlined, title: '星币 / 积分', subtitle: '原生余额与交易信息', onTap: () => _openNative(title: '星币 / 积分', path: 'home.php?mod=spacecp&ac=credit&mobile=2', type: MemberFeatureType.credits)),
            _featureTile(icon: Icons.calendar_today_outlined, title: '每日签到', subtitle: '原生签到、连续天数、奖励', onTap: () => _openNativeSite('k_misign-sign.html', '每日签到')),
            _featureTile(icon: Icons.casino_outlined, title: '幸运抽奖', subtitle: '原生抽奖页面', onTap: () => _openNativeSite('plugin.php?id=viewui_lottery', '幸运抽奖')),
            _featureTile(icon: Icons.agriculture_outlined, title: '明日农场', subtitle: '原生农场页面', onTap: () => _openNativeSite('plugin.php?id=jnfarm', '明日农场')),
            _featureTile(icon: Icons.confirmation_number_outlined, title: '邀请码', subtitle: '原生邀请码管理', onTap: () => _openNativeSite('plugin.php?frame=yes&id=boan_buycode&mobile=2', '邀请码')),
            _featureTile(icon: Icons.star_outline, title: '繁星达人', subtitle: '原生达人与会员榜单', onTap: () => _openNativeSite('plugin.php?frame=yes&id=boan_group', '繁星达人')),
          ]),
          _sectionHeader(context, '会员服务'),
          _featureTile(icon: Icons.add_card, title: '源币充值', subtitle: '原生充值与服务信息', onTap: () => _openNativeSite('home.php?ac=plugin&id=boan_buycredit:buycredit&mod=spacecp&op=credit', '源币充值')),
          const SizedBox(height: 10),
          _featureTile(icon: Icons.manage_accounts_outlined, title: '帐号设置', subtitle: '原生帐号设置页面', onTap: () => _openNativeSite('home.php?mod=spacecp&ac=profile&mobile=2', '帐号设置')),
          const SizedBox(height: 10),
          ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14), leading: const Icon(Icons.logout), title: const Text('退出登录'), trailing: const Icon(Icons.chevron_right), onTap: _logout),
        ] else ...[
          _sectionHeader(context, '登录后可用'),
          const Card(margin: EdgeInsets.zero, child: Padding(padding: EdgeInsets.all(16), child: Text('登录后可使用个人主页、我的主题、回帖、收藏、通知、消息、签到、星币、邀请码等会员功能。'))),
        ],
        _sectionHeader(context, '关于'),
        const ListTile(leading: Icon(Icons.apps), title: Text('源论坛'), subtitle: Text('YcoForum · 非官方客户端')),
        ListTile(leading: const Icon(Icons.public), title: const Text('电脑版官网'), subtitle: const Text('https://www.ycoo.net'), trailing: const Icon(Icons.chevron_right), onTap: () => _openNativeSite('', '源论坛')),
        const ListTile(leading: Icon(Icons.android), title: Text('版本'), subtitle: Text('1.0.0')),
      ]),
    );
  }
}
