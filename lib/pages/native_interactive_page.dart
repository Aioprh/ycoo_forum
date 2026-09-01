import 'package:flutter/material.dart';

import '../services/actionable_notice_service.dart';
import '../services/site_config.dart';
import '../utils/forum_text.dart';
import 'detail_page.dart';
import 'native_profile_page.dart';
import 'webview_page.dart';

class NativeInteractivePage extends StatelessWidget {
  const NativeInteractivePage({super.key});

  static const _items = <_InteractiveType>[
    _InteractiveType('打招呼', 'post', Icons.waving_hand_rounded, '收到的打招呼'),
    _InteractiveType('好友', 'friend', Icons.person_add_alt_1_rounded, '好友请求与好友互动'),
    _InteractiveType('留言', 'wall', Icons.edit_note_rounded, '个人空间留言'),
    _InteractiveType('评论', 'comment', Icons.chat_bubble_rounded, '收到的评论与点评'),
    _InteractiveType('挺你', 'click', Icons.thumb_up_alt_rounded, '收到的支持与赞'),
    _InteractiveType('分享', 'sharenotice', Icons.share_rounded, '内容被分享的提醒'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('坛友互动')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _items[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeInteractiveTypePage(type: item))),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(item.icon, color: scheme.primary, size: 27),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(item.subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ])),
                  Icon(Icons.chevron_right_rounded, color: scheme.outline, size: 28),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InteractiveType {
  final String title;
  final String type;
  final IconData icon;
  final String subtitle;
  const _InteractiveType(this.title, this.type, this.icon, this.subtitle);
}

class NativeInteractiveTypePage extends StatefulWidget {
  final _InteractiveType type;
  const NativeInteractiveTypePage({super.key, required this.type});

  @override
  State<NativeInteractiveTypePage> createState() => _NativeInteractiveTypePageState();
}

class _NativeInteractiveTypePageState extends State<NativeInteractiveTypePage> {
  late Future<InteractiveNoticePage> _future;
  int _page = 1;
  final List<InteractiveNotice> _items = [];
  bool _hasNext = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _future = _loadFirst();
  }

  Future<InteractiveNoticePage> _loadFirst() async {
    final page = await ActionableNoticeService.instance.fetchInteractivePage(type: widget.type.type, page: 1);
    _items
      ..clear()
      ..addAll(page.items);
    _page = 1;
    _hasNext = page.hasNext;
    return page;
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadFirst());
    await _future;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ActionableNoticeService.instance.fetchInteractivePage(type: widget.type.type, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page = next.page;
        _hasNext = next.hasNext;
        _items.addAll(next.items);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumText(e.toString().replaceFirst('Exception: ', '')))));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Uri? _uri(String href) {
    final raw = href.trim();
    if (raw.isEmpty || raw.startsWith('#') || raw.toLowerCase().startsWith('javascript:')) return null;
    final base = Uri.parse(SiteConfig.base);
    try {
      var uri = base.resolve(raw);
      if (uri.path.toLowerCase().endsWith('/space.php')) uri = uri.replace(path: '/home.php');
      if ((uri.path.isEmpty || uri.path == '/') && uri.queryParameters.containsKey('mod')) uri = uri.replace(path: '/home.php');
      return uri;
    } catch (_) {
      return Uri.tryParse(raw);
    }
  }

  int _uid(Uri? uri) {
    if (uri == null) return 0;
    final value = int.tryParse(uri.queryParameters['uid'] ?? '');
    if (value != null && value > 0) return value;
    final decoded = Uri.decodeFull(uri.toString());
    final match = RegExp(r'(?:[?&]|%3F|%26)uid(?:=|%3D)(\d+)', caseSensitive: false).firstMatch(decoded);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  int _tid(Uri? uri) {
    if (uri == null) return 0;
    final value = int.tryParse(uri.queryParameters['tid'] ?? uri.queryParameters['topicid'] ?? '');
    if (value != null && value > 0) return value;
    final match = RegExp(r'thread-(\d+)', caseSensitive: false).firstMatch(uri.toString());
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<void> _open(InteractiveNotice item, {String? overrideHref}) async {
    final href = (overrideHref ?? item.notice.href).trim();
    final uri = _uri(href);
    final tid = item.notice.tid > 0 ? item.notice.tid : _tid(uri);
    final uid = item.notice.uid > 0 ? item.notice.uid : _uid(uri);
    if (!mounted) return;
    if (tid > 0) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(tid: tid, title: forumText(item.notice.title))));
      return;
    }
    if (uid > 0) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NativeProfilePage(uid: uid, username: item.actor)));
      return;
    }
    if (uri != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewPage(url: uri.toString(), title: forumText(item.notice.title))));
      return;
    }
    _showBody(item);
  }

  void _showBody(InteractiveNotice item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(forumText(item.notice.title), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          if (item.time.isNotEmpty) ...[const SizedBox(height: 6), Text(item.time)],
          const SizedBox(height: 12),
          Text(forumText(item.notice.body.isNotEmpty ? item.notice.body : item.notice.subtitle), style: const TextStyle(fontSize: 16, height: 1.5)),
        ]),
      )),
    );
  }

  String _actionHint() {
    switch (widget.type.type) {
      case 'post': return '查看坛友并处理打招呼';
      case 'friend': return '查看坛友并处理好友关系';
      case 'wall': return '查看留言来源';
      case 'comment': return '打开评论来源';
      case 'click': return '查看获赞内容';
      case 'sharenotice': return '查看被分享内容';
      default: return '查看提醒';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(widget.type.title), actions: [IconButton(onPressed: _refresh, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<InteractiveNoticePage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 48),
                const SizedBox(height: 12),
                Text(forumText(snapshot.error.toString().replaceFirst('Exception: ', '')), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('重试')),
              ]),
            ));
          }
          if (_items.isEmpty) return RefreshIndicator(onRefresh: _refresh, child: ListView(children: const [SizedBox(height: 260), Center(child: Text('暂无互动提醒'))]));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 320) _loadMore();
                return false;
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                itemCount: _items.length + (_hasNext || _loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  if (index >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: _loadingMore ? const CircularProgressIndicator() : OutlinedButton.icon(onPressed: _loadMore, icon: const Icon(Icons.expand_more), label: Text('加载第 ${_page + 1} 页'))),
                    );
                  }
                  return _buildCard(context, _items[index], scheme);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(BuildContext context, InteractiveNotice item, ColorScheme scheme) {
    final title = forumText(item.notice.title);
    final subtitle = forumText(item.notice.subtitle);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: item.unread ? 1.5 : 0.5,
      child: InkWell(
        onTap: () => _open(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                CircleAvatar(backgroundColor: scheme.primaryContainer, foregroundColor: scheme.primary, child: Icon(widget.type.icon)),
                if (item.unread) Positioned(right: 0, top: 0, child: Container(width: 9, height: 9, decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle))),
              ]),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  if (item.unread) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(20)), child: Text('未读', style: TextStyle(color: scheme.onErrorContainer, fontSize: 11, fontWeight: FontWeight.w700))),
                ]),
                if (item.actor.isNotEmpty) ...[const SizedBox(height: 3), Text(item.actor, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600))],
                if (subtitle.isNotEmpty) ...[const SizedBox(height: 5), Text(subtitle, maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35))],
              ])),
              const Icon(Icons.chevron_right_rounded),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(_actionHint(), style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w700))),
              if (item.actions.isNotEmpty)
                PopupMenuButton<InteractiveNoticeAction>(
                  tooltip: '操作',
                  onSelected: (action) => _open(item, overrideHref: action.href),
                  itemBuilder: (_) => item.actions.map((action) => PopupMenuItem(value: action, child: Text(forumText(action.label)))).toList(),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
