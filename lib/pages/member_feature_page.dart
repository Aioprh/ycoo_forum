import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/member_service.dart';
import '../services/member_service_v2.dart';
import 'detail_page.dart';

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
        return MemberServiceV2.instance.fetchNotices();
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
          TextField(
            controller: toCtrl,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '收件人用户名', prefixIcon: Icon(Icons.person_outline), isDense: true),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: msgCtrl,
            maxLines: 4,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(labelText: '私信内容', prefixIcon: Icon(Icons.chat_bubble_outline), alignLabelWithHint: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.send_rounded, size: 18), label: const Text('发送')),
        ],
      ),
    ) ?? false;
    if (!ok || !mounted) {
      toCtrl.dispose();
      msgCtrl.dispose();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final err = await MemberServiceV2.instance.sendMessage(to: toCtrl.text, message: msgCtrl.text);
    toCtrl.dispose();
    msgCtrl.dispose();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(err ?? '私信已发送'), behavior: SnackBarBehavior.floating));
    if (err == null) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (widget.type == MemberFeatureType.messages)
              IconButton(icon: const Icon(Icons.edit_outlined), tooltip: '新建私信', onPressed: _openSendPm),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded), tooltip: '刷新'),
          ],
        ),
        body: FutureBuilder<Object>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const _LoadingView();
            if (snapshot.hasError) return _ErrorView(message: snapshot.error.toString().replaceFirst('Exception: ', ''), onRetry: _refresh);
            final value = snapshot.data;
            if (value is List<ThreadItem>) return _ThreadList(items: value);
            if (value is List<NativeNotice>) return _NoticeList(items: value);
            if (value is List<NativeMessage>) return _MessageList(items: value, onCompose: _openSendPm);
            if (value is List<NativeFriend>) return _FriendList(items: value);
            if (value is NativeCreditSummary) return _CreditView(summary: value);
            return const _EmptyView(title: '暂无内容', subtitle: '这里暂时没有可显示的数据');
          },
        ),
      );
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class _EmptyView extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyView({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined, size: 52, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
}

class _ThreadList extends StatelessWidget {
  final List<ThreadItem> items;
  const _ThreadList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyView(title: '暂无帖子', subtitle: '这里还没有相关主题');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(item.boardName.isEmpty ? '主题 #${item.tid}' : item.boardName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid, title: item.title))),
          ),
        );
      },
    );
  }
}

class _NoticeList extends StatelessWidget {
  final List<NativeNotice> items;
  const _NoticeList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyView(title: '暂无通知', subtitle: '回复、提醒和互动消息会显示在这里');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _NoticeCard(item: items[i]),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final NativeNotice item;
  const _NoticeCard({required this.item});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(17),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle), child: Icon(Icons.notifications_none_rounded, color: scheme.onPrimaryContainer)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.25)),
            const SizedBox(height: 6),
            Text(item.subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant)),
          ])),
        ]),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<NativeMessage> items;
  final VoidCallback onCompose;
  const _MessageList({required this.items, required this.onCompose});

  String _sender(String text) {
    final value = text.trim();
    final patterns = [
      RegExp(r'^(?:来自|发自|私信|消息来自)\s*[:：]?\s*([^\s:：]+)', caseSensitive: false),
      RegExp(r'^([^\s]{1,30})\s*(?:发来|给你|：)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(value);
      if (m != null && (m.group(1) ?? '').trim().isNotEmpty) return m.group(1)!.trim();
    }
    return '站内私信';
  }

  Future<void> _openMessage(BuildContext context, NativeMessage item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 24, backgroundColor: scheme.primaryContainer, child: Icon(Icons.person_outline_rounded, color: scheme.onPrimaryContainer)),
                const SizedBox(width: 12),
                Expanded(child: Text(_sender(item.title), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                child: Text(item.subtitle, style: const TextStyle(fontSize: 14, height: 1.5)),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { Navigator.pop(sheetContext); onCompose(); }, icon: const Icon(Icons.reply_rounded), label: const Text('发送新私信'))),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column(children: [
        const Expanded(child: _EmptyView(title: '暂无私信', subtitle: '和其他用户的站内私信会显示在这里')),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 18), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onCompose, icon: const Icon(Icons.edit_rounded), label: const Text('新建私信')))),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _MessageHeader(count: items.length, onCompose: onCompose);
        }
        final item = items[index - 1];
        final sender = _sender(item.title);
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openMessage(context, item),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 24, backgroundColor: scheme.secondaryContainer, child: Text(sender.isEmpty ? '私' : sender.characters.first, style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSecondaryContainer))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ]),
                  const SizedBox(height: 5),
                  Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant)),
                ])),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _MessageHeader extends StatelessWidget {
  final int count;
  final VoidCallback onCompose;
  const _MessageHeader({required this.count, required this.onCompose});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('站内私信', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('$count 条消息 · 点击卡片查看内容', style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer.withValues(alpha: .75))),
        ])),
        IconButton.filled(onPressed: onCompose, tooltip: '新建私信', icon: const Icon(Icons.edit_rounded)),
      ]),
    );
  }
}

class _FriendList extends StatelessWidget {
  final List<NativeFriend> items;
  const _FriendList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyView(title: '暂无好友或关注', subtitle: '你的好友、关注与粉丝会显示在这里');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _InfoCard(icon: Icons.person_outline_rounded, title: items[i].name, subtitle: items[i].subtitle),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoCard({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            CircleAvatar(radius: 22, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            ])),
          ]),
        ),
      );
}

class _CreditView extends StatelessWidget {
  final NativeCreditSummary summary;
  const _CreditView({required this.summary});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('星币余额', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(summary.balance, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          const Text('积分 / 交易信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (summary.records.isEmpty)
            const _InfoCard(icon: Icons.receipt_long_outlined, title: '暂无交易记录', subtitle: '当前页面没有可显示的交易明细')
          else
            ...summary.records.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _InfoCard(icon: Icons.receipt_long_outlined, title: e, subtitle: '论坛积分 / 星币信息'))),
        ],
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('重试')),
          ]),
        ),
      );
}
