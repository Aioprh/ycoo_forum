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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
        body: FutureBuilder<Object>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return _ErrorView(message: snapshot.error.toString().replaceFirst('Exception: ', ''), onRetry: _refresh);
            final value = snapshot.data;
            if (value is List<ThreadItem>) return _ThreadList(items: value);
            if (value is List<NativeNotice>) return _NoticeList(items: value);
            if (value is List<NativeMessage>) return _MessageList(items: value);
            if (value is List<NativeFriend>) return _FriendList(items: value);
            if (value is NativeCreditSummary) return _CreditView(summary: value);
            return const Center(child: Text('暂无内容'));
          },
        ),
      );
}

class _ThreadList extends StatelessWidget {
  final List<ThreadItem> items;
  const _ThreadList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('暂无帖子'));
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: Colors.white,
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
    if (items.isEmpty) return const Center(child: Text('暂无通知'));
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _InfoCard(icon: Icons.notifications_none_rounded, title: items[i].title, subtitle: items[i].subtitle),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<NativeMessage> items;
  const _MessageList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('暂无消息'));
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _InfoCard(icon: Icons.mail_outline_rounded, title: items[i].title, subtitle: items[i].subtitle),
    );
  }
}

class _FriendList extends StatelessWidget {
  final List<NativeFriend> items;
  const _FriendList({required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('暂无好友或关注'));
    return ListView.separated(
      padding: const EdgeInsets.all(14),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            CircleAvatar(radius: 22, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
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
            ...summary.records.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _InfoCard(icon: Icons.receipt_long_outlined, title: e, subtitle: '论坛积分 / 星币信息')),
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
