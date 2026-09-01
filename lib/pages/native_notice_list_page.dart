import 'package:flutter/material.dart';

import '../services/actionable_notice_service.dart';
import '../services/member_service_v2.dart';
import '../services/site_config.dart';
import '../utils/forum_text.dart';
import 'detail_page.dart';
import 'native_profile_page.dart';
import 'webview_page.dart';

class NativeNoticeListPage extends StatefulWidget {
  final String title;
  final String view;
  const NativeNoticeListPage({super.key, required this.title, required this.view});
  @override
  State<NativeNoticeListPage> createState() => _NativeNoticeListPageState();
}

class _NativeNoticeListPageState extends State<NativeNoticeListPage> {
  late Future<List<NativeNotice>> _future;

  @override
  void initState() {
    super.initState();
    _future = ActionableNoticeService.instance.fetch(view: widget.view);
  }

  Future<void> _refresh() async {
    setState(() => _future = ActionableNoticeService.instance.fetch(view: widget.view));
    await _future;
  }

  Uri? _actionUri(String href) {
    final raw = href.trim();
    if (raw.isEmpty || raw.startsWith('#') || raw.toLowerCase().startsWith('javascript:')) return null;
    final base = Uri.parse(SiteConfig.base);
    Uri? uri;
    try {
      uri = base.resolve(raw);
    } catch (_) {
      uri = Uri.tryParse(raw);
    }
    if (uri == null) return null;
    if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') return null;

    // 老 Discuz 的 space.php 个人空间链接在当前站点已经迁移到 home.php。
    // 保留 query 参数，避免通知中的旧链接直接落到 404。
    if (uri.path.toLowerCase().endsWith('/space.php')) {
      uri = uri.replace(path: '/home.php', queryParameters: {
        'mod': uri.queryParameters['mod'] ?? 'space',
        ...uri.queryParameters,
      });
    }
    // 某些通知只返回 ?mod=space...，Uri.resolve 会落到站点根路径；
    // Discuz 个人空间实际入口是 home.php。
    if ((uri.path.isEmpty || uri.path == '/') && uri.queryParameters.containsKey('mod')) {
      uri = uri.replace(path: '/home.php');
    }
    return uri;
  }

  int _uidFromUri(Uri uri) {
    final value = int.tryParse(uri.queryParameters['uid'] ?? '');
    if (value != null && value > 0) return value;
    final decoded = Uri.decodeFull(uri.toString());
    final match = RegExp(r'(?:[?&]|%3F|%26)uid(?:=|%3D)(\d+)', caseSensitive: false).firstMatch(decoded);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<void> _open(NativeNotice item) async {
    if (!mounted) return;
    if (item.tid > 0) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: forumText(item.title))));
      return;
    }

    final uri = _actionUri(item.href);
    final uid = item.uid > 0 ? item.uid : (uri == null ? 0 : _uidFromUri(uri));
    final params = uri?.queryParameters ?? const <String, String>{};
    final mod = (params['mod'] ?? '').toLowerCase();
    final action = (params['ac'] ?? '').toLowerCase();
    final doAction = (params['do'] ?? '').toLowerCase();

    // 个人空间相关通知优先进入原生个人主页，避免旧的 space.php / 特殊移动链接出现 404。
    if (uid > 0 && (mod == 'space' || mod == 'spacecp' || doAction == 'profile' || doAction == 'thread' || doAction == 'wall' || action == 'poke')) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NativeProfilePage(uid: uid, username: '')));
      return;
    }
    if (uid > 0) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NativeProfilePage(uid: uid, username: '')));
      return;
    }

    if (uri != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewPage(url: uri.toString(), title: forumText(item.title))));
      return;
    }
    _details(item);
  }

  void _details(NativeNotice item) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(forumText(item.title), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(forumText(item.body.isNotEmpty ? item.body : item.subtitle), style: const TextStyle(fontSize: 15, height: 1.5)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: const Text('关闭'))),
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon(NativeNotice item) {
    final text = forumText('${item.title} ${item.body}');
    if (text.contains('回复') || text.contains('评论')) return Icons.chat_bubble_rounded;
    if (text.contains('点赞') || text.contains('赞了')) return Icons.thumb_up_alt_rounded;
    if (text.contains('关注') || text.contains('好友')) return Icons.people_alt_rounded;
    if (text.contains('收藏')) return Icons.bookmark_rounded;
    if (text.contains('签到') || text.contains('任务') || text.contains('积分')) return Icons.task_alt_rounded;
    if (text.contains('购买') || text.contains('订单') || text.contains('充值')) return Icons.receipt_long_rounded;
    return Icons.notifications_rounded;
  }

  String _action(NativeNotice item) {
    final text = forumText('${item.title} ${item.body}');
    if (item.tid > 0) return text.contains('回复') || text.contains('评论') ? '查看并回复' : '打开帖子';
    if (item.uid > 0) return text.contains('关注') ? '查看并互动' : '查看坛友';
    return item.href.isNotEmpty ? '继续处理提醒' : '查看详情';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(forumText(widget.title)), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded), tooltip: '刷新')]),
      body: FutureBuilder<List<NativeNotice>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _error(snapshot.error.toString().replaceFirst('Exception: ', ''));
          final items = snapshot.data ?? const <NativeNotice>[];
          if (items.isEmpty) return RefreshIndicator(onRefresh: _refresh, child: ListView(children: const [SizedBox(height: 300), Center(child: Text('暂无提醒'))]));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(item),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(radius: 23, child: Icon(_icon(item))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(forumText(item.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Text(forumText(item.subtitle), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
                            const SizedBox(height: 8),
                            Text(_action(item), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                          ])),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
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

  Widget _error(String message) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_rounded, size: 48), const SizedBox(height: 12), Text(forumText(message), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('重试'))])));
}
