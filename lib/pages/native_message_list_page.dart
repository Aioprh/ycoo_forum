import 'package:flutter/material.dart';

import '../services/member_service_v2.dart';
import 'native_chat_page.dart';

/// 原生私信会话列表：按“联系人 + 最后一条消息”展示，点击进入完整聊天。
class NativeMessageListPage extends StatefulWidget {
  const NativeMessageListPage({super.key});

  @override
  State<NativeMessageListPage> createState() => _NativeMessageListPageState();
}

class _NativeMessageListPageState extends State<NativeMessageListPage> {
  late Future<List<NativeMessage>> _future;

  @override
  void initState() {
    super.initState();
    _future = MemberServiceV2.instance.fetchMessages();
  }

  Future<void> _refresh() async {
    setState(() => _future = MemberServiceV2.instance.fetchMessages());
    await _future;
  }

  String _name(NativeMessage item) {
    final sender = item.sender.trim();
    if (sender.isNotEmpty && sender != '站内私信') return sender;
    final title = item.title.trim();
    return title.isEmpty || title == '站内私信' ? '站内私信' : title;
  }

  String _initial(String name) => name == '站内私信' || name.isEmpty ? '信' : name.characters.first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('消息'),
        actions: [IconButton(onPressed: _refresh, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<NativeMessage>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) {
            return _StateView(icon: Icons.cloud_off_rounded, title: '消息加载失败', subtitle: snapshot.error.toString().replaceFirst('Exception: ', ''), action: _refresh);
          }
          final items = snapshot.data ?? const <NativeMessage>[];
          if (items.isEmpty) return _StateView(icon: Icons.forum_outlined, title: '还没有私信', subtitle: '和其他用户开始聊天后，会话会显示在这里。', action: _refresh);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final item = items[index];
                final name = _name(item);
                final preview = item.subtitle.trim().isEmpty ? '暂无消息内容' : item.subtitle.trim();
                return Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: item.uid > 0
                        ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeChatPage(uid: item.uid, username: name)))
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 29,
                                backgroundColor: scheme.primaryContainer,
                                child: Text(_initial(name), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                              ),
                            ],
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                                    if (item.time.trim().isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(item.time.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.3, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(Icons.chevron_right_rounded, size: 22, color: scheme.outlineVariant),
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

class _StateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() action;
  const _StateView({required this.icon, required this.title, required this.subtitle, required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: action,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 150),
          Icon(icon, size: 58, color: scheme.outline),
          const SizedBox(height: 16),
          Center(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          const SizedBox(height: 7),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 34), child: Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.5))),
          const SizedBox(height: 18),
          Center(child: FilledButton.icon(onPressed: action, icon: const Icon(Icons.refresh_rounded), label: const Text('刷新'))),
        ],
      ),
    );
  }
}
