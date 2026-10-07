import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/site_fallback_service.dart';
import '../widgets/thread_list_view.dart';
import 'create_group_thread_page.dart';
import 'create_thread_page.dart';
import 'detail_page.dart';
import 'login_page.dart';
import 'search_page.dart';
import 'thread_list_page.dart';
import 'upload_album_page.dart';
import 'write_blog_page.dart';
import 'write_doing_page.dart';

/// 首页：更偏社区阅读体验的原生首页。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _tabs = <(String, String, IconData)>[
    ('最新', 'newthread', Icons.auto_awesome_rounded),
    ('最新回复', 'new', Icons.forum_rounded),
    ('热门', 'hot', Icons.local_fire_department_rounded),
  ];
  int _index = 0;
  List<PinnedThread> _pinned = const <PinnedThread>[];

  @override
  void initState() {
    super.initState();
    _loadPinned();
  }

  /// 加载官方置顶帖(站务公告版块顶部置顶列表)。
  Future<void> _loadPinned() async {
    try {
      final items = await ApiService.instance.fetchPinnedThreads();
      if (!mounted) return;
      setState(() => _pinned = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pinned = const <PinnedThread>[]);
    }
  }

  Future<List<ThreadItem>> _load(String view) async {
    final baseUrl = ApiService.guideUrl(view);
    final url = view == 'hot' ? '$baseUrl&index=1' : baseUrl;
    try {
      final primary = await ApiService.instance.fetchThreads(url);
      if (primary.isNotEmpty) return primary;
    } catch (_) {}
    return SiteFallbackService.instance.fetchThreads(url);
  }

  Future<void> _ensureLoggedIn() async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn && mounted) {
      final login = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (login != true || !mounted) return;
    }
  }

  Future<void> _openCompose() async {
    final route = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            leading: Icon(Icons.edit_note_rounded),
            title: Text('发布内容', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('选择要发布的内容类型'),
          ),
          ListTile(leading: const Icon(Icons.forum_outlined), title: const Text('发帖', style: TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('在论坛版块发布新主题'), onTap: () => Navigator.pop(context, 'thread')),
          ListTile(leading: const Icon(Icons.groups_rounded), title: const Text('发圈子', style: TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('在圈子/群组发布主题'), onTap: () => Navigator.pop(context, 'group')),
          ListTile(leading: const Icon(Icons.self_improvement_rounded), title: const Text('记心情', style: TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('一句话记录当前状态'), onTap: () => Navigator.pop(context, 'doing')),
          ListTile(leading: const Icon(Icons.article_outlined), title: const Text('写日志', style: TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('在空间发布一篇日志'), onTap: () => Navigator.pop(context, 'blog')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('发相册', style: TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('上传图片到个人相册'), onTap: () => Navigator.pop(context, 'album')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || route == null) return;
    await _ensureLoggedIn();
    if (!mounted) return;
    Widget page;
    switch (route) {
      case 'thread': page = const CreateThreadPage(); break;
      case 'group': page = const CreateGroupThreadPage(); break;
      case 'doing': page = const WriteDoingPage(); break;
      case 'blog': page = const WriteBlogPage(); break;
      case 'album': page = const UploadAlbumPage(); break;
      default: return;
    }
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
    if (done == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final view = _tabs[_index].$2;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, scheme),
            _buildSearch(context, scheme),
            if (_pinned.isNotEmpty) _buildPinned(context, scheme),
            _buildSectionHeader(context, scheme),
            _buildTabs(context, scheme),
            Expanded(
              child: ThreadListView(
                key: ValueKey(view), paginate: false,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                loader: (_) => _load(view),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCompose,
        icon: const Icon(Icons.add_rounded),
        label: const Text('发布'),
        tooltip: '发布内容',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('源论坛', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Text('发现新内容，和大家聊聊', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ]),
          ),
          Material(
            color: scheme.primaryContainer,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
              child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.search_rounded, size: 22)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: scheme.surface, borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55))),
            child: Row(children: [
              Icon(Icons.search_rounded, color: scheme.onSurfaceVariant, size: 21), const SizedBox(width: 10),
              Text('搜索帖子、用户或版块', style: TextStyle(color: scheme.onSurfaceVariant)), const Spacer(),
              Icon(Icons.tune_rounded, color: scheme.primary, size: 19),
            ]),
          ),
        ),
      ),
    );
  }

  /// 官方置顶帖区域: 展示站务公告版块的置顶帖, 点击进入帖子详情。
  Widget _buildPinned(BuildContext context, ColorScheme scheme) {
    const maxVisible = 3;
    final visible = _pinned.take(maxVisible).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: .32),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.primary.withValues(alpha: .18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.push_pin_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('官方置顶', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: scheme.primary)),
              const Spacer(),
              if (_pinned.length > maxVisible)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openAnnouncementBoard(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('更多', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary)),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            for (final item in visible) _pinnedRow(context, scheme, item),
          ],
        ),
      ),
    );
  }

  Widget _pinnedRow(BuildContext context, ColorScheme scheme, PinnedThread item) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: item.title)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(5)),
            child: Text('置顶', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onPrimary)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  void _openAnnouncementBoard(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BoardThreadListPage(fid: ApiService.announcementFid, filter: '站务公告'),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 9), const Text('社区动态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const Spacer(),
        Text('实时更新', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ]),
    );
  }

  Widget _buildTabs(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            Expanded(child: _tab(i, scheme)),
            if (i != _tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _tab(int index, ColorScheme scheme) {
    final selected = _index == index;
    return Material(
      color: selected ? scheme.primary : scheme.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: selected ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _index = index),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 20,
                child: Center(child: Icon(_tabs[index].$3, size: 16, color: selected ? scheme.onPrimary : scheme.primary)),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 18,
                child: Center(
                  child: Text(
                    _tabs[index].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    strutStyle: const StrutStyle(fontSize: 13, height: 1.25, forceStrutHeight: true),
                    style: TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w700, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
