import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/member_service_v2.dart';
import '../services/profile_identity_service.dart';
import 'login_page.dart';
import 'member_feature_page.dart';
import 'native_site_page.dart';
import 'search_page.dart';

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
              Text(loggedIn ? 'UID: ${_uid ?? '—'} · 个人主页 · 资料 · 主题 · 回帖' : '登录后可使用论坛全部会员功能'),
            ])), const Icon(Icons.chevron_right),
          ])),
        )),
        if (loggedIn) ...[
          _sectionHeader(context, '我的社区'),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.55, children: [
            _featureTile(icon: Icons.person_outline, title: '个人主页', subtitle: '资料、主题、回帖、动态', onTap: _openMySpace),
            _featureTile(icon: Icons.badge_outlined, title: '资料设置', subtitle: '基本资料与隐私', onTap: () => _openNativeSite('home.php?mod=spacecp&ac=profile&mobile=2', '资料设置')),
            _featureTile(icon: Icons.article_outlined, title: '我的主题', subtitle: '我发布的帖子', onTap: () => _openNative(title: '我的主题', path: 'home.php?mod=space&do=thread&view=me&mobile=2', type: MemberFeatureType.threads)),
            _featureTile(icon: Icons.forum_outlined, title: '我的回帖', subtitle: '我参与的帖子', onTap: () => _openNative(title: '我的回帖', path: 'home.php?mod=space&do=thread&view=me&type=reply&mobile=2', type: MemberFeatureType.replies)),
            _featureTile(icon: Icons.bookmark_border, title: '我的收藏', subtitle: '收藏的主题', onTap: () => _openNative(title: '我的收藏', path: 'home.php?mod=space&do=favorite&view=me&mobile=2', type: MemberFeatureType.favorites)),
            _featureTile(icon: Icons.notifications_none, title: '通知', subtitle: '回复、提醒、赞等', onTap: () => _openNative(title: '通知', path: 'home.php?mod=space&do=notice&mobile=2', type: MemberFeatureType.notices)),
            _featureTile(icon: Icons.mail_outline, title: '消息', subtitle: '站内私信', onTap: () => _openNative(title: '消息', path: 'home.php?mod=space&do=pm&mobile=2', type: MemberFeatureType.messages)),
            _featureTile(icon: Icons.people_outline, title: '好友 / 关注', subtitle: '好友、关注与粉丝', onTap: () => _openNative(title: '好友 / 关注', path: 'home.php?mod=space&do=friend&mobile=2', type: MemberFeatureType.friends)),
            _featureTile(icon: Icons.photo_library_outlined, title: '相册', subtitle: '个人相册', onTap: () => _openNativeSite('home.php?mod=space&do=album&view=me&mobile=2', '相册')),
            _featureTile(icon: Icons.mood_outlined, title: '心情墙', subtitle: '我的动态与心情', onTap: () => _openNativeSite('home.php?mod=space&do=doing&view=me&mobile=2', '心情墙')),
            _featureTile(icon: Icons.campaign_outlined, title: '访问推广', subtitle: '推广与访问统计', onTap: () => _openNativeSite('home.php?mod=spacecp&ac=promotion&mobile=2', '访问推广')),
            _featureTile(icon: Icons.block_outlined, title: '小黑屋', subtitle: '处罚与禁言状态', onTap: () => _openNativeSite('home.php?mod=modcp&action=member&mobile=2', '小黑屋')),
          ]),
          _sectionHeader(context, '积分、签到与会员'),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.55, children: [
            _featureTile(icon: Icons.account_balance_wallet_outlined, title: '星币 / 积分', subtitle: '余额、积分、交易记录', onTap: () => _openNative(title: '星币 / 积分', path: 'home.php?mod=spacecp&ac=credit&mobile=2', type: MemberFeatureType.credits)),
            _featureTile(icon: Icons.calendar_today_outlined, title: '每日签到', subtitle: '签到、连续天数、奖励', onTap: () => _openNativeSite('k_misign-sign.html', '每日签到')),
            _featureTile(icon: Icons.star_rounded, title: '繁星开通', subtitle: '会员权益与开通', onTap: () => _openNativeSite('plugin.php?id=boan_group', '繁星开通')),
            _featureTile(icon: Icons.card_giftcard_outlined, title: '道具中心', subtitle: '论坛道具', onTap: () => _openNativeSite('home.php?mod=spacecp&ac=plugin&id=thunderplugin:thunder', '道具中心')),
            _featureTile(icon: Icons.task_alt_outlined, title: '任务中心', subtitle: '任务、进度与奖励', onTap: () => _openNativeSite('home.php?mod=task&mobile=2', '任务中心')),
            _featureTile(icon: Icons.confirmation_number_outlined, title: '邀请码', subtitle: '邀请码管理', onTap: () => _openNativeSite('plugin.php?frame=yes&id=boan_buycode&mobile=2', '邀请码')),
            _featureTile(icon: Icons.casino_outlined, title: '幸运抽奖', subtitle: '论坛抽奖活动', onTap: () => _openNativeSite('plugin.php?id=viewui_lottery', '幸运抽奖')),
            _featureTile(icon: Icons.agriculture_outlined, title: '明日农场', subtitle: '农场与活动', onTap: () => _openNativeSite('plugin.php?id=jnfarm', '明日农场')),
          ]),
          _sectionHeader(context, '论坛工具'),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.55, children: [
            _featureTile(icon: Icons.search, title: '搜索', subtitle: '帖子、用户、版块', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()))),
            _featureTile(icon: Icons.public, title: '电脑版论坛', subtitle: '论坛完整入口', onTap: () => _openNativeSite('', '源论坛')),
            _featureTile(icon: Icons.verified_outlined, title: '认证专区', subtitle: '认证用户与专区', onTap: () => _openNativeSite('forum.php?mod=forumdisplay&fid=2&mobile=2', '认证专区')),
            _featureTile(icon: Icons.emoji_events_outlined, title: '繁星专区', subtitle: '繁星会员专区', onTap: () => _openNativeSite('forum.php?mod=forumdisplay&fid=2&mobile=2', '繁星专区')),
          ]),
          _sectionHeader(context, '会员服务'),
          _featureTile(icon: Icons.add_card, title: '源币充值', subtitle: '充值、兑换比例与订单信息', onTap: () => _openNativeSite('home.php?ac=plugin&id=boan_buycredit:buycredit&mod=spacecp&op=credit', '源币充值')),
          const SizedBox(height: 10),
          _featureTile(icon: Icons.manage_accounts_outlined, title: '帐号设置', subtitle: '帐号资料、隐私与安全', onTap: () => _openNativeSite('home.php?mod=spacecp&ac=profile&mobile=2', '帐号设置')),
          const SizedBox(height: 10),
          ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14), leading: const Icon(Icons.logout), title: const Text('退出登录'), trailing: const Icon(Icons.chevron_right), onTap: _logout),
        ] else ...[
          _sectionHeader(context, '登录后可用'),
          const Card(margin: EdgeInsets.zero, child: Padding(padding: EdgeInsets.all(16), child: Text('登录后显示个人主页、资料设置、我的主题、回帖、收藏、通知、消息、好友、相册、签到、积分、星币、会员服务和论坛工具。'))),
        ],
        _sectionHeader(context, '关于'),
        const ListTile(leading: Icon(Icons.apps), title: Text('源论坛'), subtitle: Text('YcoForum · 非官方客户端')),
        ListTile(leading: const Icon(Icons.public), title: const Text('电脑版官网'), subtitle: const Text('ycoo.net'), trailing: const Icon(Icons.chevron_right), onTap: () => _openNativeSite('', '源论坛')),
        const ListTile(leading: Icon(Icons.android), title: Text('版本'), subtitle: Text('1.0.0')),
      ]),
    );
  }
}
