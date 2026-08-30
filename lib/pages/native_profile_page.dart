import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/profile_service.dart';
import 'detail_page.dart';

class NativeProfilePage extends StatefulWidget {
  final int uid;
  final String? username;
  const NativeProfilePage({super.key, required this.uid, this.username});
  @override
  State<NativeProfilePage> createState() => _NativeProfilePageState();
}

class _NativeProfilePageState extends State<NativeProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  ProfileData? _profile;
  List<ThreadItem> _items = const [];
  bool _loading = true;
  bool _loadingList = false;
  bool _followBusy = false;
  String? _error;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged); _load(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }
  void _tabChanged() { if (!_tabs.indexIsChanging) _loadList(replies: _tabs.index == 1); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { _profile = await ProfileService.instance.fetchProfile(widget.uid); await _loadList(replies: _tabs.index == 1); }
    catch (e) { _error = e.toString().replaceFirst('Exception: ', ''); }
    if (mounted) setState(() => _loading = false);
  }
  Future<void> _loadList({required bool replies}) async {
    if (!mounted) return;
    setState(() => _loadingList = true);
    try { final list = await ProfileService.instance.fetchThreads(widget.uid, replies: replies); if (mounted) setState(() => _items = list); }
    catch (_) { if (mounted) setState(() => _items = const []); }
    if (mounted) setState(() => _loadingList = false);
  }
  Future<void> _follow() async {
    if (_followBusy || _profile == null) return;
    final next = !_profile!.followedByMe;
    setState(() => _followBusy = true);
    final err = await ProfileService.instance.setFollow(widget.uid, next);
    if (!mounted) return;
    setState(() => _followBusy = false);
    if (err != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err))); return; }
    setState(() { final p = _profile!; _profile = ProfileData(uid: p.uid, username: p.username, avatar: p.avatar, group: p.group, signature: p.signature, threads: p.threads, replies: p.replies, following: p.following + (next ? 1 : -1), followers: p.followers, credits: p.credits, points: p.points, followingMe: p.followingMe, followedByMe: next); });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null && _profile == null) return Scaffold(appBar: AppBar(), body: _Error(message: _error!, retry: _load));
    final p = _profile!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(expandedHeight: 250, pinned: true, stretch: true, title: Text(p.username), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))], flexibleSpace: FlexibleSpaceBar(background: _Header(profile: p, onFollow: _follow, busy: _followBusy))),
          SliverToBoxAdapter(child: _Stats(profile: p)),
          SliverPersistentHeader(pinned: true, delegate: _TabHeader(TabBar(controller: _tabs, tabs: const [Tab(icon: Icon(Icons.article_outlined), text: '主题'), Tab(icon: Icon(Icons.forum_outlined), text: '回帖')]))),
          if (_loadingList) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          if (!_loadingList && _items.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: _Empty()),
          if (_items.isNotEmpty) SliverPadding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), sliver: SliverList.builder(itemCount: _items.length, itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _ThreadCard(item: _items[i])))),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ProfileData profile; final VoidCallback onFollow; final bool busy;
  const _Header({required this.profile, required this.onFollow, required this.busy});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.surface])),
    child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 70, 20, 18), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      CircleAvatar(radius: 38, backgroundColor: Theme.of(context).colorScheme.surface, backgroundImage: profile.avatar.isNotEmpty ? NetworkImage(profile.avatar) : null, child: profile.avatar.isEmpty ? Text(profile.username.isEmpty ? '?' : profile.username.characters.first, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)) : null),
      const SizedBox(width: 14), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(profile.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), if (profile.group.isNotEmpty) Text(profile.group, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)), if (profile.signature.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(profile.signature, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))])),
      if ((profile.uid != 0) && (profile.uid != (profile.uid == 0 ? -1 : -2))) FilledButton.tonalIcon(onPressed: busy ? null : onFollow, icon: Icon(profile.followedByMe ? Icons.check : Icons.person_add_alt_1), label: Text(profile.followedByMe ? '已关注' : '关注')),
    ])),
  );
}

class _Stats extends StatelessWidget { final ProfileData profile; const _Stats({required this.profile});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Row(children: [
    _S('主题', '${profile.threads}'), _S('回帖', '${profile.replies}'), _S('关注', '${profile.following}'), _S('粉丝', '${profile.followers}'), _S('星币', '${profile.credits}'), _S('积分', '${profile.points}'),
  ]))));
}
class _S extends StatelessWidget { final String a,b; const _S(this.a,this.b); @override Widget build(BuildContext c) => Expanded(child: Column(children: [Text(b, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 3), Text(a, style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant))])); }

class _ThreadCard extends StatelessWidget { final ThreadItem item; const _ThreadCard({required this.item});
  @override Widget build(BuildContext context) => Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: item.title))), child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
    Container(width: 42, height: 42, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(item.replyCount > 0 ? Icons.forum_outlined : Icons.article_outlined)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), Row(children: [if (item.boardName.isNotEmpty) Flexible(child: Text(item.boardName, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary))), const SizedBox(width: 8), Text('${item.replyCount} 回复 · ${item.viewCount} 浏览', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))])])), const Icon(Icons.chevron_right),
  ]))));
}

class _TabHeader extends SliverPersistentHeaderDelegate { final TabBar tab; _TabHeader(this.tab); @override double get minExtent => 54; @override double get maxExtent => 54; @override Widget build(BuildContext c,double s,bool o)=>Material(color:Theme.of(c).colorScheme.surface,child:tab); @override bool shouldRebuild(c)=>false; }
class _Empty extends StatelessWidget { const _Empty(); @override Widget build(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.inbox_outlined,size:52),const SizedBox(height:10),Text('暂无内容',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:4),Text('这里还没有可以展示的主题或回帖',textAlign:TextAlign.center)]))); }
class _Error extends StatelessWidget { final String message; final VoidCallback retry; const _Error({required this.message,required this.retry}); @override Widget build(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off,size:48),const SizedBox(height:12),Text('个人主页加载失败'),const SizedBox(height:6),Text(message,textAlign:TextAlign.center),const SizedBox(height:14),FilledButton.icon(onPressed:retry,icon:const Icon(Icons.refresh),label:const Text('重试'))]))); }
