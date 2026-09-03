import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/site_fallback_service.dart';
import '../widgets/thread_list_view.dart';
import 'create_thread_page.dart';
import 'login_page.dart';
import 'search_page.dart';

/// 首页：更偏社区阅读体验的原生首页。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Discuz 导读的合法 view 参数：newthread=最新发表、new=最新回复、hot=热门。
  static const _tabs = <(String, String, IconData)>[
    ('最新', 'newthread', Icons.auto_awesome_rounded),
    ('最新回复', 'new', Icons.forum_rounded),
    ('热门', 'hot', Icons.local_fire_department_rounded),
  ];
  int _index = 0;

  Future<List<ThreadItem>> _load(String view) async {
    // 保持 7c13372 验证过的移动端导读数据源。
    final url = ApiService.guideUrl(view);
    try {
      final primary = await ApiService.instance.fetchThreads(url);
      if (primary.isNotEmpty) return primary;
    } catch (_) {}
    return SiteFallbackService.instance.fetchThreads(url);
  }

  Future<void> _createThread() async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) {
      if (!mounted) return;
      final login = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (login != true || !mounted) return;
    }
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreateThreadPage()));
    if (created == true && mounted) setState(() {});
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
        onPressed: _createThread,
        icon: const Icon(Icons.add_rounded),
        label: const Text('发帖'),
        tooltip: '发布帖子',
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

  /// 三个 Tab 使用完全一致的内部网格：图标区域固定、文字区域固定高度，
  /// 从而避免“最新回复”较长时把文字视觉位置撑偏。
  Widget _buildTabs(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                child: Center(
                  child: Icon(
                    _tabs[index].$3,
                    size: 16,
                    color: selected ? scheme.onPrimary : scheme.primary,
                  ),
                ),
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
                    strutStyle: const StrutStyle(
                      fontSize: 13,
                      height: 1.25,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
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
