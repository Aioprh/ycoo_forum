import 'package:flutter/material.dart';

import '../services/browse_history_service.dart';
import 'detail_page.dart';

/// 浏览历史: 本机保存的帖子浏览记录, 点击可重新进入该帖子。
class BrowseHistoryPage extends StatefulWidget {
  const BrowseHistoryPage({super.key});
  @override
  State<BrowseHistoryPage> createState() => _BrowseHistoryPageState();
}

class _BrowseHistoryPageState extends State<BrowseHistoryPage> {
  List<BrowseHistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await BrowseHistoryService.instance.list();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空浏览历史'),
        content: const Text('将删除本机保存的全部浏览记录, 确定继续吗?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await BrowseHistoryService.instance.clear();
    if (mounted) setState(() => _entries = const []);
  }

  void _open(BrowseHistoryEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(tid: entry.tid, title: entry.title)));
  }

  String _timeText(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('浏览历史'),
        actions: [if (_entries.isNotEmpty) TextButton(onPressed: _clear, child: const Text('清空'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _empty(scheme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _tile(scheme, _entries[index]),
                  ),
                ),
    );
  }

  Widget _empty(ColorScheme scheme) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_rounded, size: 46, color: scheme.primary.withValues(alpha: .6)),
          const SizedBox(height: 12),
          const Text('还没有浏览记录', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('打开过的帖子会自动记录在这里', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ]),
      );

  Widget _tile(ColorScheme scheme, BrowseHistoryEntry entry) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(entry),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.article_outlined, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    entry.title.isEmpty ? '帖子 ${entry.tid}' : entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [if (entry.boardName.isNotEmpty) entry.boardName, _timeText(entry.time)].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
      );
}