import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/thread_detail.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/attachment_download_service.dart';
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
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _loading = true, _sending = false, _buying = false, _rewarding = false;
  bool _loggedIn = false, _favorited = false, _liked = false, _interacting = false;
  bool _commentsExpanded = true;
  String? _error;
  double _bodyHeight = 0;
  int _likeCount = 0;

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _replyCtrl.dispose(); _replyFocus.dispose(); super.dispose(); }

  Future<void> _init() async {
    await AuthService.instance.init();
    await AuthService.instance.checkLoggedIn();
    if (mounted) setState(() => _loggedIn = AuthService.instance.isLoggedIn);
    await _fetch();
  }

  Future<void> _fetch() async {
    final hadDetail = _detail != null;
    if (mounted) setState(() { _loading = !hadDetail; _error = null; });
    try {
      final d = await ApiService.instance.fetchThreadDetail(widget.tid);
      if (!mounted) return;
      final oldBody = _detail?.bodyHtml.trim() ?? '';
      final newBody = d.bodyHtml.trim();
      final changed = oldBody != newBody;
      setState(() {
        _detail = d; _likeCount = d.likeCount; _liked = d.likedByMe;
        if (newBody.isEmpty) { _bodyController = null; _bodyHeight = 0; }
        else if (changed || _bodyController == null) _bodyHeight = 0;
      });
      if (newBody.isNotEmpty && (changed || _bodyController == null)) _bodyController = _web(newBody);
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
      final state = await ThreadInteractionService.instance.fetchState(detail: d);
      if (!mounted) return;
      setState(() { _likeCount = state.likeCount; _liked = state.likedByMe; _favorited = state.favorited; });
    } catch (_) {}
  }

  WebViewController _web(String html) {
    final doc = '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><base href="https://www.ycoo.net/"><style>
*{box-sizing:border-box}html,body{margin:0;padding:0;background:transparent;color:#20232b;overflow-wrap:anywhere;-webkit-font-smoothing:antialiased}p{margin:0 0 13px}h1,h2,h3,h4{line-height:1.4;margin:20px 0 10px;color:#12151c}a{color:#4d63d8;text-decoration:none}strong,b{color:#12151c}ul,ol{padding-left:22px}li{margin:5px 0}img{display:block!important;width:auto!important;max-width:100%!important;height:auto!important;max-height:72vh!important;object-fit:contain!important;border-radius:14px;margin:14px auto!important}video,iframe{max-width:100%!important;border-radius:14px}table{width:100%!important;border-collapse:collapse;margin:12px 0}td,th{padding:8px;overflow-wrap:anywhere;border:1px solid #e1e4ea}pre,code{white-space:pre-wrap;word-break:break-word}code{background:#f0f2f6;padding:2px 6px;border-radius:6px}pre{background:#f3f4f7;padding:14px;border-radius:12px;overflow:hidden}blockquote{margin:14px 0;padding:10px 14px;border-left:3px solid #7184e8;background:#f4f6ff;color:#687080;border-radius:0 12px 12px 0}.attachment-link{display:flex!important;align-items:center;gap:10px;padding:13px 14px;margin:10px 0;background:#f4f6ff;border:1px solid #dce2ff;border-radius:12px;color:#4058d6!important;font-weight:650}
</style></head><body>$html</body></html>''';
    late WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (request) async {
        final url = request.url;
        if (!AttachmentDownloadService.instance.isAttachmentUrl(url)) return NavigationDecision.navigate;
        if (!_loggedIn) { if (mounted) await _login(); return NavigationDecision.prevent; }
        try {
          final started = await AttachmentDownloadService.instance.download(url: url, cookie: AuthService.instance.authCookie, referer: 'https://www.ycoo.net/');
          if (mounted) _snack(started ? '已开始下载附件' : '当前平台暂不支持原生附件下载');
        } catch (e) { if (mounted) _snack('附件下载失败：$e'); }
        return NavigationDecision.prevent;
      }, onPageFinished: (_) async {
        try {
          await controller.runJavaScript("document.querySelectorAll('a').forEach(function(a){try{var h=a.href||'';if(/attachment\\.php|mod=attachment|[?&]aid=|\\/attachment\\/|\\/download\\//i.test(h)){a.classList.add('attachment-link');if(!a.querySelector('.attachment-icon')){var i=document.createElement('span');i.textContent='📎';a.prepend(i);}}}catch(e){}});document.querySelectorAll('img').forEach(function(i){i.style.width='auto';i.style.maxWidth='100%';i.style.height='auto';i.style.maxHeight='72vh';i.style.objectFit='contain';});");
          final raw = await controller.runJavaScriptReturningResult('''(function(){document.querySelectorAll('[style]').forEach(function(e){var st=(e.getAttribute('style')||'').replace(/\\s/g,'').toLowerCase();if(st.indexOf('100vh')>=0||st.indexOf('min-height:')>=0||st.indexOf('height:100%')>=0)e.style.minHeight='0';});return Math.max(document.body.scrollHeight,document.documentElement.scrollHeight);})()''');
          final height = double.tryParse(raw.toString().replaceAll('"', '')) ?? 0;
          if (mounted && height > 0) setState(() => _bodyHeight = height + 10);
        } catch (_) {}
      }))
      ..loadHtmlString(doc, baseUrl: 'https://www.ycoo.net/');
    return controller;
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _login() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (ok == true && mounted) { await AuthService.instance.init(); await AuthService.instance.checkLoggedIn(); setState(() => _loggedIn = AuthService.instance.isLoggedIn); await _fetch(); }
  }

  Future<void> _reply() async {
    final d = _detail, text = _replyCtrl.text.trim();
    if (d == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await AuthService.instance.reply(d.tid, d.fid, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) { _replyCtrl.clear(); _replyFocus.unfocus(); _snack('回帖成功'); await _fetch(); } else { _snack(error); }
  }

  Future<void> _like(ThreadDetail d) async {
    if (!_loggedIn) { await _login(); if (!_loggedIn) return; }
    if (_interacting || d.firstPid <= 0) return;
    setState(() => _interacting = true);
    final error = await ThreadInteractionService.instance.toggleLike(tid: d.tid, pid: d.firstPid, like: !_liked);
    if (!mounted) return;
    if (error != null) { setState(() => _interacting = false); _snack(error); return; }
    setState(() { _liked = !_liked; _likeCount += _liked ? 1 : -1; if (_likeCount < 0) _likeCount = 0; _interacting = false; });
  }

  Future<void> _favorite(ThreadDetail d) async {
    if (!_loggedIn) { await _login(); if (!_loggedIn) return; }
    if (_interacting) return;
    setState(() => _interacting = true);
    final error = await ThreadInteractionService.instance.toggleFavorite(tid: d.tid, favorite: !_favorited);
    if (!mounted) return;
    if (error != null) { setState(() => _interacting = false); _snack(error); return; }
    setState(() { _favorited = !_favorited; _interacting = false; });
  }

  Future<void> _reward(ThreadDetail d) async {
    if (!_loggedIn) { await _login(); if (!_loggedIn) return; }
    if (_rewarding || d.firstPid <= 0) return;
    final input = TextEditingController(text: '10');
    final amount = await showDialog<int>(context: context, builder: (c) => AlertDialog(title: const Text('打赏作者'), content: TextField(controller: input, autofocus: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '打赏数量', suffixText: '积分', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () { final v = int.tryParse(input.text.trim()) ?? 0; if (v > 0) Navigator.pop(c, v); }, child: const Text('确认打赏'))]));
    input.dispose();
    if (amount == null || !mounted) return;
    setState(() => _rewarding = true);
    final result = await ThreadInteractionService.instance.reward(tid: d.tid, pid: d.firstPid, amount: amount);
    if (!mounted) return;
    setState(() => _rewarding = false); _snack(result ?? '打赏成功');
  }

  Future<void> _purchase() async {
    final d = _detail;
    if (d == null || _buying) return;
    if (!_loggedIn) { await _login(); if (!_loggedIn) return; }
    final price = d.price == null ? '以论坛页面为准' : '${d.price} ${d.currency}';
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('购买主题'), content: Text('确定购买这个付费主题吗？\n\n价格：$price'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定购买'))])) ?? false;
    if (!ok || !mounted) return;
    setState(() => _buying = true);
    final result = await ApiService.instance.purchaseThread(d.tid);
    if (!mounted) return;
    setState(() => _buying = false); _snack(result.message); if (result.success) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Scaffold(backgroundColor: s.surfaceContainerLowest, appBar: AppBar(titleSpacing: 8, leading: IconButton(tooltip: '返回', onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded)), title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), actions: [IconButton(tooltip: '刷新', onPressed: _fetch, icon: const Icon(Icons.refresh_rounded)), const SizedBox(width: 4)], backgroundColor: s.surfaceContainerLowest, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0), body: _buildBody(context), bottomNavigationBar: _composer(context));
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _detail == null) return _errorView(context);
    final d = _detail!;
    return RefreshIndicator(onRefresh: _fetch, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(12, 4, 12, 28), children: [
      _hero(context, d), _quickActions(context, d), _sectionHeader(context, '正文', '楼主发布的主题内容', Icons.article_rounded),
      d.isPaid ? _paidNotice(context, d) : (_bodyController == null ? _empty(context, '暂无正文内容') : _webCard(context, _bodyController!, _bodyHeight)),
      if (d.commentsHtml.trim().isNotEmpty) _commentsSection(context, d),
    ]));
  }

  Widget _errorView(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_off_rounded, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(height: 14), const Text('详情加载失败', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), const SizedBox(height: 7), Text('网络或服务器暂时不可用', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)), const SizedBox(height: 16), FilledButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: const Text('重新加载'))])));

  Widget _hero(BuildContext context, ThreadDetail d) {
    final s = Theme.of(context).colorScheme;
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(18, 18, 18, 16), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [s.primaryContainer.withValues(alpha: .72), s.surface]), borderRadius: BorderRadius.circular(26), border: Border.all(color: s.outlineVariant.withValues(alpha: .45))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (d.boardName.isNotEmpty) GestureDetector(onTap: d.fid == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BoardThreadListPage(filter: d.boardName, fid: d.fid))), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: s.surface.withValues(alpha: .75), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.forum_rounded, size: 15, color: s.primary), const SizedBox(width: 6), Text(d.boardName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.primary)), const SizedBox(width: 3), Icon(Icons.chevron_right_rounded, size: 15, color: s.primary)]))),
      const SizedBox(height: 14), Text(d.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23, height: 1.28, fontWeight: FontWeight.w800)), const SizedBox(height: 16),
      Row(children: [CircleAvatar(radius: 22, backgroundColor: s.primaryContainer, backgroundImage: d.avatar.isNotEmpty ? NetworkImage(d.avatar) : null, child: d.avatar.isNotEmpty ? null : Icon(Icons.person_rounded, color: s.primary)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(d.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))), if (d.level.isNotEmpty) ...[const SizedBox(width: 7), _chip(d.level, s.secondaryContainer, s.onSecondaryContainer)]]), const SizedBox(height: 3), if (d.time.isNotEmpty) Text(d.time, style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant))]))]),
      const SizedBox(height: 14), Wrap(spacing: 7, runSpacing: 7, children: [_metaChip(context, Icons.tag_rounded, '主题 ${d.tid}'), if (d.isPaid) _metaChip(context, Icons.lock_outline_rounded, '付费主题'), if (_likeCount > 0) _metaChip(context, Icons.favorite_border_rounded, '$_likeCount 点赞')]),
    ]));
  }

  Widget _chip(String text, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)), child: Text(text, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)));
  Widget _metaChip(BuildContext context, IconData icon, String text) { final s = Theme.of(context).colorScheme; return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: s.surface.withValues(alpha: .72), borderRadius: BorderRadius.circular(10), border: Border.all(color: s.outlineVariant.withValues(alpha: .35))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: s.onSurfaceVariant), const SizedBox(width: 5), Text(text, style: TextStyle(fontSize: 11, color: s.onSurfaceVariant, fontWeight: FontWeight.w600))])); }

  Widget _quickActions(BuildContext context, ThreadDetail d) {
    final s = Theme.of(context).colorScheme;
    Widget item(IconData icon, String label, {bool active = false, int? count, required VoidCallback onTap}) => Expanded(child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20, color: active ? s.primary : s.onSurfaceVariant), const SizedBox(height: 4), Text(count != null && count > 0 ? '$label · $count' : label, style: TextStyle(fontSize: 11.5, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: active ? s.primary : s.onSurfaceVariant))])));
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: s.outlineVariant.withValues(alpha: .45)), boxShadow: [BoxShadow(color: s.shadow.withValues(alpha: .035), blurRadius: 14, offset: const Offset(0, 4))]), child: Row(children: [item(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, _liked ? '已点赞' : '点赞', active: _liked, count: _likeCount, onTap: () => _like(d)), item(_favorited ? Icons.star_rounded : Icons.star_border_rounded, _favorited ? '已收藏' : '收藏', active: _favorited, onTap: () => _favorite(d)), item(_rewarding ? Icons.hourglass_top_rounded : Icons.card_giftcard_outlined, '打赏', active: _rewarding, onTap: () => _reward(d)), item(Icons.chat_bubble_outline_rounded, '回复', onTap: () => _replyFocus.requestFocus())]));
  }

  Widget _sectionHeader(BuildContext context, String title, String subtitle, IconData icon) { final s = Theme.of(context).colorScheme; return Padding(padding: const EdgeInsets.fromLTRB(4, 7, 4, 10), child: Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: s.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: s.primary)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant))]))])); }
  Widget _webCard(BuildContext context, WebViewController controller, double height) { final s = Theme.of(context).colorScheme; return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.fromLTRB(11, 11, 11, 8), decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.outlineVariant.withValues(alpha: .45)), boxShadow: [BoxShadow(color: s.shadow.withValues(alpha: .025), blurRadius: 14, offset: const Offset(0, 4))]), child: SizedBox(height: height > 0 ? height : 260, child: WebViewWidget(controller: controller))); }

  Widget _paidNotice(BuildContext context, ThreadDetail d) { final s = Theme.of(context).colorScheme; return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(26), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [s.primaryContainer, s.surface]), borderRadius: BorderRadius.circular(24), border: Border.all(color: s.outlineVariant.withValues(alpha: .45))), child: Column(children: [Container(width: 68, height: 68, decoration: BoxDecoration(color: s.primary.withValues(alpha: .12), shape: BoxShape.circle), child: Icon(Icons.lock_rounded, size: 30, color: s.primary)), const SizedBox(height: 14), const Text('这是一个付费主题', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(d.price == null ? '购买后即可查看完整内容' : '支付 ${d.price} ${d.currency} 后查看完整内容', textAlign: TextAlign.center, style: TextStyle(color: s.onSurfaceVariant)), const SizedBox(height: 18), FilledButton.icon(onPressed: _buying ? null : _purchase, icon: _buying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shopping_bag_outlined), label: Text(_buying ? '购买中…' : '购买主题'))])); }

  Widget _commentsSection(BuildContext context, ThreadDetail d) { final s = Theme.of(context).colorScheme; return Container(margin: const EdgeInsets.only(top: 2, bottom: 10), decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: s.outlineVariant.withValues(alpha: .45))), child: Column(children: [InkWell(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), onTap: () => setState(() => _commentsExpanded = !_commentsExpanded), child: Padding(padding: const EdgeInsets.fromLTRB(16, 15, 12, 15), child: Row(children: [Container(width: 4, height: 30, decoration: BoxDecoration(color: s.secondary, borderRadius: BorderRadius.circular(4))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('评论 / 回复', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text('原生楼层 · 按楼层浏览', style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant))])), Container(width: 34, height: 34, decoration: BoxDecoration(color: s.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(_commentsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 21))])), if (_commentsExpanded) ...[Divider(height: 1, color: s.outlineVariant.withValues(alpha: .35)), NativeCommentList(html: d.commentsHtml)]])); }
  Widget _empty(BuildContext context, String text) { final s = Theme.of(context).colorScheme; return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(vertical: 44), decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.outlineVariant.withValues(alpha: .4))), child: Column(children: [Icon(Icons.article_outlined, size: 34, color: s.onSurfaceVariant), const SizedBox(height: 9), Text(text, style: TextStyle(color: s.onSurfaceVariant))])); }

  Widget _composer(BuildContext context) { final s = Theme.of(context).colorScheme; final d = _detail; if (d == null || d.isPaid) return const SizedBox.shrink(); return SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), decoration: BoxDecoration(color: s.surface, border: Border(top: BorderSide(color: s.outlineVariant.withValues(alpha: .45))), boxShadow: [BoxShadow(color: s.shadow.withValues(alpha: .045), blurRadius: 16, offset: const Offset(0, -4))]), child: !_loggedIn ? OutlinedButton.icon(onPressed: _login, icon: const Icon(Icons.login_rounded, size: 18), label: const Text('登录后参与讨论'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))) : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _replyCtrl, focusNode: _replyFocus, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _reply(), decoration: InputDecoration(hintText: '友善地说点什么…', isDense: true, filled: true, fillColor: s.surfaceContainerHighest.withValues(alpha: .72), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: s.primary.withValues(alpha: .45))), contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11)))), const SizedBox(width: 7), Container(width: 46, height: 46, decoration: BoxDecoration(color: s.primary, borderRadius: BorderRadius.circular(15)), child: IconButton(onPressed: _sending ? null : _reply, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded, color: Colors.white)))])));
  }
}
