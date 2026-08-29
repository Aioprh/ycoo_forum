import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/thread_detail.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_page.dart';
import 'thread_list_page.dart';

class DetailPage extends StatefulWidget {
  final int tid;
  final String title;
  const DetailPage({super.key, required this.tid, required this.title});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  ThreadDetail? _detail;
  WebViewController? _bodyController;
  final TextEditingController _replyCtrl = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  bool _loading = true;
  bool _sending = false;
  bool _buying = false;
  bool _loggedIn = false;
  String? _error;
  double _bodyHeight = 0;

  @override
  void initState() {
    super.initState();
    _initSessionAndFetch();
  }

  Future<void> _initSessionAndFetch() async {
    await AuthService.instance.init();
    await AuthService.instance.checkLoggedIn();
    if (mounted) setState(() => _loggedIn = AuthService.instance.isLoggedIn);
    await _fetch();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final detail = await ApiService.instance.fetchThreadDetail(widget.tid);
      if (!mounted) return;
      setState(() => _detail = detail);
      _bodyHeight = 0;
      _bodyController = _buildBodyController(detail.bodyHtml);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WebViewController _buildBodyController(String bodyHtml) {
    final safeHtml = bodyHtml.isEmpty ? '<div></div>' : bodyHtml;
    final doc = '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"><base href="https://www.ycoo.net/"><style>body{margin:0;padding:16px;font-size:16px;line-height:1.7;color:#333;word-wrap:break-word}img{max-width:100%!important;height:auto;border-radius:6px}a{color:#4e6ef2}pre,code{white-space:pre-wrap;word-break:break-all}table{width:100%;border-collapse:collapse}.post-card{background:#f7f8fa;border-radius:10px;padding:12px 14px;margin:12px 0}.post-card:first-child{margin-top:0}.post-hd{display:flex;align-items:center;flex-wrap:wrap;gap:6px}.p-floor{color:#8a919f;font-size:12px}.p-author{font-weight:600;color:#222;font-size:14px}.p-level{color:#4e6ef2;font-size:11px;background:#eef1fd;padding:1px 6px;border-radius:8px}.p-time{color:#999;font-size:12px;margin-top:4px}.post-card .p-body{margin-top:8px;font-size:15px}</style></head><body>$safeHtml</body></html>''';
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => _fitWebViewHeight()))
      ..loadHtmlString(doc, baseUrl: 'https://www.ycoo.net/');
  }

  Future<void> _fitWebViewHeight() async {
    try {
      final raw = await _bodyController!.runJavaScriptReturningResult('document.documentElement.scrollHeight').then((v) => v.toString());
      final h = double.tryParse(raw.replaceAll(RegExp(r'"'), '')) ?? 0;
      if (h > 0 && mounted && h != _bodyHeight) setState(() => _bodyHeight = h + 8);
    } catch (_) {}
  }

  Future<void> _openPurchase() async {
    final d = _detail;
    if (d == null || _buying) return;
    if (!_loggedIn) {
      await _openLogin();
      if (!_loggedIn) return;
    }

    final priceText = d.price == null ? '当前价格以论坛页面为准' : '${d.price} ${d.currency}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('购买主题'),
        content: Text('确定购买这个付费主题吗？\n\n价格：$priceText\n\n点击“确定”后将直接使用当前论坛账号购买。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确定购买')),
        ],
      ),
    ) ?? false;
    if (!confirmed || !mounted) return;

    setState(() => _buying = true);
    final result = await ApiService.instance.purchaseThread(d.tid);
    if (!mounted) return;
    setState(() => _buying = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      await _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _buildBody(context),
      bottomNavigationBar: _buildComposer(context),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final theme = Theme.of(context);
    final d = _detail;
    if (d == null) return const SizedBox.shrink();
    if (d.isPaid) {
      return SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          Expanded(child: Text(d.price == null ? '付费主题' : '付费主题 · ${d.price} ${d.currency}', style: const TextStyle(fontWeight: FontWeight.w600))),
          FilledButton.icon(
            onPressed: _buying ? null : _openPurchase,
            icon: _buying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shopping_cart_outlined),
            label: Text(_buying ? '购买中…' : '购买主题'),
          ),
        ]),
      ));
    }
    if (!_loggedIn) {
      return SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: OutlinedButton.icon(onPressed: _openLogin, icon: const Icon(Icons.login, size: 18), label: const Text('登录后回帖'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46))),
      ));
    }
    return SafeArea(top: false, child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: theme.colorScheme.surface, border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)))),
      child: Row(children: [
        Expanded(child: TextField(controller: _replyCtrl, focusNode: _replyFocus, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _sendReply(), decoration: const InputDecoration(hintText: '说点什么吧……', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))), contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9)))),
        const SizedBox(width: 8),
        IconButton(onPressed: _sending ? null : _sendReply, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), color: theme.colorScheme.primary),
      ]),
    ));
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (ok == true && mounted) {
      await AuthService.instance.init();
      await AuthService.instance.checkLoggedIn();
      setState(() => _loggedIn = AuthService.instance.isLoggedIn);
      await _fetch();
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text;
    if (text.trim().isEmpty) return;
    final d = _detail;
    if (d == null) return;
    setState(() => _sending = true);
    final err = await AuthService.instance.reply(d.tid, d.fid, text);
    if (!mounted) return;
    setState(() => _sending = false);
    final messenger = ScaffoldMessenger.of(context);
    if (err == null) {
      _replyCtrl.clear();
      _replyFocus.unfocus();
      messenger.showSnackBar(const SnackBar(content: Text('回帖成功'), duration: Duration(seconds: 2)));
      await _fetch();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _detail == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('详情加载失败'), const SizedBox(height: 8), FilledButton(onPressed: _fetch, child: const Text('重试'))]));
    final d = _detail!;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      _header(context, d),
      const Divider(),
      if (d.bodyHtml.isEmpty && d.isPaid)
        _paidNotice(context, d)
      else if (d.bodyHtml.isEmpty)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('该主题暂时没有可显示的正文。', style: TextStyle(color: Colors.grey))))
      else
        Padding(padding: const EdgeInsets.only(top: 8), child: SizedBox(height: _bodyHeight > 0 ? _bodyHeight : MediaQuery.of(context).size.height * 0.72, child: WebViewWidget(controller: _bodyController!))),
    ]);
  }

  Widget _paidNotice(BuildContext context, ThreadDetail d) {
    return Padding(padding: const EdgeInsets.all(20), child: Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      const Icon(Icons.lock_outline, size: 42),
      const SizedBox(height: 12),
      Text(d.price == null ? '此主题需要购买后查看' : '此主题需支付 ${d.price} ${d.currency} 后查看', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _buying ? null : _openPurchase, icon: const Icon(Icons.shopping_cart_outlined), label: const Text('购买主题')),
    ]))));
  }

  Widget _header(BuildContext context, ThreadDetail d) {
    final theme = Theme.of(context);
    return Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(d.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      Row(children: [
        CircleAvatar(radius: 18, backgroundImage: d.avatar.isNotEmpty ? NetworkImage(d.avatar) : null, child: d.avatar.isNotEmpty ? null : const Icon(Icons.person, size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(d.author, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), if (d.level.isNotEmpty) ...[const SizedBox(width: 6), Text(d.level, style: TextStyle(fontSize: 11, color: theme.primaryColor))]]), if (d.time.isNotEmpty) Text(d.time, style: const TextStyle(fontSize: 11.5, color: Colors.grey))])),
        if (d.boardName.isNotEmpty) GestureDetector(onTap: d.fid == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BoardThreadListPage(filter: d.boardName, fid: d.fid))), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Text(d.boardName, style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary)))),
      ]),
    ]));
  }
}
