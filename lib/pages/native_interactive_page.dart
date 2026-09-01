import 'package:flutter/material.dart';

import '../services/actionable_notice_service.dart';
import '../services/member_service_v2.dart';
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
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                      child: Icon(item.icon, color: scheme.primary, size: 27),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(item.subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: scheme.outline, size: 28),
                  ],
                ),
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
  late Future<List<NativeNotice>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<NativeNotice>> _load() => ActionableNoticeService.instance.fetch(view: 'interactive', type: widget.type.type);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Uri? _uri(String href) {
    final raw = href.trim();
    if (raw.isEmpty || raw.startsWith('#') || raw.toLowerCase().startsWith('javascript:')) return null;
    final base = Uri.parse(SiteConfig.base);
    try {
      var uri = base.resolve(raw);
      if (uri.path.toLowerCase().endsWith('/space.php')) {
        uri = uri.replace(path: '/home.php');
      }
      if ((uri.path.isEmpty || uri.path == '/') && uri.queryParameters.containsKey('mod')) {
        uri = uri.replace(path: '/home.php');
      }
      return uri;
    } catch (_) {
      return Uri.tryParse(raw);
    }
  }

  Future<void> _open(NativeNotice item) async {
    if (!mounted) return;
    if (item.tid > 0) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: forumText(item.title))));
      return;
    }
    final uri = _uri(item.href);
    final uid = item.uid > 0 ? item.uid : _uid(uri);
    if (uid > 0) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NativeProfilePage(uid: uid, username: '')));
      return;
    }
    if (uri != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewPage(url: uri.toString(), title: forumText(item.title))));
      return;
    }
    if (mounted) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Text(forumText(item.body.isNotEmpty ? item.body : item.subtitle), style: const TextStyle(fontSize: 16, height: 1.5)))),
      );
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

  IconData _noticeIcon() => widget.type.icon;

  String _action(NativeNotice item) {
    if (item.tid > 0) return '打开帖子并继续互动';
    if (item.uid > 0) {
      switch (widget.type.type) {
        case 'post': return '查看坛友并处理打招呼';
        case 'friend': return '查看坛友并处理好友';
        case 'wall': return '查看坛友并处理留言';
        case 'comment': return '查看评论来源';
        case 'click': return '查看坛友';
        case 'sharenotice': return '查看分享来源';
      }
    }
    return '查看提醒';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(widget.type.title), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<NativeNotice>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_rounded, size: 48), const SizedBox(height: 12), Text(forumText(snapshot.error.toString().replaceFirst('Exception: ', '')), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('重试'))])));
          final items = snapshot.data ?? const <NativeNotice>[];
          if (items.isEmpty) return RefreshIndicator(onRefresh: _refresh, child: ListView(children: const [SizedBox(height: 260), Center(child: Text('暂无互动提醒'))]));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(item),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(backgroundColor: scheme.primaryContainer, foregroundColor: scheme.primary, child: Icon(_noticeIcon())),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(forumText(item.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 5),
                          Text(forumText(item.subtitle), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
                          const SizedBox(height: 8),
                          Text(_action(item), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                        ])),
                        const Icon(Icons.chevron_right_rounded),
                      ]),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
