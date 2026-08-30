import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../services/auth_service.dart';
import '../services/member_service_v2.dart';
import '../services/net_client.dart';

class NativeChatPage extends StatefulWidget {
  final int uid;
  final String username;

  const NativeChatPage({super.key, required this.uid, required this.username});

  @override
  State<NativeChatPage> createState() => _NativeChatPageState();
}

class _NativeChatPageState extends State<NativeChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<NativeMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.init();
      if (!AuthService.instance.isLoggedIn) throw Exception('请先登录论坛');
      final client = await NetClient.instance.client;
      final uri = Uri.parse('https://www.ycoo.net/home.php?mod=space&do=pm&subop=view&touid=${widget.uid}&mobile=2').replace(queryParameters: {
        'mod': 'space', 'do': 'pm', 'subop': 'view', 'touid': '${widget.uid}', 'mobile': '2',
        '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await client.get(uri, headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!,
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      final list = <NativeMessage>[];
      for (final node in doc.querySelectorAll('dl.pml, dl[id^="pmlist_"], li.pm_list, li.pml')) {
        final author = node.querySelector('a[href*="uid="],a[href*="mod=space"]');
        final sender = (author?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        final time = (node.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]')?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        var body = (node.querySelector('.ptm')?.text ?? node.text).replaceAll(RegExp(r'\s+'), ' ').trim();
        if (sender.isNotEmpty) body = body.replaceFirst(sender, '').trim();
        if (time.isNotEmpty) body = body.replaceFirst(time, '').trim();
        body = body.replaceAll(RegExp(r'^[:：\-·\s]+|[:：\-·\s]+\$'), '').trim();
        if (body.isEmpty || body == '站内私信' || body == '站内消息') continue;
        list.add(NativeMessage(title: sender.isEmpty ? widget.username : sender, sender: sender, subtitle: body, time: time));
      }
      if (mounted) setState(() { _messages = list.reversed.toList(); _loading = false; });
      _jumpBottom();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await MemberServiceV2.instance.sendMessage(to: widget.username, message: text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _controller.clear();
    await _load();
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(widget.username),
        actions: [IconButton(onPressed: _load, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('重试'))]))
              : Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _messages.isEmpty
                          ? ListView(children: const [SizedBox(height: 180), Center(child: Text('暂无聊天记录')),])
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                              itemCount: _messages.length,
                              itemBuilder: (_, i) {
                                final m = _messages[i];
                                final mine = m.sender.isEmpty || m.sender != widget.username;
                                return Align(
                                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 310),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m.subtitle, style: const TextStyle(fontSize: 15, height: 1.45)), if (m.time.isNotEmpty) ...[const SizedBox(height: 4), Text(m.time, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))]],),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(children: [
                        Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: '发送给 ${widget.username}', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
                        const SizedBox(width: 8),
                        IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
