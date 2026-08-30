import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/api_service.dart';
import '../services/site_fallback_service.dart';
import 'thread_list_page.dart';

/// 版块页:分类 → 子版块网格,点击进入帖子列表。
class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  late Future<List<ForumCategory>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadBoards();
  }

  Future<List<ForumCategory>> _loadBoards() async {
    try {
      final primary = await ApiService.instance.fetchBoards();
      if (primary.isNotEmpty) return primary;
    } catch (_) {
      // 模板发生变化时使用稳定 fid 链接兜底。
    }
    return SiteFallbackService.instance.fetchBoards();
  }

  void _reload() => setState(() => _future = _loadBoards());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('社区')),
      body: FutureBuilder<List<ForumCategory>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('版块加载失败'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            );
          }
          final cats = snap.data ?? [];
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [for (final cat in cats) _category(context, cat)],
            ),
          );
        },
      ),
    );
  }

  /// 网站原始版块名称有时会把“今日: N / 帖数: N”一起放进链接文本。
  /// App 卡片已经单独展示统计信息，因此标题只保留纯版块名。
  String _displayBoardName(ForumBoard board) {
    var name = board.name.replaceAll(RegExp(r'\s+'), ' ').trim();
    name = name.replaceAll(RegExp(r'\s*(?:今日|今天)\s*[:：]?\s*\d+'), '');
    name = name.replaceAll(RegExp(r'\s*(?:帖子数|贴数|主题数|帖数)\s*[:：]?\s*\d+'), '');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name.isEmpty ? board.name : name;
  }

  Widget _category(BuildContext context, ForumCategory cat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            cat.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        _grid(context, cat.boards),
      ],
    );
  }

  Widget _grid(BuildContext context, List<ForumBoard> boards) {
    final theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.25,
      ),
      itemCount: boards.length,
      itemBuilder: (context, i) {
        final b = boards[i];
        final displayName = _displayBoardName(b);
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  BoardThreadListPage(fid: b.fid, filter: displayName),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (b.icon.isNotEmpty)
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(b.icon),
                    onBackgroundImageError: (_, _) {},
                    child: const Icon(Icons.forum_outlined, size: 18),
                  )
                else
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    child: Icon(
                      Icons.forum_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (b.today.isNotEmpty)
                  Text(
                    b.today,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
