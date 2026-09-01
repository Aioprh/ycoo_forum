import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/member_service.dart';
import '../services/member_service_v2.dart';
import '../utils/forum_text.dart';
import '../widgets/native_icon_style.dart';
import 'detail_page.dart';
import 'native_message_list_page.dart';
import 'native_profile_page.dart';

class MemberFeaturePage extends StatefulWidget {
  final String title;
  final String path;
  final MemberFeatureType type;
  const MemberFeaturePage({super.key, required this.title, required this.path, required this.type});

  @override
  State<MemberFeaturePage> createState() => _MemberFeaturePageState();
}

enum MemberFeatureType { threads, replies, favorites, notices, messages, friends, credits }

class _MemberFeaturePageState extends State<MemberFeaturePage> {
  late Future<Object> _future;
  String get _viewForNotice => switch (widget.title) {
        '坛友互动' => 'interactive', '系统提醒' => 'system', '应用提醒' => 'app', '我的帖子' => 'mypost', _ => 'all',
      };
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<Object> _load() {
    switch (widget.type) {
      case MemberFeatureType.threads:
      case MemberFeatureType.replies:
      case MemberFeatureType.favorites: return MemberService.instance.fetchThreads(widget.path);
      case MemberFeatureType.notices: return MemberServiceV2.instance.fetchNotices(view: _viewForNotice);
      case MemberFeatureType.messages: return MemberServiceV2.instance.fetchMessages();
      case MemberFeatureType.friends: return MemberServiceV2.instance.fetchFriends();
      case MemberFeatureType.credits: return MemberServiceV2.instance.fetchCredits();
    }
  }
  Future<void> _refresh() async { setState(() => _future = _load()); await _future; }
  @override
  Widget build(BuildContext context) {
    if (widget.type == MemberFeatureType.messages) return const NativeMessageListPage();
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(forumText(widget.title)), actions: [IconButton(onPressed: _refresh, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<Object>(future: _future, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _ErrorState(message: forumText(snapshot.error.toString().replaceFirst('Exception: ', '')), onRetry: _refresh);
        final value = snapshot.data;
        if (value is List<ThreadItem>) return _ThreadList(items: value);
        if (value is List<NativeFriend>) return _FriendList(items: value);
        if (value is List<NativeNotice>) return _NoticeList(items: value);
        if (value is NativeCreditSummary) return _CreditView(summary: value);
        return const _EmptyState(title: '暂无内容', subtitle: '这里暂时没有可显示的数据');
      }),
    );
  }
}

class _NoticeList extends StatelessWidget {
  final List<NativeNotice> items;
  const _NoticeList({required this.items});
  IconData _iconFor(String title, String subtitle) {
    final text = forumText('$title $subtitle');
    if (text.contains('购买') || text.contains('订单') || text.contains('星币')) return Icons.receipt_long_rounded;
    if (text.contains('任务') || text.contains('积分')) return Icons.task_alt_rounded;
    if (text.contains('评论') || text.contains('回复')) return Icons.chat_bubble_outline_rounded;
    if (text.contains('关注') || text.contains('好友')) return Icons.people_alt_rounded;
    if (text.contains('主题')) return Icons.forum_rounded;
    if (text.contains('注册') || text.contains('欢迎')) return Icons.verified_user_rounded;
    return Icons.notifications_none_rounded;
  }

  void _open(BuildContext context, NativeNotice item) {
    if (item.tid > 0) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: forumText(item.title))));
      return;
    }
    if (item.uid > 0) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeProfilePage(uid: item.uid, username: '')));
      return;
    }
    _showDetail(context, item);
  }

  void _showDetail(BuildContext context, NativeNotice item) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        final display = forumText(item.body.isNotEmpty ? item.body : item.subtitle);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.notifications_active_outlined, size: 20), const SizedBox(width: 8), Expanded(child: Text('通知详情', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.onSurface))), IconButton(onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close))]),
                const SizedBox(height: 12),
                Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(14)), child: Text(display, style: TextStyle(fontSize: 15, height: 1.5, color: scheme.onSurface))),
                const SizedBox(height: 8),
                if (item.uid > 0) FilledButton.icon(onPressed: () { Navigator.of(sheetContext).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeProfilePage(uid: item.uid, username: ''))); }, icon: const Icon(Icons.person_outline), label: const Text('查看作者主页')),
              ]),
            ),
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(title: '暂时没有提醒内容', subtitle: '新的回复、评论、系统消息等提醒会显示在这里');
    return ListView.separated(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 9), itemBuilder: (context, i) {
      final item = items[i]; final title = forumText(item.title); final subtitle = forumText(item.subtitle);
      final actionable = item.tid > 0 || item.uid > 0 || item.body.isNotEmpty || item.subtitle.isNotEmpty;
      return Card(clipBehavior: Clip.antiAlias, child: ListTile(leading: NativeIconStyle.badge(context, _iconFor(title, subtitle)), title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: subtitle != title ? Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis) : null, trailing: actionable ? const Icon(Icons.chevron_right_rounded) : null, onTap: actionable ? () => _open(context, item) : null));
    });
  }
}

class _ThreadList extends StatelessWidget {
  final List<ThreadItem> items; const _ThreadList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(title: '暂无帖子', subtitle: '这里还没有相关主题');
    return ListView.separated(padding: const EdgeInsets.all(14), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) {
      final item = items[i];
      return Card(clipBehavior: Clip.antiAlias, child: ListTile(title: Text(forumText(item.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(item.boardName.isEmpty ? '主题 #${item.tid}' : forumText(item.boardName)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: forumText(item.title))))));
    });
  }
}

class _FriendList extends StatelessWidget {
  final List<NativeFriend> items; const _FriendList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(title: '暂无好友或关注', subtitle: '你的好友、关注与粉丝会显示在这里');
    return ListView.separated(padding: const EdgeInsets.all(14), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) => Card(child: ListTile(leading: NativeIconStyle.badge(context, Icons.person_rounded), title: Text(forumText(items[i].name)), subtitle: Text(forumText(items[i].subtitle)))));
  }
}

class _CreditView extends StatelessWidget {
  final NativeCreditSummary summary; const _CreditView({required this.summary});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('余额', style: TextStyle(fontSize: 13)), const SizedBox(height: 5), Text(forumText(summary.balance), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))]))), const SizedBox(height: 10), ...summary.records.map((e) => Card(child: ListTile(title: Text(forumText(e))))) ]);
}

class _EmptyState extends StatelessWidget {
  final String title; final String subtitle; const _EmptyState({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inbox_outlined, size: 52, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 12), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])));
}

class _ErrorState extends StatelessWidget {
  final String message; final Future<void> Function() onRetry; const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_rounded, size: 46), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('重试'))])));
}
