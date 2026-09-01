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
  final String avatar;
  const _Pm(this.uid, this.name, this.preview, this.time, this.avatar);
}

class _NativeMessageListPageState extends State<NativeMessageListPage> {
  List<_Pm> items = const [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); load(); }
  String clean(String value) => forumText(value.replaceAll(RegExp(r'\s+'), ' ').trim());

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      await AuthService.instance.init();
      if (!AuthService.instance.isLoggedIn) throw Exception('请先登录论坛');
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie ?? '';
      final uri = Uri.parse('${SiteConfig.base}home.php').replace(queryParameters: {
        'mod': 'space', 'do': 'pm', 'mobile': '2', '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
      });
      final response = await client.get(uri, headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store', 'Pragma': 'no-cache',
        if (cookie.isNotEmpty) 'Cookie': cookie,
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }

      final result = <_Pm>[];
      final seen = <int>{};

      for (final link in doc.querySelectorAll('a[href]')) {
        final href = (link.attributes['href'] ?? '').trim();
        if (!isConversation(href)) continue;
        final uid = getUid(href);
        if (uid <= 0 || seen.contains(uid)) continue;

        dynamic container = link;
        for (var depth = 0; depth < 7; depth++) {
          final parent = container.parent;
          if (parent == null) break;
          final parentText = text(parent);
          if (parentText.length <= 700) container = parent; else break;
        }

        var name = clean(link.text);
        if (name.isEmpty || isGeneric(name)) {
          for (final userLink in container.querySelectorAll('a[href*="uid="],a[href*="username="]')) {
            final candidate = clean(userLink.text);
            if (candidate.isNotEmpty && !isGeneric(candidate)) { name = candidate; break; }
          }
        }
        if (name.isEmpty || isGeneric(name)) continue;

        var preview = text(container);
        preview = removeFirst(preview, name);
        final timeNode = container.querySelector('time,.xg1,.xg2,[class*="time"],[class*="date"]');
        final time = text(timeNode);
        if (time.isNotEmpty) preview = removeFirst(preview, time);
        preview = preview.replaceFirst(RegExp(r'^(私人消息|站内私信|私信|消息)\s*'), '').trim();
        if (preview.isEmpty || isGeneric(preview)) continue;

        final image = container.querySelector('img[src],img[data-src],img[data-original]');
        final avatar = (image?.attributes['src'] ?? image?.attributes['data-src'] ?? image?.attributes['data-original'] ?? '').trim();
        result.add(_Pm(uid, name, preview, time, avatar));
        seen.add(uid);
      }

      if (mounted) setState(() { items = result; loading = false; error = null; });
    } catch (e) {
      if (mounted) setState(() { error = clean(e.toString().replaceFirst('Exception: ', '')); loading = false; });
    }
  }

  static bool isConversation(String href) {
    final value = href.toLowerCase();
    final pmPage = value.contains('do=pm') || value.contains('ac=pm');
    final conversation = value.contains('touid=') || value.contains('pmid=') || value.contains('subop=view');
    return pmPage && conversation;
  }

  static int getUid(String href) {
    for (final key in const ['touid', 'uid']) {
      final match = RegExp(r'[?&]' + key + r'=(\d+)', caseSensitive: false).firstMatch(href);
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  static bool isGeneric(String value) => RegExp(r'^(站内私信|私人消息|私信|消息|查看全部私人消息|发送短消息)$').hasMatch(value.trim());
  static String removeFirst(String source, String value) { final index = source.indexOf(value); if (index < 0) return source; return '${source.substring(0, index)}${source.substring(index + value.length)}'.trim(); }

  static String text(dynamic node) {
    if (node == null) return '';
    try {
      final clone = node.clone();
      for (final element in clone.querySelectorAll('i.iconfont,i.comiis-icon,i.comiis_icon,.iconfont,.comiis-icon,svg,[class*="iconfont"],[class*="comiis-icon"]')) { element.remove(); }
      return forumText((clone.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    } catch (_) { return forumText((node.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()); }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(title: const Text('消息'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh)), IconButton(onPressed: () {}, icon: const Icon(Icons.edit))]),
      body: Column(children: [
        Container(height: 48, color: Colors.white, child: Row(children: [
          Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [const Text('私人消息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 8), Container(width: 30, height: 3, color: scheme.primary)]))),
          Expanded(child: Center(child: Text('公共消息', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)))),
        ])),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: load, child: const Text('重试'))]))
            : items.isEmpty ? const Center(child: Text('暂无私人消息'))
            : RefreshIndicator(onRefresh: load, child: ListView.separated(itemCount: items.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 92), itemBuilder: (context, index) {
                final item = items[index];
                final avatar = item.avatar.isNotEmpty ? SiteConfig.resolve(item.avatar) : '${SiteConfig.base}uc_server/avatar.php?uid=${item.uid}&size=small';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                  leading: CircleAvatar(radius: 30, backgroundImage: NetworkImage(avatar), onBackgroundImageError: (_, __) {}),
                  title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  subtitle: Text(item.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(item.time, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeChatPage(uid: item.uid, username: item.name))),
                );
              }))),
      ]),
    );
  }
}
