import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/checkin_service.dart';
import '../services/profile_identity_service.dart';
import 'login_page.dart';
import 'member_feature_page.dart';
import 'native_profile_page.dart';
import 'native_site_page.dart';
import 'profile_edit_page.dart';
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
  bool _signing = false;
  String? _checkinResult;

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
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (ok == true) await _load();
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (mounted) setState(() { _username = null; _uid = null; _avatarUrl = null; _ready = true; _checkinResult = null; });
  }

  Future<void> _checkIn() async {
    if (_signing) return;
    setState(() { _signing = true; _checkinResult = null; });
    final result = await CheckinService.instance.sign();
    if (!mounted) return;
    setState(() { _signing = false; _checkinResult = result; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ProfileEditPage()));
    if (changed == true) await _load();
  }

  void _openNativeSite(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeSitePage(path: path, title: title)));
  }

  void _openNative({required String title, required String path, required MemberFeatureType type}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberFeaturePage(title: title, path: path, type: type)));
  }

  void _openMySpace() {
    final uid = _uid;
    if (uid == null || uid <= 0) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeProfilePage(uid: uid, username: _username)));
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Text(text, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
  );

  Widget _featureTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(13)), child: Icon(icon, size: 22)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        ]),
      ),
    ),
  );

  Widget _avatar(bool loggedIn) {
    if (!loggedIn || _avatarUrl == null || _avatarUrl!.isEmpty) {
      return CircleAvatar(radius: 34, child: Icon(loggedIn ? Icons.person : Icons.login, size: 34));
    }
    return CircleAvatar(radius: 34, backgroundImage: NetworkImage(_avatarUrl!));
  }

  Widget _accountCard(bool loggedIn) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loggedIn ? _openMySpace : (_ready ? _openLogin : null),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surface])),
          child: Row(children: [
            Stack(children: [
              _avatar(loggedIn),
              if (loggedIn) Positioned(right: 0, bottom: 0, child: Container(width: 18, height: 18, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle, border: Border.all(color: scheme.surface, width: 2)), child: const Icon(Icons.check, size: 11))),
            ]),
            const SizedBox(width: 15),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(loggedIn ? _username!.trim() : '登录 / 注册', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(loggedIn ? 'UID ${_uid ?? '—'}  ·  点击进入我的主页' : '登录后解锁完整会员功能', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              if (loggedIn) ...[
                const SizedBox(height: 10),
                Row(children: [
                  _miniStat(Icons.article_outlined, '我的主题'),
                  const SizedBox(width: 12),
                  _miniStat(Icons.forum_outlined, '我的回帖'),
                  const SizedBox(width: 12),
                  _miniStat(Icons.settings_outlined, '资料设置'),
                ]),
              ],
            ])),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600))]);

  Widget _checkinCard() {
    final scheme = Theme.of(context).colorScheme;
    final done = _checkinResult != null && (_checkinResult!.contains('成功') || _checkinResult!.contains('已经签到') || _checkinResult!.contains('已签'));
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _signing || done ? null : _checkIn,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.secondaryContainer, scheme.surface])),
          child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: scheme.secondary, borderRadius: BorderRadius.circular(16)), child: Icon(done ? Icons.check_rounded : Icons.calendar_month_rounded, color: scheme.onSecondary, size: 27)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Text('每日签到', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(width: 7), if (done) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)), child: const Text('今日已完成', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))) ]),
              const SizedBox(height: 4),
              Text(_signing ? '正在签到，请稍候…' : done ? (_checkinResult ?? '今天已经签到') : '点击一次，直接完成今日签到', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ])),
            if (_signing) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) else if (!done) Icon(Icons.arrow_forward_ios_rounded, size: 16, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _username != null && _username!.trim().isNotEmpty && AuthService.instance.isLoggedIn;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('我的'), actions: [IconButton(tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
          children: [
            _sectionHeader(context, '帐号'),
            _accountCard(loggedIn),
            if (loggedIn) ...[
              _sectionHeader(context, '社区'),
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
                children: [
                  _featureTile(icon: Icons.person_outline, title: '个人主页', subtitle: '资料、主题、回帖', onTap: _openMySpace),
                  _featureTile(icon: Icons.badge_outlined, title: '资料设置', subtitle: '编辑个人资料', onTap: _openEdit),
                  _featureTile(icon: Icons.article_outlined, title: '我的主题', subtitle: '我发布的帖子', onTap: () => _openNative(title: '我的主题', path: 'home.php?mod=space&do=thread&view=me&mobile=2', type: MemberFeatureType.threads)),
                  _featureTile(icon: Icons.forum_outlined, title: '我的回帖', subtitle: '我参与的帖子', onTap: () => _openNative(title: '我的回帖', path: 'home.php?mod=space&do=thread&view=me&type=reply&mobile=2', type: MemberFeatureType.replies)),
                  _featureTile(icon: Icons.bookmark_border, title: '我的收藏', subtitle: '收藏的主题', onTap: () => _openNative(title: '我的收藏', path: 'home.php?mod=space&do=favorite&view=me&mobile=2', type: MemberFeatureType.favorites)),
                  _featureTile(icon: Icons.notifications_none, title: '通知', subtitle: '回复、提醒、赞', onTap: () => _openNative(title: '通知', path: 'home.php?mod=space&do=notice&mobile=2', type: MemberFeatureType.notices)),
                  _featureTile(icon: Icons.mail_outline, title: '消息', subtitle: '站内私信', onTap: () => _openNative(title: '消息', path: 'home.php?mod=space&do=pm&mobile=2', type: MemberFeatureType.messages)),
                  _featureTile(icon: Icons.people_outline, title: '好友 / 关注', subtitle: '好友、关注与粉丝', onTap: () => _openNative(title: '好友 / 关注', path: 'home.php?mod=space&do=friend&mobile=2', type: MemberFeatureType.friends)),
                ],
              ),
              _sectionHeader(context, '签到与资产'),
              _checkinCard(),
              const SizedBox(height: 10),
              _featureTile(icon: Icons.account_balance_wallet_outlined, title: '星币 / 积分', subtitle: '余额与交易记录', onTap: () => _openNative(title: '星币 / 积分', path: 'home.php?mod=spacecp&ac=credit&mobile=2', type: MemberFeatureType.credits)),
              _sectionHeader(context, '论坛工具'),
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
                children: [
                  _featureTile(icon: Icons.search, title: '搜索', subtitle: '帖子、用户、版块', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()))),
                  _featureTile(icon: Icons.public, title: '电脑版论坛', subtitle: '完整论坛入口', onTap: () => _openNativeSite('', '源论坛')),
                ],
              ),
              _sectionHeader(context, '会员服务'),
              _featureTile(icon: Icons.add_card, title: '源币充值', subtitle: '充值与订单信息', onTap: () => _openNativeSite('home.php?ac=plugin&id=boan_buycredit:buycredit&mod=spacecp&op=credit', '源币充值')),
              const SizedBox(height: 10),
              _featureTile(icon: Icons.manage_accounts_outlined, title: '帐号设置', subtitle: '帐号资料与安全', onTap: _openEdit),
              const SizedBox(height: 8),
              ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14), leading: const Icon(Icons.logout), title: const Text('退出登录'), trailing: const Icon(Icons.chevron_right), onTap: _logout),
            ] else ...[
              _sectionHeader(context, '登录后可用'),
              Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('登录后使用完整论坛功能', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), Text('个人主页、收藏、通知、消息、签到、积分等功能都可以直接在 App 中使用。', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)), const SizedBox(height: 14), FilledButton.icon(onPressed: _ready ? _openLogin : null, icon: const Icon(Icons.login), label: const Text('立即登录'))])),
            ],
            _sectionHeader(context, '关于'),
            const ListTile(contentPadding: EdgeInsets.symmetric(horizontal: 4), leading: Icon(Icons.apps_rounded), title: Text('源论坛'), subtitle: Text('YcoForum · 非官方客户端')),
          ],
        ),
      ),
    );
  }
}
