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

      final conversationUri = Uri.parse('${SiteConfig.base}home.php').replace(queryParameters: {
        'mod': 'space',
        'do': 'pm',
        'subop': 'view',
        'touid': '${widget.uid}',
        'mobile': '2',
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

      // Discuz 默认 space_pm_node.htm 使用 dl#pmlist_<pmid> + dd.ptm。
      // Comiis/移动模板的 class 可能不同，因此同时按结构和常见容器兜底。
      final selectors = <String>[
        'dl[id^="pmlist_"]',
        'dl.pml',
        'dl.bbda.cl',
        'dl[class*="pm"]',
        'li.pm_list',
        'li.pml',
        'li[class*="pm"]',
        '.pm_list > li',
        '.pml > li',
        '.pmlist li',
        '[id*="pmlist"] li',
        '.comiis_pm_list li',
        '.comiis_pmitem',
        '.comiis_pm_content',
      ];

      for (final selector in selectors) {
        for (final node in doc.querySelectorAll(selector)) {
          final message = _parseNode(node);
          if (message == null) continue;
          final key = '${message.uid}|${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
          if (seen.add(key)) list.add(message);
        }
      }

      // 最后按“包含用户空间链接 + 非 UI 文本”的结构兜底，兼容定制移动模板。
      if (list.isEmpty) {
        for (final node in doc.querySelectorAll('dl,li,article,section,div')) {
          final authorLinks = node.querySelectorAll('a[href*="mod=space&uid="],a[href*="mod=space%26uid="],a[href*="?uid="],a[href*="&uid="]');
          if (authorLinks.isEmpty) continue;
          final text = _cleanNodeText(node);
          if (text.length < 2 || text.length > 1000 || _isUiOnly(text)) continue;
          final message = _parseNode(node);
          if (message == null) continue;
          final key = '${message.uid}|${message.sender}|${message.subtitle}|${message.time}'.toLowerCase();
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
    if (node == null) return null;

    final author = node.querySelector(
      'a[href*="mod=space&uid="],'
      'a[href*="mod=space%26uid="],'
      'a[href*="touid="],'
      'a[href*="uid="],'
      'a[href*="username="]',
    );
    var sender = _cleanNodeText(author);
    final authorUid = _authorUid(node);

    // 默认 Discuz 私信节点：dd.ptm 中依次为“你/用户名 + 正文 + 时间”。
    // 优先取 ptm，再兼容 Comiis 自定义正文容器。
    final bodyNode = node.querySelector(
      'dd.ptm,.ptm,.pml_body,.pm_body,.pm_message,.comiis_pmtext,.comiis_pm_content,.pmtext,'
      '[class*="pm_content"],[class*="pm_message"],[class*="pmtext"]',
    );
    var body = _cleanNodeText(bodyNode ?? node);

    if (sender.isNotEmpty) body = _removeFirstText(body, sender);
    final currentName = _clean(AuthService.instance.username ?? '');
    if (currentName.isNotEmpty) body = _removeFirstText(body, currentName);

    final timeNode = node.querySelector('.xg1,.xg2,time,[class*="time"],[class*="date"]');
    final time = _cleanNodeText(timeNode);
    if (time.isNotEmpty) body = _removeFirstText(body, time);

    body = _clean(body.replaceAll(RegExp(r'^[:：\-·\s]+|[:：\-·\s]+$'), ''));
    if (body.isEmpty || _isUiOnly(body)) return null;

    if (sender.isEmpty) {
      sender = authorUid == AuthService.instance.uid ? currentName : _clean(widget.username);
    }
    if (sender.isEmpty) sender = '站内私信';

    return NativeMessage(
      title: sender,
      subtitle: body,
      sender: sender,
      time: time,
      // 必须使用实际消息作者 UID；不能把整个会话的 touid 都当成作者 UID。
      uid: authorUid,
    );
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
      for (final icon in clone.querySelectorAll('i.iconfont,i.comiis-icon,i.comiis_icon,.iconfont,.comiis-icon,[class*="iconfont"],[class*="comiis-icon"],[class*="icon-"]')) {
        icon.remove();
      }
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
    if (currentUid != null && currentUid > 0 && message.uid > 0) return message.uid == currentUid;
    final currentName = _clean(AuthService.instance.username ?? '');
    final sender = _clean(message.sender);
    return currentName.isNotEmpty && sender.isNotEmpty && sender == currentName;
  }
}
