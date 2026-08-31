import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/member_service.dart';
import '../services/member_service_v2.dart';
import '../services/site_config.dart';
import '../utils/forum_text.dart';
import '../widgets/native_icon_style.dart';
import 'detail_page.dart';
import 'native_chat_page.dart';
import 'webview_page.dart';

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
        '坛友互动' => 'interactive',
        '系统提醒' => 'system',
        '应用提醒' => 'app',
        '我的帖子' => 'mypost',
        _ => 'all',
      };

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Object> _load() {
    switch (widget.type) {
      case MemberFeatureType.threads:
      case MemberFeatureType.replies:
      case MemberFeatureType.favorites:
        return MemberService.instance.fetchThreads(widget.path);
      case MemberFeatureType.notices:
        return MemberServiceV2.instance.fetchNotices(view: _viewForNotice);
      case MemberFeatureType.messages:
        return MemberServiceV2.instance.fetchMessages();
      case MemberFeatureType.friends:
        return MemberServiceV2.instance.fetchFriends();
      case MemberFeatureType.credits:
        return MemberServiceV2.instance.fetchCredits();
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openSendPm() async {
    final toCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('发送私信'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: toCtrl, autofocus: true, decoration: const InputDecoration(labelText: '收件人用户名', prefixIcon: Icon(Icons.person_outline_rounded))),
              const SizedBox(height: 12),
              TextField(controller: msgCtrl, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: '私信内容', prefixIcon: Icon(Icons.chat_bubble_outline_rounded), alignLabelWithHint: true)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
              FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.send_rounded), label: const Text('发送')),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) {
      toCtrl.dispose();
      msgCtrl.dispose();
      return;
    }
    final error = await MemberServiceV2.instance.sendMessage(to: toCtrl.text, message: msgCtrl.text);
    toCtrl.dispose();
    msgCtrl.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumText(error ?? '私信已发送')), behavior: SnackBarBehavior.floating));
    if (error == null) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(forumText(widget.title)),
        actions: [
          if (widget.type == MemberFeatureType.messages) IconButton(onPressed: _openSendPm, tooltip: '新建私信', icon: const Icon(Icons.edit_outlined)),
          IconButton(onPressed: _refresh, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<Object>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _ErrorState(message: forumText(snapshot.error.toString().replaceFirst('Exception: ', '')), onRetry: _refresh);
          final value = snapshot.data;
          if (value is List<ThreadItem>) return _ThreadList(items: value);
          if (value is List<NativeMessage>) return _MessageList(items: value, onCompose: _openSendPm);
          if (value is List<NativeFriend>) return _FriendList(items: value);
          if (value is List<NativeNotice>) return _NoticeList(items: value);
          if (value is NativeCreditSummary) return _CreditView(summary: value);
          return const _EmptyState(title: '暂无内容', subtitle: '这里暂时没有可显示的数据');
        },
      ),
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

  /// 从各类通知链接里尽量提取主题 id, 兼容多种写法。
  static int? _extractTid(String href) {
    for (final m in RegExp(r'(?:thread-|tid=)(\d+)', caseSensitive: false).allMatches(href)) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v > 0) return v;
    }
    final vm = RegExp(r'mod=viewthread\D+(\d+)', caseSensitive: false).firstMatch(href);
    final vv = int.tryParse(vm?.group(1) ?? '');
    if (vv != null && vv > 0) return vv;
    return null;
  }

  /// 点击通知跳到来源: 能识别到主题就打开原生详情页(渲染帖子正文), 否则用内置 WebView 打开来源页。
  void _open(BuildContext context, NativeNotice item) {
    final href = item.href;
    if (href.isEmpty) return;
    final tid = _extractTid(href);
    if (tid != null && tid > 0) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(tid: tid, title: forumText(item.title))));
      return;
    }
    final url = SiteConfig.resolve(href);
    if (url.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebViewPage(url: url, title: forumText(item.title))));
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(title: '暂时没有提醒内容', subtitle: '新的回复、评论、系统消息等提醒会显示在这里');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, i) {
        final item = items[i];
        final title = forumText(item.title);
        final subtitle = forumText(item.subtitle);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: NativeIconStyle.badge(context, _iconFor(title, subtitle)),
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: subtitle != title ? Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
            trailing: item.href.isEmpty ? null : const Icon(Icons.chevron_right_rounded),
            onTap: item.href.isEmpty ? null : () => _open(context, item),
          ),
        );
      },
    );
  }
}

class _ThreadList extends StatelessWidget {
  final List<ThreadItem> items;
  const _ThreadList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(title: '暂无帖子', subtitle: '这里还没有相关主题');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = items[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            title: Text(forumText(item.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(item.boardName.isEmpty ? '主题 #${item.tid}' : forumText(item.boardName)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: forumText(item.title)))),
          ),
        );
      },
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<NativeMessage> items;
  final VoidCallback onCompose;
  const _MessageList({required this.items, required this.onCompose});

  String _sender(NativeMessage item) {
    final rawSender = forumText(item.sender);
    if (rawSender.trim().isNotEmpty && rawSender != '站内私信') return rawSender.trim();
    final title = forumText(item.title).trim();
    final m = RegExp(r'^(?:来自|发自|消息来自)\s*[:：]?\s*(.+)$').firstMatch(title);
    return m?.group(1)?.trim().isNotEmpty == true ? forumText(m!.group(1)!.trim()) : (title.isEmpty ? '站内私信' : title);
  }

  Future<void> _open(BuildContext context, NativeMessage item) async {
    final sender = _sender(item);
    // 解析到了对端 uid: 直接进入真正的聊天对话页, 可查看往来消息并回复。
    if (item.uid > 0) {
      final username = (sender.isEmpty || sender == '站内私信') ? '用户' : sender;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeChatPage(uid: item.uid, username: username)));
      return;
    }
    final body = forumText(item.subtitle);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 23, child: Text(sender.isEmpty ? '信' : sender.characters.first)),
              const SizedBox(width: 12),
              Expanded(child: Text(sender, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 16),
            Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Theme.of(sheet).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)), child: Text(body, style: const TextStyle(height: 1.5))),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { Navigator.pop(sheet); onCompose(); }, icon: const Icon(Icons.reply_rounded), label: const Text('发送新私信'))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column(children: [
        const Expanded(child: _EmptyState(title: '暂无私信', subtitle: '和其他用户的站内私信会显示在这里')),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 18), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onCompose, icon: const Icon(Icons.edit_rounded), label: const Text('新建私信')))),
      ]);
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('站内私信', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), SizedBox(height: 3), Text('点击卡片查看消息内容', style: TextStyle(fontSize: 11))])),
              IconButton.filled(onPressed: onCompose, icon: const Icon(Icons.edit_rounded)),
            ]),
          );
        }
        final item = items[index - 1];
        final sender = _sender(item);
        final subtitle = forumText(item.subtitle);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: scheme.secondaryContainer, child: Text(sender.isEmpty ? '信' : sender.characters.first)),
            title: Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _open(context, item),
          ),
        );
      },
    );
  }
}

class _FriendList extends StatelessWidget {
  final List<NativeFriend> items;
  const _FriendList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(title: '暂无好友或关注', subtitle: '你的好友、关注与粉丝会显示在这里');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => Card(child: ListTile(leading: NativeIconStyle.badge(context, Icons.person_rounded), title: Text(forumText(items[i].name)), subtitle: Text(forumText(items[i].subtitle)))),
    );
  }
}

class _CreditView extends StatelessWidget {
  final NativeCreditSummary summary;
  const _CreditView({required this.summary});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('余额', style: TextStyle(fontSize: 13)), const SizedBox(height: 5), Text(forumText(summary.balance), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))]))),
        const SizedBox(height: 10),
        ...summary.records.map((e) => Card(child: ListTile(title: Text(forumText(e))))),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inbox_outlined, size: 52, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 12), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])));
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_rounded, size: 46), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('重试'))])));
}
