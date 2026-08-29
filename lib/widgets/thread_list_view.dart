import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../pages/detail_page.dart';
import 'thread_card.dart';

/// 帖子列表加载器:按页码抓取一页帖子。
/// 导读类(不翻页)可忽略 page 参数,恒返回第 1 页。
typedef ThreadsLoader = Future<List<ThreadItem>> Function(int page);

/// 通用帖子列表:下拉刷新 + 上滑分页(可禁用)。
class ThreadListView extends StatefulWidget {
  final ThreadsLoader loader;

  /// 是否支持上滑翻页(版块列表用 true,导读单页用 false)。
  final bool paginate;
  final EdgeInsets? padding;

  const ThreadListView({
    super.key,
    required this.loader,
    this.paginate = true,
    this.padding,
  });

  @override
  State<ThreadListView> createState() => _ThreadListViewState();
}

class _ThreadListViewState extends State<ThreadListView> {
  final List<ThreadItem> _items = [];
  final ScrollController _scroll = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.paginate &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    _page = 1;
    _hasMore = true;
    await _fetch(refresh: true);
  }

  Future<void> _loadMore() async {
    if (!widget.paginate || _loading || !_hasMore) return;
    await _fetch(refresh: false);
  }

  Future<void> _fetch({required bool refresh}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.loader(_page);
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items
            ..clear()
            ..addAll(data);
        } else {
          _items.addAll(data);
        }
        _page++;
        if (data.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetail(ThreadItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(tid: item.tid, title: item.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding ?? const EdgeInsets.only(bottom: 12),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return _footer();
          }
          final item = _items[i];
          return ThreadCard(item: item, onTap: () => _openDetail(item));
        },
      ),
    );
  }

  Widget _footer() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: EdgeInsets.all(14),
        child: Center(
          child: GestureDetector(
            onTap: _loadMore,
            child: Text('加载失败,点击重试', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: Text('暂无帖子', style: TextStyle(color: Colors.grey))),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 42, color: Colors.grey),
          const SizedBox(height: 10),
          const Text('数据加载失败', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}