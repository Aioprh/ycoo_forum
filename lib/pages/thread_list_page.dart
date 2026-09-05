import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/thread_item.dart';
import '../services/api_service.dart';
import '../services/site_fallback_service.dart';
import '../widgets/thread_list_view.dart';

/// 版块帖子列表页：带分页，并展示网页端的「主题分类」筛选标签。
class BoardThreadListPage extends StatefulWidget {
  final int fid;
  final String filter;

  const BoardThreadListPage({super.key, required this.fid, required this.filter});

  @override
  State<BoardThreadListPage> createState() => _BoardThreadListPageState();
}

class _BoardThreadListPageState extends State<BoardThreadListPage> {
  List<ForumTypeTag> _types = const [];
  int _typeid = 0; // 0 表示「全部」

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final tags = await ApiService.instance.fetchForumTypes(widget.fid);
      if (!mounted) return;
      setState(() => _types = tags);
    } catch (_) {
      // 无法解析分类时保持为空，帖子流仍照常显示。
    }
  }

  Future<List<ThreadItem>> _load(int page) async {
    final url = ApiService.forumUrl(widget.fid, page, typeid: _typeid);
    try {
      final primary = await ApiService.instance.fetchThreads(url);
      if (primary.isNotEmpty) return primary;
    } catch (_) {
      // 站点模板变化或请求异常时继续使用兼容解析器。
    }
    return SiteFallbackService.instance.fetchThreads(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.filter)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_types.isNotEmpty) _typeBar(context),
            Expanded(
              child: ThreadListView(
                // typeid 变化时重建，让列表按新分类重新从第 1 页加载。
                key: ValueKey<int>(_typeid),
                paginate: true,
                loader: _load,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分类筛选栏：采用截图所示的横向胶囊标签布局。
  ///
  /// 不强行把所有分类压缩进屏幕，而是保留每个标签自己的可读宽度，
  /// 分类较多时横向滑动，字体放大时也不会因为固定宽度而挤压换行。
  Widget _typeBar(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        itemCount: _types.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _tagChip(context, 0, '全部');
          }
          final tag = _types[index - 1];
          return _tagChip(context, tag.typeid, tag.name);
        },
      ),
    );
  }

  Widget _tagChip(BuildContext context, int typeid, String name) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = typeid == _typeid;

    return Semantics(
      button: true,
      selected: selected,
      label: '主题分类$name',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            if (typeid == _typeid) return;
            setState(() => _typeid = typeid);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? scheme.primaryContainer : scheme.outlineVariant,
                width: selected ? 1 : 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
