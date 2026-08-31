import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../services/site_config.dart';
import '../services/auth_service.dart';
import '../services/member_service_v2.dart';
import '../services/net_client.dart';
import '../utils/forum_text.dart';

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
      final headers = <String, String>{
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if (cookie.isNotEmpty) 'Cookie': cookie,
      };

      final conversationUri = Uri.parse('${SiteConfig.base}home.php').replace(queryParameters: {
        'mod': 'space', 'do': 'pm', 'subop': 'view', 'touid': '${widget.uid}', 'mobile': '2',
        '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await client.get(conversationUri, headers: {
        ...headers,
        'Referer': '${SiteConfig.base}home.php?mod=space&do=pm&mobile=2',
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
      final html = NetClient.decode(response.bodyBytes);
      if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');

      final doc = parser.parse(html);
      for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
      final list = <NativeMessage>[];
      final seen = <String>{};

      // Discuz 标准模板：一条真实私信就是一个 dl#pmlist_<pmid>。
      // 不能同时遍历它的子节点，否则同一条消息会被重复解析。
      final canonicalNodes = doc.querySelectorAll('dl[id^="pmlist_"]');
      for (final node in canonicalNodes) {
        final message = _parseNode(node);
        if (message == null) continue;
        final nodeId = node.attributes['id'] ?? '';
        final key = nodeId.isNotEmpty ? 'pmid:$nodeId' : '${message.uid}|${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
        if (seen.add(key)) list.add(message);
      }

      // Comiis 定制模板没有 pmlist_* 时再启用兜底，且不再匹配正文子节点。
      if (canonicalNodes.isEmpty) {
        for (final selector in const ['li.comiis_pmitem','li.pm_list','li.pml','.comiis_pm_list > li','.pmlist > li']) {
          for (final node in doc.querySelectorAll(selector)) {
            final message = _parseNode(node);
            if (message == null) continue;
            final key = '${message.uid}|${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
            if (seen.add(key)) list.add(message);
          }
          if (list.isNotEmpty) break;
        }
      }

      if (list.isEmpty) {
        for (final node in doc.querySelectorAll('dl,li,article,section')) {
          final links = node.querySelectorAll('a[href*="mod=space&uid="],a[href*="mod=space%26uid="],a[href*="?uid="],a[href*="&uid="]');
          if (links.isEmpty) continue;
          final message = _parseNode(node);
          if (message == null) continue;
          final key = '${message.uid}|${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
          if (seen.add(key)) list.add(message);
        }
      }

      if (mounted) setState(() { _messages = list; _loading = false; });
      _jumpBottom();
    } catch (e) {
      if (mounted) setState(() { _error = _clean(e.toString().replaceFirst('Exception: ', '')); _loading = false; });
    }
  }

  NativeMessage? _parseNode(dynamic node) {
    if (node == null) return null;
    final contentNode = node.querySelector('dd.ptm') ?? node.querySelector(
      '.pm_message,.pml_body,.pm_body,.comiis_pmtext,.comiis_pm_content,.pmtext,[class*="pm_content"],[class*="pm_message"],[class*="pmtext"]',
    );
    if (contentNode == null && node.querySelector('dd') == null) return null;

    final author = contentNode?.querySelector('a[href*="mod=space&uid="],a[href*="mod=space%26uid="],a[href*="uid="],a[href*="username="]');
    var sender = _cleanNodeText(author);
    final authorUid = _authorUid(node);
    var body = _cleanNodeText(contentNode ?? node);
    if (sender.isNotEmpty) body = _removeFirstText(body, sender);
    final currentName = _clean(AuthService.instance.username ?? '');
    if (currentName.isNotEmpty) body = _removeFirstText(body, currentName);
    final timeNode = contentNode?.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]') ?? node.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]');
    final time = _cleanNodeText(timeNode);
    if (time.isNotEmpty) body = _removeFirstText(body, time);
    body = _clean(body.replaceAll(RegExp(r'^[:：\-·\s]+|[:：\-·\s]+$'), ''));
    if (body.isEmpty || _isUiOnly(body)) return null;
    if (sender.isEmpty) sender = authorUid == AuthService.instance.uid ? currentName : _clean(widget.username);
    if (sender.isEmpty) sender = '站内私信';
    return NativeMessage(title: sender, subtitle: body, sender: sender, time: time, uid: authorUid);
  }

  static String _removeFirstText(String source, String value) {
    final v = value.trim();
    if (v.isEmpty) return source;
    final index = source.indexOf(v);
    if (index < 0) return source;
    return '${source.substring(0, index)}${source.substring(index + v.length)}'.trim();
  }

  static int _authorUid(dynamic node) {
    final links = node.querySelectorAll('a[href*="mod=space&uid="],a[href*="mod=space%26uid="],a[href*="?uid="],a[href*="&uid="],a[href*="uid="]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'(?:[?&]|%3F|%26)uid=(\d+)', caseSensitive: false).firstMatch(href);
      final value = int.tryParse(m?.group(1) ?? '');
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  static String _cleanNodeText(dynamic node) {
    if (node == null) return '';
    try {
      final clone = node.clone(true);
      for (final icon in clone.querySelectorAll('i.iconfont,i.comiis-icon,i.comiis_icon,.iconfont,.comiis-icon,[class*="iconfont"],[class*="comiis-icon"],[class*="icon-"]')) { icon.remove(); }
      for (final el in clone.querySelectorAll('svg')) { el.remove(); }
      return forumText((clone.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    } catch (_) {
      return forumText((node.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    }
  }

  static bool _isUiOnly(String text) => RegExp(r'^(首页|消息|私信|返回|刷新|发送|回复|删除|查看|详情|上一页|下一页)$').hasMatch(text.trim());

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    final text = _cleanNodeText(doc.body);
    return text.isNotEmpty && RegExp(r'(用户名|登录密码)').hasMatch(text) && text.contains('登录') && !html.contains('action=logout');
  }

  Future<void> _send() async {
    final text = _clean(_controller.text);
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await MemberServiceV2.instance.sendMessage(to: widget.username, message: text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumText(error))));
      return;
    }
    _controller.clear();
    await _load();
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });
  }

  Widget _avatar(int uid) {
    if (uid <= 0) return CircleAvatar(child: Text('?'));
    return CircleAvatar(
      backgroundImage: NetworkImage('${SiteConfig.base}uc_server/avatar.php?uid=$uid&size=small'),
      onBackgroundImageError: (_, __) {},
    );
  }

  String? _dateLabel(String time) => RegExp(r'(\d{4}-\d{1,2}-\d{1,2})').firstMatch(time)?.group(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final username = forumText(widget.username);
    final currentUid = AuthService.instance.uid ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [_avatar(widget.uid), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(username, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), Text('站内私信', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))])]),
        actions: [IconButton(onPressed: _load, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: Text(forumText(_error!), textAlign: TextAlign.center)), const SizedBox(height: 12), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('重试'))]))
              : Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _messages.isEmpty
                          ? ListView(children: const [SizedBox(height: 180), Center(child: Text('暂无聊天记录'))])
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                              itemCount: _messages.length,
                              itemBuilder: (_, i) {
                                final m = _messages[i];
                                final mine = _isMine(m);
                                final date = _dateLabel(m.time);
                                final previousDate = i > 0 ? _dateLabel(_messages[i - 1].time) : null;
                                return Column(children: [
                                  if (date != null && date != previousDate) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)), child: Text(date, style: const TextStyle(fontSize: 11, color: Colors.white))),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
                                      if (!mine) ...[_avatar(m.uid > 0 ? m.uid : widget.uid), const SizedBox(width: 8)],
                                      Flexible(child: Container(
                                        constraints: const BoxConstraints(maxWidth: 320),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(color: mine ? scheme.primaryContainer : Colors.white, borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 3, offset: const Offset(0, 1))]),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(forumText(m.subtitle), style: const TextStyle(fontSize: 15, height: 1.45)), if (m.time.isNotEmpty && _dateLabel(m.time) == null) ...[const SizedBox(height: 4), Align(alignment: Alignment.centerRight, child: Text(forumText(m.time), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)))]]),
                                      )),
                                      if (mine) ...[const SizedBox(width: 8), _avatar(currentUid)],
                                    ]),
                                  ),
                                ]);
                              },
                            ),
                    ),
                  ),
                  SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), decoration: const BoxDecoration(color: Colors.white), child: Row(children: [
                    Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: '发送给 $username', filled: true, fillColor: const Color(0xFFF0F0F4), border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
                  ]))),
                ]),
    );
  }

  bool _isMine(NativeMessage message) {
    final currentUid = AuthService.instance.uid;
    if (currentUid != null && currentUid > 0 && message.uid > 0) return message.uid == currentUid;
    final currentName = _clean(AuthService.instance.username ?? '');
    final sender = _clean(message.sender);
    return currentName.isNotEmpty && sender.isNotEmpty && sender == currentName;
  }
}
