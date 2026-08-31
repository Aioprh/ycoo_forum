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

      String? conversationHref;
      final listUri = Uri.parse('${SiteConfig.base}home.php').replace(queryParameters: {
        'mod': 'space',
        'do': 'pm',
        'mobile': '2',
        '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      try {
        final listResponse = await client.get(listUri, headers: headers).timeout(const Duration(seconds: 20));
        if (listResponse.statusCode == 200) {
          final listHtml = NetClient.decode(listResponse.bodyBytes);
          if (_looksLikeLogin(listHtml)) throw Exception('登录态已失效，请重新登录论坛');
          final listDoc = parser.parse(listHtml);
          for (final node in listDoc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
          for (final a in listDoc.querySelectorAll('a[href]')) {
            final href = (a.attributes['href'] ?? '').trim();
            if (!_isConversationHref(href)) continue;
            if (_hrefUid(href) == widget.uid) {
              conversationHref = href;
              break;
            }
            final parent = a.parent;
            final parentText = _clean(parent?.text ?? '');
            final parentHasUid = parent?.querySelector('a[href*="touid=${widget.uid}"],a[href*="uid=${widget.uid}"]') != null;
            if (parentHasUid && parentText.isNotEmpty) {
              conversationHref = href;
              break;
            }
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('登录态已失效')) rethrow;
      }

      final conversationUri = conversationHref != null && conversationHref!.isNotEmpty
          ? Uri.parse(SiteConfig.resolve(conversationHref!)).replace(queryParameters: {
              ...Uri.parse(SiteConfig.resolve(conversationHref!)).queryParameters,
              '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
            })
          : Uri.parse('${SiteConfig.base}home.php').replace(queryParameters: {
              'mod': 'space',
              'do': 'pm',
              'subop': 'view',
              'touid': '${widget.uid}',
              'mobile': '2',
              '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
            });

      final response = await client.get(conversationUri, headers: {
        ...headers,
        'Referer': listUri.toString(),
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('请求失败 HTTP ${response.statusCode}');
      final html = NetClient.decode(response.bodyBytes);
      if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
      final doc = parser.parse(html);
      for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }

      final list = <NativeMessage>[];
      final seen = <String>{};
      const selectors = <String>[
        'dl.pml', 'dl[id^="pmlist_"]', 'li.pm_list', 'li.pml', '.pm_list > li', '.pml > li',
        '.pmlist li', '[id*="pmlist"] li', '.comiis_pm_list li', '.comiis_pmitem', '.comiis_pm_content',
      ];
      for (final selector in selectors) {
        for (final node in doc.querySelectorAll(selector)) {
          final message = _parseNode(node);
          if (message == null) continue;
          final key = '${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
          if (seen.add(key)) list.add(message);
        }
      }

      if (list.isEmpty) {
        for (final node in doc.querySelectorAll('li,article,div')) {
          final text = _cleanNodeText(node);
          if (text.length < 2 || text.length > 500) continue;
          if (RegExp(r'^(首页|消息|私信|返回|刷新|发送|回复|删除)$').hasMatch(text)) continue;
          final hasConversationLink = node.querySelector('a[href*="touid=${widget.uid}"],a[href*="subop=view"],a[href*="do=pm"]') != null;
          if (!hasConversationLink) continue;
          final message = _parseNode(node);
          if (message == null) continue;
          final key = '${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
          if (seen.add(key)) list.add(message);
        }
      }

      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
      }
      _jumpBottom();
    } catch (e) {
      if (mounted) setState(() { _error = _clean(e.toString().replaceFirst('Exception: ', '')); _loading = false; });
    }
  }

  NativeMessage? _parseNode(dynamic node) {
    final author = node.querySelector('a[href*="uid="],a[href*="touid="],a[href*="mod=space"],a[href*="username="]');
    var sender = _cleanNodeText(author);
    final time = _cleanNodeText(node.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]'));
    var body = _cleanNodeText(node.querySelector('.ptm,.pml_body,.pm_body,.pm_message,.comiis_pmtext,.comiis_pm_content,.pmtext') ?? node);
    if (sender.isNotEmpty) body = body.replaceFirst(sender, '').trim();
    if (time.isNotEmpty) body = body.replaceFirst(time, '').trim();
    body = _clean(body.replaceAll(RegExp(r'^[:：\-·\s]+|[:：\-·\s]+$'), ''));
    if (body.isEmpty || RegExp(r'^(站内私信|站内消息|私信|消息|查看|详情|回复|删除)$').hasMatch(body)) return null;
    if (sender.isEmpty) sender = _clean(widget.username);
    return NativeMessage(title: sender, subtitle: body, sender: sender, time: time, uid: widget.uid);
  }

  static String _cleanNodeText(dynamic node) {
    if (node == null) return '';
    try {
      final clone = node.clone(true);
      for (final icon in clone.querySelectorAll('i.iconfont,i.comiis-icon,i.comiis_icon,.iconfont,.comiis-icon,[class*="iconfont"],[class*="comiis-icon"],[class*="icon-"]')) {
        icon.remove();
      }
      for (final el in clone.querySelectorAll('svg')) { el.remove(); }
      return forumText((clone.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    } catch (_) {
      return forumText((node.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    }
  }

  static bool _isConversationHref(String href) {
    final h = href.toLowerCase();
    return h.contains('do=pm') || h.contains('ac=pm') || h.contains('pmid=') || h.contains('touid=') || h.contains('subop=view');
  }

  static int _hrefUid(String href) {
    for (final key in const ['touid', 'uid', 'fuid']) {
      final m = RegExp('[?&]$key=(\\d+)', caseSensitive: false).firstMatch(href);
      final v = int.tryParse(m?.group(1) ?? '');
      if (v != null && v > 0) return v;
    }
    return 0;
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final username = forumText(widget.username);
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(username),
        actions: [IconButton(onPressed: _load, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(forumText(_error!), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('重试'))]))
              : Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _messages.isEmpty
                          ? ListView(children: const [SizedBox(height: 180), Center(child: Text('暂无聊天记录'))])
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                              itemCount: _messages.length,
                              itemBuilder: (_, i) {
                                final m = _messages[i];
                                final mine = _isMine(m);
                                return Align(
                                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 310),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(forumText(m.subtitle), style: const TextStyle(fontSize: 15, height: 1.45)),
                                      if (m.time.isNotEmpty) ...[const SizedBox(height: 4), Text(forumText(m.time), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))],
                                    ]),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  SafeArea(top: false, child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(children: [
                      Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: '发送给 $username', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
                      const SizedBox(width: 8),
                      IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
                    ]),
                  )),
                ]),
    );
  }

  bool _isMine(NativeMessage message) {
    final currentUid = AuthService.instance.uid;
    if (currentUid != null && currentUid > 0 && message.uid == currentUid) return true;
    final currentName = _clean(AuthService.instance.username ?? '');
    final sender = _clean(message.sender);
    return currentName.isNotEmpty && sender.isNotEmpty && sender == currentName;
  }
}
