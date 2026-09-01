import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../services/auth_service.dart';
import '../services/member_service_v2.dart';
import '../services/net_client.dart';
import '../services/site_config.dart';
import '../utils/forum_text.dart';

class NativeChatPage extends StatefulWidget {
  final int uid;
  final String username;
  const NativeChatPage({super.key, required this.uid, required this.username});
  @override
  State<NativeChatPage> createState() => _NativeChatPageState();
}

class _ChatMessage {
  final int uid;
  final String sender;
  final String body;
  final String time;
  const _ChatMessage({required this.uid, required this.sender, required this.body, required this.time});
}

class _NativeChatPageState extends State<NativeChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<_ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _controller.dispose(); _scroll.dispose(); super.dispose(); }

  String _clean(String value) => forumText(value.replaceAll(RegExp(r'\s+'), ' ').trim());

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.init();
      if (!AuthService.instance.isLoggedIn) throw Exception('请先登录论坛');
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie ?? '';
      final uri = Uri.parse('${SiteConfig.base}home.php').replace(queryParameters: {
        'mod': 'space', 'do': 'pm', 'subop': 'view', 'touid': '${widget.uid}', 'mobile': '2',
        '_ycoo_ts': '${DateTime.now().millisecondsSinceEpoch}',
      });
      final response = await client.get(uri, headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if (cookie.isNotEmpty) 'Cookie': cookie,
        'Referer': '${SiteConfig.base}home.php?mod=space&do=pm&mobile=2',
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
      final html = NetClient.decode(response.bodyBytes);
      final doc = parser.parse(html);
      for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }

      final result = <_ChatMessage>[];
      final seen = <String>{};
      // 标准 Discuz：每条私信对应一个 dl#pmlist_<pmid>。
      final primary = doc.querySelectorAll('dl[id^="pmlist_"]');
      for (final node in primary) _add(result, seen, _parseMessage(node), node.attributes['id']);

      // 手机版/Comiis 有些版本会去掉 pmlist_* id，但仍保留 dd.ptm。
      if (result.isEmpty) {
        for (final node in doc.querySelectorAll('dl.bbda.cl,dl.bbda,dl.cl,dl')) {
          if (node.querySelector('dd.ptm') == null) continue;
          _add(result, seen, _parseMessage(node));
        }
      }

      // 定制模板可能使用 li/div 容器；只接受明确包含“正文节点”的容器，
      // 避免把整个页面的导航、积分、菜单误当成聊天记录。
      if (result.isEmpty) {
        for (final node in doc.querySelectorAll('li.comiis_pmitem,li.pm_list,li.pml,.comiis_pm_list > li,.pmlist > li,.pm_message,.pml_body,.pm_body,.comiis_pmtext,.comiis_pm_content')) {
          final target = node.localName == 'li' || node.localName == 'div' ? node : node.parent;
          _add(result, seen, _parseMessage(target));
        }
      }

      if (mounted) setState(() { _messages = result; _loading = false; });
      _jumpBottom();
    } catch (e) {
      if (mounted) setState(() { _error = _clean(e.toString().replaceFirst('Exception: ', '')); _loading = false; });
    }
  }

  void _add(List<_ChatMessage> result, Set<String> seen, _ChatMessage? message, [String? id]) {
    if (message == null) return;
    final key = id == null || id.isEmpty ? '${message.uid}|${message.sender}|${message.body}|${message.time}' : 'id:$id';
    if (seen.add(key)) result.add(message);
  }

  _ChatMessage? _parseMessage(dynamic node) {
    if (node == null) return null;
    final content = node.querySelector('dd.ptm') ?? node.querySelector('.pm_message,.pml_body,.pm_body,.comiis_pmtext,.comiis_pm_content,.pmtext');
    if (content == null) return null;
    final author = node.querySelector('dd.ptm a[href*="mod=space&uid="],dd.ptm a[href*="uid="],a[href*="mod=space&uid="],a[href*="mod=space%26uid="],a[href*="uid="]');
    final sender = _cleanText(author);
    final uid = _extractUid(node);
    var body = _cleanText(content);
    if (sender.isNotEmpty) body = _removeFirst(body, sender);
    final timeNode = content.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]') ?? node.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]');
    final time = _cleanText(timeNode);
    if (time.isNotEmpty) body = _removeFirst(body, time);
    body = _clean(body.replaceAll(RegExp(r'^[:：\-·\s]+|[:：\-·\s]+$'), ''));
    if (body.isEmpty || _isUiOnly(body)) return null;
    final currentName = _clean(AuthService.instance.username ?? '');
    final finalSender = sender.isNotEmpty ? sender : (uid == AuthService.instance.uid ? currentName : _clean(widget.username));
    return _ChatMessage(uid: uid, sender: finalSender.isEmpty ? _clean(widget.username) : finalSender, body: body, time: time);
  }

  static String _cleanText(dynamic node) {
    if (node == null) return '';
    try {
      final clone = node.clone();
      for (final element in clone.querySelectorAll('i.iconfont,i.comiis-icon,i.comiis_icon,.iconfont,.comiis-icon,svg,[class*="iconfont"],[class*="comiis-icon"]')) { element.remove(); }
      return forumText((clone.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    } catch (_) { return forumText((node.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()); }
  }

  static int _extractUid(dynamic node) {
    final links = node.querySelectorAll('a[href*="mod=space&uid="],a[href*="mod=space%26uid="],a[href*="?uid="],a[href*="&uid="],a[href*="uid="]');
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final match = RegExp(r'(?:[?&]|%3F|%26)uid=(\d+)', caseSensitive: false).firstMatch(href);
      final uid = int.tryParse(match?.group(1) ?? '');
      if (uid != null && uid > 0) return uid;
    }
    return 0;
  }

  static bool _isUiOnly(String text) => RegExp(r'^(站内私信|站内消息|私信|消息|查看|详情|回复|删除)$').hasMatch(text.trim());
  static String _removeFirst(String source, String value) { final target = value.trim(); if (target.isEmpty) return source; final index = source.indexOf(target); if (index < 0) return source; return '${source.substring(0, index)}${source.substring(index + target.length)}'.trim(); }

  Future<void> _send() async {
    final text = _clean(_controller.text);
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await MemberServiceV2.instance.sendMessage(to: widget.username, message: text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumText(error)))); return; }
    _controller.clear();
    await _load();
  }

  void _jumpBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); }); }

  bool _isMine(_ChatMessage message) {
    final currentUid = AuthService.instance.uid;
    if (currentUid != null && currentUid > 0 && message.uid > 0) return currentUid == message.uid;
    final currentName = _clean(AuthService.instance.username ?? '');
    return currentName.isNotEmpty && currentName == _clean(message.sender);
  }

  Widget _avatar(int uid) {
    if (uid <= 0) return const CircleAvatar(child: Icon(Icons.person));
    return CircleAvatar(backgroundImage: NetworkImage('${SiteConfig.base}uc_server/avatar.php?uid=$uid&size=small'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _clean(widget.username);
    final currentUid = AuthService.instance.uid ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(titleSpacing: 0, title: Row(children: [_avatar(widget.uid), const SizedBox(width: 10), Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))]), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: Text(_error!, textAlign: TextAlign.center)), const SizedBox(height: 12), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('重试'))]))
          : Column(children: [
              Expanded(child: _messages.isEmpty
                  ? ListView(children: const [SizedBox(height: 180), Center(child: Text('暂无聊天记录'))])
                  : ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 14, 12, 18), itemCount: _messages.length, itemBuilder: (context, index) {
                      final message = _messages[index]; final mine = _isMine(message);
                      return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
                        if (!mine) ...[_avatar(message.uid > 0 ? message.uid : widget.uid), const SizedBox(width: 8)],
                        Flexible(child: Container(constraints: const BoxConstraints(maxWidth: 320), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: mine ? scheme.primaryContainer : Colors.white, borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message.body, style: const TextStyle(fontSize: 15, height: 1.45)), if (message.time.isNotEmpty) ...[const SizedBox(height: 4), Align(alignment: Alignment.centerRight, child: Text(message.time, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)))]]))),
                        if (mine) ...[const SizedBox(width: 8), _avatar(currentUid)],
                      ]));
                    })),
              SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), color: Colors.white, child: Row(children: [
                Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: '发送给 $name', filled: true, fillColor: const Color(0xFFF0F0F4), border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
              ]))),
            ]),
    );
  }
}
