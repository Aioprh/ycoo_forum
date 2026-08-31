import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/profile_service.dart';
import '../services/profile_username_service.dart';
import 'detail_page.dart';
import 'native_chat_page.dart';

class NativeProfilePage extends StatefulWidget {
  final int uid;
  final String? username;
  const NativeProfilePage({super.key, required this.uid, this.username});
  @override State<NativeProfilePage> createState() => _NativeProfilePageState();
}

class _NativeProfilePageState extends State<NativeProfilePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  ProfileData? _profile;
  List<ThreadItem> _items = const [];
  bool _loading = true, _loadingList = false, _followBusy = false;
  String? _error;
  String? _displayUsername;
  List<String> _displayBadges = const [];

  @override void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged); _load(); }
  @override void dispose() { _tabs.removeListener(_tabChanged); _tabs.dispose(); super.dispose(); }
  void _tabChanged() { if (!_tabs.indexIsChanging) _loadList(replies: _tabs.index == 1); }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final p = await ProfileService.instance.fetchProfile(widget.uid, fallbackUsername: widget.username, forceRefresh: true);
      final resolvedName = await ProfileUsernameService.instance.resolve(widget.uid, fallback: widget.username);
      final identity = _NameParts.parse(resolvedName ?? p.username, group: p.group);
      if (mounted) setState(() {
        _profile = p;
        _displayUsername = identity.name;
        _displayBadges = identity.badges;
      });
      await _loadList(replies: _tabs.index == 1);
    } catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadList({required bool replies}) async {
    if (!mounted) return;
    setState(() => _loadingList = true);
    try { final list = await ProfileService.instance.fetchThreads(widget.uid, replies: replies); if (mounted) setState(() => _items = list); }
    catch (_) { if (mounted) setState(() => _items = const []); }
    finally { if (mounted) setState(() => _loadingList = false); }
  }

  Future<void> _follow() async {
    final p = _profile; if (_followBusy || p == null) return;
    final next = !p.followedByMe; setState(() => _followBusy = true);
    final err = await ProfileService.instance.setFollow(widget.uid, next);
    if (!mounted) return; setState(() => _followBusy = false);
    if (err != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err))); return; }
    setState(() => _profile = p.copyWith(following: p.following + (next ? 1 : -1), followedByMe: next));
  }

  void _chat() {
    final p = _profile; if (p == null || p.uid <= 0) return;
    final name = _displayUsername ?? _NameParts.parse(p.username, group: p.group).name;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeChatPage(uid: p.uid, username: name)));
  }

  @override Widget build(BuildContext context) {
    final p = _profile;
    if (_loading && p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (p == null) return Scaffold(appBar: AppBar(title: const Text('个人资料')), body: _Error(message: _error ?? '加载失败', retry: _load));
    final identity = _NameParts.parse(_displayUsername ?? p.username, group: p.group, preferredBadges: _displayBadges);
    final name = identity.name;
    final badges = identity.badges;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 238, pinned: true, title: const Text('个人资料'),
            actions: [IconButton(onPressed: _chat, tooltip: '聊天', icon: const Icon(Icons.chat_bubble_outline_rounded)), IconButton(onPressed: _load, tooltip: '刷新', icon: const Icon(Icons.refresh))],
            flexibleSpace: FlexibleSpaceBar(background: _Header(profile: p, username: name, badges: badges, onFollow: _follow, onChat: _chat, busy: _followBusy)),
          ),
          SliverToBoxAdapter(child: _Stats(profile: p)),
          SliverPersistentHeader(pinned: true, delegate: _TabHeader(TabBar(controller: _tabs, tabs: const [Tab(icon: Icon(Icons.article_outlined), text: '主题'), Tab(icon: Icon(Icons.forum_outlined), text: '回帖')]))),
          if (_loadingList) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          if (!_loadingList && _items.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: _Empty()),
          if (_items.isNotEmpty) SliverPadding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), sliver: SliverList.builder(itemCount: _items.length, itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _ThreadCard(item: _items[i])))),
        ]),
      ),
    );
  }

  static bool _isUsableName(String value) {
    final v = _NameParts.parse(value).name.trim();
    if (v.isEmpty || v == '用户' || v.contains('�') || v.contains('\uFFFD')) return false;
    final compact = v.replaceAll(RegExp(r'[\s\u2000-\u206F\u25A0-\u27BF\uE000-\uF8FF]+'), '');
    return !RegExp(r'^(?:资料|个人资料|用户资料|用户|用户名|昵称|关注|已关注|聊天|私信|回复|主题|回帖|帖子|帖子数|粉丝|积分|星币|登录|注册|退出|刷新|个人中心|Ta的空间|空间|我的|提示信息|系统提示|温馨提示|提示|抱歉|无权|没有权限|不存在|该用户)$', caseSensitive: false).hasMatch(compact);
  }
}

class _NameParts {
  final String name;
  final List<String> badges;
  const _NameParts(this.name, this.badges);

  static _NameParts parse(String? source, {String? group, List<String>? preferredBadges}) {
    final raw = (source ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final badgeSource = '${preferredBadges?.join(' ') ?? ''} ${group ?? ''} $raw';
    final badges = <String>[];
    final level = RegExp(r'Lv\.?\s*\d+', caseSensitive: false).firstMatch(badgeSource)?.group(0);
    if (level != null) badges.add(level.replaceAll(RegExp(r'\s+'), ''));
    const ranks = ['童生','秀才','举人','进士','探花','榜眼','状元','九品','八品','七品','六品','五品','四品','三品','二品','一品'];
    for (final rank in ranks) {
      if (badgeSource.contains(rank)) { badges.add(rank); break; }
    }

    var name = raw;
    name = name.replaceFirst(RegExp(r'Lv\.?\s*\d+.*$', caseSensitive: false), '').trim();
    if (name.isEmpty || _isUiLabel(name)) name = raw;
    if (name.length > 32) name = name.substring(0, 32).trim();
    return _NameParts(name.isEmpty ? '用户' : name, List.unmodifiable(badges));
  }

  static bool _isUiLabel(String value) => RegExp(r'^(?:资料|个人资料|用户资料|用户|用户名|昵称|关注|已关注|聊天|私信|回复|主题|回帖|帖子|帖子数|粉丝|积分|星币|登录|注册|退出|刷新|个人中心|Ta的空间|空间|我的|提示信息|系统提示|温馨提示|提示|抱歉|无权|没有权限|不存在|该用户)$', caseSensitive: false).hasMatch(value.trim());
}

class _Header extends StatelessWidget {
  final ProfileData profile;
  final String username;
  final List<String> badges;
  final VoidCallback onFollow, onChat;
  final bool busy;
  const _Header({required this.profile, required this.username, required this.badges, required this.onFollow, required this.onChat, required this.busy});

  Widget _badge(BuildContext context, String text, IconData icon) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: s.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: s.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: s.primary),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: s.onSurface)),
      ]),
    );
  }

  @override Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [s.primaryContainer, s.surface])),
      child: SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 72, 20, 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: s.surface,
            backgroundImage: profile.avatar.isNotEmpty ? NetworkImage(profile.avatar) : null,
            child: profile.avatar.isEmpty ? Text(username.isEmpty ? '?' : username.characters.first, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)) : null,
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 5, runSpacing: 4, children: [
                for (var i = 0; i < badges.length; i++) _badge(context, badges[i], i == 0 && badges[i].toLowerCase().startsWith('lv') ? Icons.diamond_outlined : Icons.school_outlined),
              ]),
            ],
            const SizedBox(height: 5),
            Text('UID ${profile.uid}', style: TextStyle(fontSize: 12, color: s.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ])),
          const SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.tonalIcon(onPressed: busy ? null : onFollow, icon: Icon(profile.followedByMe ? Icons.check : Icons.person_add_alt_1, size: 18), label: Text(profile.followedByMe ? '已关注' : '关注')),
            const SizedBox(height: 6),
            OutlinedButton.icon(onPressed: onChat, icon: const Icon(Icons.chat_bubble_outline, size: 18), label: const Text('聊天')),
          ]),
        ]),
      )),
    );
  }
}

class _Stats extends StatelessWidget {
  final ProfileData profile;
  const _Stats({required this.profile});

  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _S('主题', '${profile.threads}'),
              _S('回帖', '${profile.replies}'),
              _S('关注', '${profile.following}'),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _S('粉丝', '${profile.followers}'),
              _S('星币', '${profile.credits}'),
              _S('积分', '${profile.points}'),
            ]),
          ],
        ),
      ),
    ),
  );
}

class _S extends StatelessWidget {
  final String a, b;
  const _S(this.a, this.b);

  @override Widget build(BuildContext c) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              b,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          a,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}
class _ThreadCard extends StatelessWidget { final ThreadItem item; const _ThreadCard({required this.item}); @override Widget build(BuildContext context)=>Card(margin:EdgeInsets.zero,clipBehavior:Clip.antiAlias,child:InkWell(onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>DetailPage(tid:item.tid,title:item.title))),child:Padding(padding:const EdgeInsets.all(15),child:Row(children:[Container(width:42,height:42,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primaryContainer,borderRadius:BorderRadius.circular(12)),child:Icon(item.replyCount>0?Icons.forum_outlined:Icons.article_outlined)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(item.title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:6),Row(children:[if(item.boardName.isNotEmpty)Flexible(child:Text(item.boardName,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,color:Theme.of(context).colorScheme.primary))),const SizedBox(width:8),Text('${item.replyCount} 回复 · ${item.viewCount} 浏览',style:TextStyle(fontSize:11,color:Theme.of(context).colorScheme.onSurfaceVariant))])])),const Icon(Icons.chevron_right)])))); }
class _TabHeader extends SliverPersistentHeaderDelegate { final TabBar tab; _TabHeader(this.tab); @override double get minExtent=>54; @override double get maxExtent=>54; @override Widget build(BuildContext c,double s,bool o)=>Material(color:Theme.of(c).colorScheme.surface,child:tab); @override bool shouldRebuild(covariant _TabHeader oldDelegate)=>false; }
class _Empty extends StatelessWidget { const _Empty(); @override Widget build(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.inbox_outlined,size:52,color:Theme.of(c).colorScheme.onSurfaceVariant),const SizedBox(height:10),const Text('暂无内容',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:4),const Text('这里还没有可以展示的主题或回帖',textAlign:TextAlign.center)]))); }
class _Error extends StatelessWidget { final String message; final VoidCallback retry; const _Error({required this.message,required this.retry}); @override Widget build(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off,size:48),const SizedBox(height:12),const Text('个人主页加载失败'),const SizedBox(height:6),Text(message,textAlign:TextAlign.center),const SizedBox(height:14),FilledButton.icon(onPressed:retry,icon:const Icon(Icons.refresh),label:const Text('重试'))]))); }
