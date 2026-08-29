import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/member_service.dart';
import 'detail_page.dart';

class MemberFeaturePage extends StatefulWidget {
  final String title;
  final String path;
  final MemberFeatureType type;

  const MemberFeaturePage({
    super.key,
    required this.title,
    required this.path,
    required this.type,
  });

  @override
  State<MemberFeaturePage> createState() => _MemberFeaturePageState();
}

enum MemberFeatureType { threads, replies, favorites, notices, credits }

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
        return MemberService.instance.fetchNotices();
      case MemberFeatureType.credits:
        return MemberService.instance.fetchCredits();
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<Object>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(message: snapshot.error.toString().replaceFirst('Exception: ', ''), onRetry: _refresh);
          }
          final value = snapshot.data;
          if (value is List<ThreadItem>) return _ThreadList(items: value);
          if (value is List<MemberNotice>) return _NoticeList(items: value);
          if (value is CreditSummary) return _CreditView(summary: value);
          return const Center(child: Text('暂无内容'));
        },
      ),
    );
  }
}

class _ThreadList extends StatelessWidget {
  final List<ThreadItem> items;
  const _ThreadList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('暂无帖子'));
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.boardName.isEmpty ? '主题 #${item.tid}' : item.boardName),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DetailPage(tid: item.tid)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NoticeList extends StatelessWidget {
  final List<MemberNotice> items;
  const _NoticeList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('暂无通知'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.notifications_none)),
        title: Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(items[i].subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _CreditView extends StatelessWidget {
  final CreditSummary summary;
  const _CreditView({required this.summary});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('星币余额', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(summary.balance, style: Theme.of(context).textTheme.displaySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('积分 / 交易信息', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (summary.records.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('暂无交易记录')))
        else
          ...summary.records.map((e) => Card(child: ListTile(title: Text(e)))),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
