import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/api_service.dart';
import '../services/site_fallback_service.dart';
import '../widgets/thread_list_view.dart';
import 'search_page.dart';

/// 首页：更偏社区阅读体验的原生首页。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _tabs = <(String, String, IconData)>[
    ('最新', 'newthread', Icons.auto_awesome_rounded),
    ('最新回复', 'newreply', Icons.forum_rounded),
    ('热门', 'digest', Icons.local_fire_department_rounded),
  ];
  int _index = 0;

  Future<List<ThreadItem>> _load(String view) async {
    final url = ApiService.guideUrl(view);
    try {
      final primary = await ApiService.instance.fetchThreads(url);
      if (primary.isNotEmpty) return primary;
    } catch (_) {
      // 站点模板/网络异常时继续走兼容解析器。
    }
    return SiteFallbackService.instance.fetchThreads(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final view = _tabs[_index].$2;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context, scheme)),
            SliverToBoxAdapter(child: _buildSearch(context, scheme)),
            SliverToBoxAdapter(child: _buildSectionHeader(context, scheme)),
            SliverToBoxAdapter(child: _buildTabs(context, scheme)),
            SliverFillRemaining(
              hasScrollBody: true,
              child: ThreadListView(
                key: ValueKey(view),
                paginate: false,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                loader: (_) => _load(view),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '源论坛',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '发现新内容，和大家聊聊',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Material(
            color: scheme.primaryContainer,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchPage()),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.search_rounded, size: 22),
              ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchPage()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: Colors.grey.shade500, size: 21),
                const SizedBox(width: 10),
                Text('搜索帖子、用户或版块', style: TextStyle(color: Colors.grey.shade500)),
                const Spacer(),
                Icon(Icons.tune_rounded, color: scheme.primary, size: 19),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 9),
          const Text('社区动态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w750)),
          const Spacer(),
          Text('实时更新', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildTabs(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
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
      color: selected ? scheme.primary : Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: selected ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _index = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_tabs[index].$3, size: 16, color: selected ? scheme.onPrimary : scheme.primary),
              const SizedBox(width: 5),
              Text(
                _tabs[index].$1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onPrimary : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
