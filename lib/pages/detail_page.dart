import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/thread_detail.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/thread_interaction_service.dart';
import '../widgets/native_comment_list.dart';
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
  WebViewController? _commentsController;
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();

  bool _loading = true;
  bool _sending = false;
  bool _buying = false;
  bool _loggedIn = false;
  bool _favorited = false;
  bool _liked = false;
  bool _interacting = false;
  bool _commentsExpanded = true;
  String? _error;
  double _bodyHeight = 0;
  double _commentsHeight = 0;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
      final d = await ApiService.instance.fetchThreadDetail(widget.tid);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _likeCount = d.likeCount;
        _liked = d.likedByMe;
        _bodyHeight = 0;
        _commentsHeight = 0;
      });
      _bodyController = d.isPaid || d.bodyHtml.trim().isEmpty ? null : _web(d.bodyHtml, false);
      _commentsController = null;
      if (_loggedIn) await _loadInteractionState();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInteractionState() async {
    final d = _detail;
    if (d == null) return;
    try {
      final s = await ThreadInteractionService.instance.fetchState(detail: d);
      if (!mounted) return;
      setState(() {
        _likeCount = s.likeCount;
        _liked = s.likedByMe;
        _favorited = s.favorited;
      });
    } catch (_) {}
  }

  WebViewController _web(String html, bool comments) {
    final postCss = '''
      body { padding: 4px 2px 18px; font-size: 16px; line-height: 1.85; }
      .post-card { background: #ffffff; border: 1px solid #e7e8ee; border-radius: 16px; padding: 16px; margin: 0 0 12px; box-shadow: 0 2px 10px rgba(30,35,55,.035); }
      .post-card .post-hd { padding-bottom: 11px; margin-bottom: 11px; border-bottom: 1px solid #eef0f4; }
      .post-card .p-floor { display: inline-block; padding: 3px 8px; background: #eef1ff; color: #536dfe; border-radius: 8px; font-weight: 700; }
      .post-card .p-author { font-weight: 750; color: #20232c; }
      .post-card .p-level { color: #536dfe; background: #eef1ff; padding: 3px 8px; border-radius: 9px; }
      .post-card .p-time { color: #9299a7; font-size: 12px; }
      .post-card .p-body { margin-top: 10px; color: #252832; font-size: 15.5px; line-height: 1.82; }
    ''';
    final commentCss = '''
      body { padding: 2px 2px 8px; font-size: 14px; line-height: 1.75; }
      .post-card { position: relative; background: #f8f9fc; border: 1px solid #e9ebf1; border-radius: 15px; padding: 13px 14px; margin: 0 0 9px; }
      .post-card .post-hd { display: flex; align-items: center; flex-wrap: wrap; gap: 5px; padding-bottom: 9px; margin-bottom: 9px; border-bottom: 1px solid #eceef3; }
      .post-card .p-floor { order: 10; margin-left: auto; color: #8d95a3; font-size: 11px; font-weight: 700; }
      .post-card .p-author { font-size: 14px; font-weight: 700; color: #272b35; }
      .post-card .p-level { color: #5f6fbb; background: #eef1fa; padding: 2px 7px; border-radius: 8px; font-size: 10px; }
      .post-card .p-time { color: #9aa1ad; font-size: 11px; }
      .post-card .p-body { color: #454a56; font-size: 14px; line-height: 1.75; }
    ''';
    final doc = '''<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<base href="https://www.ycoo.net/">
<style>
*{box-sizing:border-box}html,body{margin:0;padding:0;background:transparent;color:#252832;overflow-wrap:anywhere;-webkit-font-smoothing:antialiased}
p{margin:0 0 11px}h1,h2,h3,h4{line-height:1.4;margin:18px 0 10px;color:#171a21}a{color:#536dfe;text-decoration:none}strong,b{color:#171a21}
img{display:block!important;width:auto!important;max-width:100%!important;height:auto!important;max-height:72vh!important;object-fit:contain!important;border-radius:12px;margin:12px auto!important}
video,iframe{max-width:100%!important;height:auto!important;border-radius:12px}table{width:100%!important;max-width:100%!important;border-collapse:collapse}td,th{padding:7px;overflow-wrap:anywhere;border:1px solid #e3e6ec}pre,code{white-space:pre-wrap;word-break:break-word}code{background:#f1f3f6;padding:2px 5px;border-radius:5px}pre{background:#f4f5f7;padding:12px 14px;border-radius:10px;overflow:hidden}blockquote{margin:12px 0;padding:9px 13px;border-left:3px solid #8a9cff;background:#f4f6ff;color:#687080;border-radius:0 10px 10px 0}
${comments ? commentCss : postCss}
</style></head><body>$html</body></html>''';

    late WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) async {
        try {
          await controller.runJavaScript("document.querySelectorAll('img').forEach(function(i){i.style.width='auto';i.style.maxWidth='100%';i.style.height='auto';i.style.maxHeight='72vh';i.style.objectFit='contain';});");
          final raw = await controller.runJavaScriptReturningResult('Math.max(document.body.scrollHeight,document.documentElement.scrollHeight)');
          final h = double.tryParse(raw.toString().replaceAll('"', '')) ?? 0;
          if (!mounted || h <= 0) return;
          setState(() => comments ? _commentsHeight = h + 8 : _bodyHeight = h + 8);
        } catch (_) {}
      }))
      ..loadHtmlString(doc, baseUrl: 'https://www.ycoo.net/');
    return controller;
  }

  Future<void> _purchase() async {
    final d = _detail;
    if (d == null || _buying) return;
    if (!_loggedIn) { await _login(); if (!_loggedIn) return; }
    final price = d.price == null ? '以论坛页面为准' : '${d.price} ${d.currency}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('购买主题'),
        content: Text('确定购买这个付费主题吗？\n\n价格：$price'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定购买')),
        ],
      ),
    ) ?? false;
    if (!ok || !mounted) return;
    setState(() => _buying = true);
    final result = await ApiService.instance.purchaseThread(d.tid);
    if (!mounted) return;
    setState(() => _buying = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) await _fetch();
  }

  Future<void> _login() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (ok == true && mounted) {
      await AuthService.instance.init();
      await AuthService.instance.checkLoggedIn();
      setState(() => _loggedIn = AuthService.instance.isLoggedIn);
      await _fetch();
    }
  }

  Future<void> _reply() async {
    final d = _detail;
    final text = _replyCtrl.text.trim();
    if (d == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final err = await AuthService.instance.reply(d.tid, d.fid, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (err == null) {
      _replyCtrl.clear();
      _replyFocus.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('回帖成功')));
      await _fetch();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _like(ThreadDetail d) async {
    if (!_loggedIn) { await _login(); if (!_loggedIn) return; }
    if (_interacting || d.firstPid <= 0) return;
    setState(() => _interacting = true);
    final err = await ThreadInteractionService.instance.toggleLike(tid: d.tid, pid: d.firstPid, like: !_liked);
    if (!mounted) return;
    if (err != null) {
      setState(() => _interacting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() { _liked = !_liked; _likeCount += _liked ? 1 : -1; if (_likeCount < 0) _likeCount = 0; _interacting = false; });
  }

  Future<void> _favorite(ThreadDetail d) async {
    if (!_loggedIn) { await _login(); if (!_loggedIn) return; }
    if (_interacting) return;
    setState(() => _interacting = true);
    final err = await ThreadInteractionService.instance.toggleFavorite(tid: d.tid, favorite: !_favorited);
    if (!mounted) return;
    if (err != null) {
      setState(() => _interacting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() { _favorited = !_favorited; _interacting = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: s.surfaceContainerLowest,
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis), scrolledUnderElevation: 1),
      body: _body(context),
      bottomNavigationBar: _composer(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _detail == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 42), const SizedBox(height: 12),
        const Text('详情加载失败'), const SizedBox(height: 8),
        FilledButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: const Text('重新加载')),
      ]));
    }

    final d = _detail!;
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 28),
        children: [
          _header(context, d),
          _actions(context, d),
          _sectionTitle(context, '帖子正文', Icons.article_outlined, '楼主发布的主题内容'),
          if (d.isPaid) _paidNotice(context, d)
          else if (_bodyController != null) _webCard(context, _bodyController!, _bodyHeight, isComment: false)
          else _empty(context, '暂无正文内容'),
          if (_commentsController != null) ...[
            const SizedBox(height: 4),
            _commentsSection(context),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon, String subtitle) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 9),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: s.primaryContainer, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 20, color: s.primary)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant)),
        ])),
      ]),
    );
  }

  Widget _commentsSection(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          onTap: () => setState(() => _commentsExpanded = !_commentsExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              Container(width: 4, height: 25, decoration: BoxDecoration(color: s.secondary, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('评论 / 回复', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('原生楼层 · ${_detail?.commentsHtml.trim().isEmpty == false ? '按楼层浏览' : '暂无回复'}', style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant)),
              ])),
              Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: s.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(_commentsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20)),
            ]),
          ),
        ),
        if (_commentsExpanded) ...[
          Divider(height: 1, color: s.outlineVariant.withValues(alpha: .4)),
          NativeCommentList(html: _detail?.commentsHtml ?? ''),
        ],
      ]),
    );
  }

  Widget _webCard(BuildContext context, WebViewController c, double height, {required bool isComment}) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.outlineVariant.withValues(alpha: .5))),
      child: SizedBox(height: height > 0 ? height : (isComment ? 180 : 260), child: WebViewWidget(controller: c)),
    );
  }

  Widget _header(BuildContext context, ThreadDetail d) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.outlineVariant.withValues(alpha: .5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (d.boardName.isNotEmpty) GestureDetector(
          onTap: d.fid == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BoardThreadListPage(filter: d.boardName, fid: d.fid))),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: s.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.forum_outlined, size: 14, color: s.primary), const SizedBox(width: 5), Text(d.boardName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.primary))])),
        ),
        const SizedBox(height: 12),
        Text(d.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 21, height: 1.3, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: s.primaryContainer, backgroundImage: d.avatar.isNotEmpty ? NetworkImage(d.avatar) : null, child: d.avatar.isNotEmpty ? null : Icon(Icons.person_rounded, color: s.primary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Flexible(child: Text(d.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))), if (d.level.isNotEmpty) ...[const SizedBox(width: 7), Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: s.secondaryContainer, borderRadius: BorderRadius.circular(8)), child: Text(d.level, style: TextStyle(fontSize: 10, color: s.onSecondaryContainer)))]],),
            if (d.time.isNotEmpty) Text(d.time, style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant)),
          ])),
        ],),
      ]),
    );
  }

  Widget _actions(BuildContext context, ThreadDetail d) {
    final s = Theme.of(context).colorScheme;
    Widget button(IconData icon, String label, {int? count, bool active = false, required VoidCallback onTap}) => Expanded(child: Material(color: active ? s.primary.withValues(alpha: .12) : Colors.transparent, borderRadius: BorderRadius.circular(13), child: InkWell(borderRadius: BorderRadius.circular(13), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 19, color: active ? s.primary : s.onSurfaceVariant), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? s.primary : s.onSurfaceVariant)), if (count != null && count > 0) ...[const SizedBox(width: 3), Text('$count', style: TextStyle(fontSize: 12, color: active ? s.primary : s.onSurfaceVariant))]]))));
    return Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 10), child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: s.surfaceContainerHighest.withValues(alpha: .6), borderRadius: BorderRadius.circular(17)), child: Row(children: [button(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, _liked ? '已点赞' : '点赞', count: _likeCount, active: _liked, onTap: () => _like(d)), const SizedBox(width: 4), button(_favorited ? Icons.star_rounded : Icons.star_border_rounded, _favorited ? '已收藏' : '收藏', active: _favorited, onTap: () => _favorite(d)), const SizedBox(width: 4), button(Icons.reply_rounded, '回复', onTap: () => _replyFocus.requestFocus())])));
  }

  Widget _paidNotice(BuildContext context, ThreadDetail d) {
    final s = Theme.of(context).colorScheme;
    return Container(margin: const EdgeInsets.fromLTRB(12, 0, 12, 12), padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: LinearGradient(colors: [s.primaryContainer, s.surface]), borderRadius: BorderRadius.circular(22), border: Border.all(color: s.outlineVariant.withValues(alpha: .5))), child: Column(children: [Container(width: 64, height: 64, decoration: BoxDecoration(color: s.primary.withValues(alpha: .12), shape: BoxShape.circle), child: Icon(Icons.lock_rounded, size: 30, color: s.primary)), const SizedBox(height: 14), const Text('这是一个付费主题', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(d.price == null ? '购买后即可查看完整内容' : '支付 ${d.price} ${d.currency} 后查看完整内容', textAlign: TextAlign.center, style: TextStyle(color: s.onSurfaceVariant)), const SizedBox(height: 17), FilledButton.icon(onPressed: _buying ? null : _purchase, icon: _buying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shopping_bag_outlined), label: Text(_buying ? '购买中…' : '购买主题'))]));
  }

  Widget _empty(BuildContext context, String text) => Container(margin: const EdgeInsets.fromLTRB(12, 0, 12, 12), padding: const EdgeInsets.symmetric(vertical: 40), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22)), child: Center(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))));

  Widget _composer(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final d = _detail;
    if (d == null || d.isPaid) return const SizedBox.shrink();
    if (!_loggedIn) return SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(16, 9, 16, 9), decoration: BoxDecoration(color: s.surface, border: Border(top: BorderSide(color: s.outlineVariant.withValues(alpha: .45)))), child: OutlinedButton.icon(onPressed: _login, icon: const Icon(Icons.login_rounded, size: 18), label: const Text('登录后参与讨论'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46))));
    return SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), decoration: BoxDecoration(color: s.surface, border: Border(top: BorderSide(color: s.outlineVariant.withValues(alpha: .45)))), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _replyCtrl, focusNode: _replyFocus, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _reply(), decoration: InputDecoration(hintText: '友善地说点什么…', isDense: true, filled: true, fillColor: s.surfaceContainerHighest.withValues(alpha: .65), border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: s.primary.withValues(alpha: .45))), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10))), const SizedBox(width: 6), Material(color: s.primary, shape: const CircleBorder(), child: IconButton(onPressed: _sending ? null : _reply, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded, color: Colors.white)))]));
  }
}