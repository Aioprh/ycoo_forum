import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../services/auth_service.dart';
import '../services/net_client.dart';
import '../services/site_config.dart';
import '../utils/forum_text.dart';
import 'native_chat_page.dart';

class NativeMessageListPage extends StatefulWidget {
  const NativeMessageListPage({super.key});

  @override
  State<NativeMessageListPage> createState() => _NativeMessageListPageState();
}

class _Pm {
  final int uid;
  final String name;
  final String preview;
  final String time;

  const _Pm(this.uid, this.name, this.preview, this.time);
}

class _NativeMessageListPageState extends State<NativeMessageListPage> {
  List<_Pm> items = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  String clean(String value) {
    return forumText(value.replaceAll(RegExp(r'\s+'), ' ').trim());
  }

  Future<void> load() async {
    if (mounted) {
      setState(() => loading = true);
    }

    try {
      await AuthService.instance.init();
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie ?? '';
      final uri = Uri.parse('${SiteConfig.base}home.php').replace(
        queryParameters: {
          'mod': 'space',
          'do': 'pm',
          'mobile': '2',
          '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      final response = await client.get(
        uri,
        headers: {
          'User-Agent': NetClient.ua,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('请求失败 HTTP ${response.statusCode}');
      }

      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      for (final node in doc.querySelectorAll('script,style,noscript,template')) {
        node.remove();
      }

      final result = <_Pm>[];
      final seen = <int>{};

      // Discuz 私信列表中，真正的会话链接必须包含 do=pm/ac=pm，
      // 并带有 touid、pmid 或 subop=view。排除“站内私信”等入口链接。
      for (final link in doc.querySelectorAll('a[href]')) {
        final href = (link.attributes['href'] ?? '').trim();
        final uid = getUid(href);
        if (uid <= 0 || uid == AuthService.instance.uid || !isConversation(href)) {
          continue;
        }
        if (seen.contains(uid)) continue;

        final name = clean(link.text);
        if (name.isEmpty || isGeneric(name)) continue;

        dynamic node = link;
        for (var depth = 0; depth < 5; depth++) {
          final parent = node.parent;
          if (parent == null) break;
          final parentText = text(parent);
          if (parentText.length >= name.length && parentText.length < 500) {
            node = parent;
          } else {
            break;
          }
        }

        var preview = text(node);
        preview = removeFirst(preview, name);
        final timeNode = node.querySelector(
          'time,.xg1,.xg2,[class*="time"],[class*="date"]',
        );
        final time = text(timeNode);
        if (time.isNotEmpty) {
          preview = removeFirst(preview, time);
        }
        preview = preview
            .replaceFirst(RegExp(r'^(私人消息|站内私信|私信|消息)\s*'), '')
            .trim();

        if (preview.isEmpty || isGeneric(preview)) continue;
        seen.add(uid);
        result.add(_Pm(uid, name, preview, time));
      }

      if (mounted) {
        setState(() {
          items = result;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = clean(e.toString().replaceFirst('Exception: ', ''));
          loading = false;
        });
      }
    }
  }

  static bool isConversation(String href) {
    final value = href.toLowerCase();
    final pmPage = value.contains('do=pm') || value.contains('ac=pm');
    final conversation = value.contains('touid=') ||
        value.contains('pmid=') ||
        value.contains('subop=view');
    return pmPage && conversation;
  }

  static int getUid(String href) {
    for (final key in const ['touid', 'uid']) {
      final match = RegExp('[?&]$key=(\\d+)', caseSensitive: false).firstMatch(href);
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  static bool isGeneric(String value) {
    return RegExp(r'^(站内私信|私人消息|私信|消息|查看全部私人消息|发送短消息)$')
        .hasMatch(value.trim());
  }

  static String removeFirst(String source, String value) {
    final index = source.indexOf(value);
    if (index < 0) return source;
    return '${source.substring(0, index)}${source.substring(index + value.length)}'.trim();
  }

  static String text(dynamic node) {
    if (node == null) return '';
    try {
      final clone = node.clone();
      for (final element in clone.querySelectorAll(
        'i.iconfont,i.comiis-icon,i.comiis_icon,.iconfont,.comiis-icon,svg,[class*="iconfont"],[class*="comiis-icon"]',
      )) {
        element.remove();
      }
      return forumText((clone.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    } catch (_) {
      return forumText((node.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.edit)),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 48,
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('私人消息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Container(width: 30, height: 3, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text('公共消息', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: load, child: const Text('重试')),
                          ],
                        ),
                      )
                    : items.isEmpty
                        ? const Center(child: Text('暂无私人消息'))
                        : RefreshIndicator(
                            onRefresh: load,
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, indent: 92),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                                  leading: CircleAvatar(
                                    radius: 34,
                                    backgroundImage: NetworkImage(
                                      '${SiteConfig.base}uc_server/avatar.php?uid=${item.uid}&size=small',
                                    ),
                                  ),
                                  title: Text(item.name),
                                  subtitle: Text(item.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Text(item.time, style: const TextStyle(fontSize: 11)),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => NativeChatPage(uid: item.uid, username: item.name),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
