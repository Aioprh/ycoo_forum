import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../pages/detail_page.dart';
import '../services/api_service.dart';
import '../widgets/native_image_viewer.dart';
import '../widgets/native_post_content.dart';
import 'thread_card.dart';

typedef ThreadsLoader = Future<List<ThreadItem>> Function(int page);

class ThreadListView extends StatefulWidget {
  final ThreadsLoader loader;
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
  final Map<int, List<String>> _fullImageCache = <int, List<String>>{};

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
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 160) {
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

  Future<void> _openImage(ThreadItem item, int index) async {
    final cached = _fullImageCache[item.tid];
    if (cached != null && cached.isNotEmpty) {
      final targetIndex = _matchImageIndex(item.covers[index], cached, index, item.covers.length);
      if (!mounted) return;
      await openImageViewer(
        context,
        url: cached[targetIndex],
        gallery: cached,
      );
      return;
    }

    // 列表缩略图可能已经被论坛裁剪，列表页本身不一定提供可靠的原图地址。
    // 点击时读取帖子正文，用正文实际渲染的图片 URL 作为原图来源。
    try {
      final detail = await ApiService.instance.fetchThreadDetail(item.tid);
      final images = postImageUrls(detail.bodyHtml);
      if (images.isNotEmpty) {
        _fullImageCache[item.tid] = images;
        final targetIndex = _matchImageIndex(item.covers[index], images, index, item.covers.length);
        if (!mounted) return;
        await openImageViewer(
          context,
          url: images[targetIndex],
          gallery: images,
        );
        return;
      }
    } catch (_) {
      // 正文读取失败时继续使用列表已有地址兜底。
    }

    if (!mounted) return;
    final gallery = item.fullCovers.length == item.covers.length
        ? item.fullCovers
        : item.covers;
    final targetIndex = index < gallery.length ? index : 0;
    if (gallery.isEmpty) return;
    await openImageViewer(
      context,
      url: gallery[targetIndex],
      gallery: gallery,
    );
  }

  int _matchImageIndex(String thumbnail, List<String> originals, int fallback, int sourceCount) {
    final thumbKey = _imageIdentity(thumbnail);
    if (thumbKey.isNotEmpty) {
      for (var i = 0; i < originals.length; i++) {
        if (_imageIdentity(originals[i]) == thumbKey) return i;
      }
    }

    // 如果 URL 本身无法建立映射，而两边数量一致，保持列表对应位置。
    if (originals.length == sourceCount) {
      return fallback < 0 ? 0 : (fallback >= originals.length ? originals.length - 1 : fallback);
    }

    // 无法确定映射时优先显示第一张正文原图，避免再次打开裁剪缩略图。
    return 0;
  }

  String _imageIdentity(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return '';
    var path = uri.path;
    if (path.isEmpty) return '';
    var name = path.substring(path.lastIndexOf('/') + 1).toLowerCase();
    name = name
        .replaceAll(RegExp(r'([_-](?:thumb|thumbnail|small|middle|medium|large))(?=\.)'), '')
        .replaceAll(RegExp(r'([_-]\d{2,4}x\d{2,4})(?=\.)'), '');
    return name;
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
        padding: widget.padding ?? const EdgeInsets.fromLTRB(14, 6, 14, 24),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i >= _items.length) return _footer(context);
          final item = _items[i];
          return ThreadCard(
            item: item,
            onTap: () => _openDetail(item),
            onImageTap: (index) => _openImage(item, index),
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final hint = Theme.of(context).colorScheme.onSurfaceVariant;
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
        padding: const EdgeInsets.all(14),
        child: Center(child: Text('加载失败，点击下拉重试', style: TextStyle(color: hint))),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(child: Text('暂无帖子', style: TextStyle(color: hint))),
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
    final hint = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 42, color: hint),
          const SizedBox(height: 10),
          const Text('数据加载失败', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(error, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hint)),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
