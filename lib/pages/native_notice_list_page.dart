import 'package:flutter/material.dart';

import '../services/member_service_v2.dart';
import '../utils/forum_text.dart';
import '../widgets/native_icon_style.dart';
import 'detail_page.dart';
import 'native_profile_page.dart';

/// 原生通知列表。
///
/// 通知不是“纯文本列表”：
/// - 有帖子目标时直接进入帖子详情，继续点赞、回复、评论等操作；
/// - 有用户目标时进入用户主页，继续关注、私信等操作；
/// - 没有可解析目标时仍提供完整通知详情，而不是做成不可点击的静态卡片。
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
    _future = MemberServiceV2.instance.fetchNotices(view: widget.view);
  }

  Future<void> _refresh() async {
    setState(() => _future = MemberServiceV2.instance.fetchNotices(view: widget.view));
    await _future;
  }

  Future<void> _openNotice(NativeNotice item) async {
    if (!mounted) return;
    if (item.tid > 0) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailPage(tid: item.tid, title: forumText(item.title)),
      ));
      return;
    }
    if (item.uid > 0) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NativeProfilePage(uid: item.uid, username: ''),
      ));
      return;
    }
    _showDetail(item);
  }

  void _showDetail(NativeNotice item) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '通知详情',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onSurface),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(forumText(item.title), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    forumText(item.body.isNotEmpty ? item.body : item.subtitle),
                    style: TextStyle(fontSize: 15, height: 1.55, color: scheme.onSurface),
                  ),
                ),
                if (item.uid > 0) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => NativeProfilePage(uid: item.uid, username: ''),
                        ));
                      },
                      icon: const Icon(Icons.person_outline),
                      label: const Text('查看坛友并继续互动'),
                    ),
                  ),
                ],
                if (item.tid > 0) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DetailPage(tid: item.tid, title: forumText(item.title)),
                        ));
                      },
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('打开帖子并继续互动'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(NativeNotice item) {
    final text = forumText('${item.title} ${item.subtitle}');
    if (text.contains('关注') || text.contains('好友')) return Icons.people_alt_rounded;
    if (text.contains('点赞') || text.contains('赞了')) return Icons.thumb_up_alt_rounded;
    if (text.contains('评论') || text.contains('回复')) return Icons.chat_bubble_rounded;
    if (text.contains('收藏')) return Icons.bookmark_rounded;
    if (text.contains('任务') || text.contains('签到') || text.contains('积分')) return Icons.task_alt_rounded;
    if (text.contains('订单') || text.contains('购买') || text.contains('充值')) return Icons.receipt_long_rounded;
    if (text.contains('主题')) return Icons.forum_rounded;
    return Icons.notifications_none_rounded;
  }

  String _actionLabel(NativeNotice item) {
    final text = forumText('${item.title} ${item.subtitle}');
    if (item.tid > 0) {
      if (text.contains('回复') || text.contains('评论')) return '查看并回复';
      if (text.contains('点赞') || text.contains('赞了')) return '查看帖子';
      return '打开帖子';
    }
    if (item.uid > 0) return text.contains('关注') ? '查看并互动' : '查看坛友';
    return '查看详情';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(forumText(widget.title)),
        actions: [IconButton(onPressed: _refresh, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<NativeNotice>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = forumText(snapshot.error.toString().replaceFirst('Exception: ', ''));
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('重试')),
                  ],
                ),
              ),
            );
          }
          final items = snapshot.data ?? const <NativeNotice>[];
          if (items.isEmpty) {
            return const Center(child: Text('暂无提醒'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final title = forumText(item.title);
                final subtitle = forumText(item.subtitle);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openNotice(item),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 13, 10, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NativeIconStyle.badge(context, _icon(item)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 5),
                                Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.35)),
                                const SizedBox(height: 9),
                                Row(
                                  children: [
                                    Text(_actionLabel(item), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                                    const SizedBox(width: 3),
                                    Icon(Icons.arrow_forward_rounded, size: 15, color: scheme.primary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, color: scheme.outline),
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
}
