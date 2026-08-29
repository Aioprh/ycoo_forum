import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/thread_detail.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/thread_interaction_service.dart';
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
  int _likeCount = 0;
  bool _liked = false;
  bool _favorited = false;
  bool _interacting = false;

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
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await ApiService.instance.fetchThreadDetail(widget.tid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _likeCount = detail.likeCount;
        _liked = detail.likedByMe;
      });
      _bodyHeight = 0;
      _bodyController = _buildBodyController(detail.bodyHtml);
      if (_loggedIn) _loadInteractionState();
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
      setState(() {
        _likeCount = state.likeCount;
        _liked = state.likedByMe;
        _favorited = state.favorited;
      });
    } catch (_) {
      // 互动状态同步失败不阻塞正文展示。
    }
  }

  WebViewController _buildBodyController(String bodyHtml) {
    final safeHtml = bodyHtml.isEmpty ? '<div></div>' : bodyHtml;
    final doc = '''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<base href="https://www.ycoo.net/">
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: transparent; }
  body {
    padding: 6px 16px 18px;
    font-size: 16px;
    line-height: 1.82;
    color: #242833;
    word-wrap: break-word;
    overflow-wrap: anywhere;
    -webkit-font-smoothing: antialiased;
  }
  p { margin: 0 0 12px; }
  h1, h2, h3, h4 { line-height: 1.4; margin: 18px 0 10px; color: #171a21; }
  h1 { font-size: 23px; } h2 { font-size: 20px; } h3 { font-size: 18px; }
  a { color: #536dfe; text-decoration: none; }
  strong, b { color: #171a21; }
  img { max-width: 100% !important; height: auto !important; border-radius: 12px; display: block; margin: 12px auto; }
  video, iframe { max-width: 100% !important; border-radius: 12px; }
  pre, code { white-space: pre-wrap; word-break: break-word; }
  code { background: #f1f3f6; padding: 2px 5px; border-radius: 5px; font-size: .92em; }
  pre { background: #f4f5f7; padding: 12px 14px; border-radius: 10px; overflow: hidden; }
  blockquote { margin: 14px 0; padding: 9px 14px; border-left: 3px solid #8a9cff; background: #f5f6ff; color: #646b78; border-radius: 0 10px 10px 0; }
  ul, ol { padding-left: 24px; }
  li { margin: 5px 0; }
  hr { border: 0; border-top: 1px solid #e7e9ee; margin: 20px 0; }
  table { width: 100%; border-collapse: separate; border-spacing: 0; margin: 14px 0; overflow: hidden; border: 1px solid #e3e6ec; border-radius: 10px; }
  th, td { padding: 8px 10px; border-right: 1px solid #e3e6ec; border-bottom: 1px solid #e3e6ec; text-align: left; }
  th { background: #f5f6f8; font-weight: 650; }
  tr:last-child td { border-bottom: 0; }
  th:last-child, td:last-child { border-right: 0; }
  .post-card { background: #f7f8fa; border: 1px solid #eceef2; border-radius: 14px; padding: 13px 14px; margin: 12px 0; }
  .post-card:first-child { margin-top: 0; }
  .post-hd { display: flex; align-items: center; flex-wrap: wrap; gap: 6px; }
  .p-floor { color: #9299a7; font-size: 12px; }
  .p-author { font-weight: 650; color: #222630; font-size: 14px; }
  .p-level { color: #536dfe; font-size: 11px; background: #edf0ff; padding: 2px 7px; border-radius: 9px; }
  .p-time { color: #9aa0ab; font-size: 12px; margin-top: 4px; }
  .post-card .p-body { margin-top: 9px; font-size: 15px; line-height: 1.75; }
</style>
</head>
<body>$safeHtml</body>
</html>''';

    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _fitWebViewHeight()),
      )
      ..loadHtmlString(doc, baseUrl: 'https://www.ycoo.net/');
  }

  Future<void> _fitWebViewHeight() async {
    try {
      final raw = await _bodyController!
          .runJavaScriptReturningResult('document.documentElement.scrollHeight')
          .then((v) => v.toString());
      final h = double.tryParse(raw.replaceAll(RegExp(r'"'), '')) ?? 0;
      if (h > 0 && mounted && h != _bodyHeight) {
        setState(() => _bodyHeight = h + 8);
      }
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
            content: Text('确定购买这个付费主题吗？\n\n价格：$priceText\n\n点击“确定购买”后将使用当前论坛账号完成购买。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确定购买')),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _buying = true);
    final result = await ApiService.instance.purchaseThread(d.tid);
    if (!mounted) return;
    setState(() => _buying = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: false,
        scrolledUnderElevation: 1,
      ),
      body: _buildBody(context),
      bottomNavigationBar: _buildComposer(context),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final theme = Theme.of(context);
    final d = _detail;
    if (d == null) return const SizedBox.shrink();

    if (d.isPaid) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .45))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('付费主题', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(d.price == null ? '购买后查看完整内容' : '${d.price} ${d.currency}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _buying ? null : _openPurchase,
                icon: _buying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shopping_bag_outlined, size: 19),
                label: Text(_buying ? '购买中…' : '购买主题'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_loggedIn) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .45))),
          ),
          child: OutlinedButton.icon(
            onPressed: _openLogin,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('登录后参与讨论'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .45))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _replyCtrl,
                focusNode: _replyFocus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendReply(),
                decoration: InputDecoration(
                  hintText: '友善地说点什么…',
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: .5))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: theme.colorScheme.primary,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: '发送',
                onPressed: _sending ? null : _sendReply,
                icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _actions(BuildContext context, ThreadDetail d) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            _actionButton(
              context,
              icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              label: _liked ? '已点赞' : '点赞',
              count: _likeCount,
              active: _liked,
              onTap: () => _toggleLike(d),
            ),
            const SizedBox(width: 4),
            _actionButton(
              context,
              icon: _favorited ? Icons.star_rounded : Icons.star_border_rounded,
              label: _favorited ? '已收藏' : '收藏',
              active: _favorited,
              onTap: () => _toggleFavorite(d),
            ),
            const SizedBox(width: 4),
            _actionButton(
              context,
              icon: Icons.reply_rounded,
              label: '回复',
              onTap: () => _replyFocus.requestFocus(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    int? count,
    bool active = false,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: active ? scheme.primary.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: active ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? scheme.primary : scheme.onSurfaceVariant)),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 3),
                  Text('$count', style: TextStyle(fontSize: 12, color: active ? scheme.primary : scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLike(ThreadDetail d) async {
    if (!_loggedIn) {
      await _openLogin();
      if (!_loggedIn) return;
    }
    if (_interacting || _sending) return;
    if (d.firstPid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无法定位首楼，请刷新后重试')));
      return;
    }
    setState(() => _interacting = true);
    final err = await ThreadInteractionService.instance.toggleLike(tid: d.tid, pid: d.firstPid, like: !_liked);
    if (!mounted) return;
    setState(() => _interacting = false);
    if (err == null) {
      setState(() {
        _liked = !_liked;
        if (_liked) {
          _likeCount++;
        } else if (_likeCount > 0) {
          _likeCount--;
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _toggleFavorite(ThreadDetail d) async {
    if (!_loggedIn) {
      await _openLogin();
      if (!_loggedIn) return;
    }
    if (_interacting || _sending) return;
    setState(() => _interacting = true);
    final err = await ThreadInteractionService.instance.toggleFavorite(tid: d.tid, favorite: !_favorited);
    if (!mounted) return;
    setState(() => _interacting = false);
    if (err == null) {
      setState(() => _favorited = !_favorited);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 42, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              const Text('详情加载失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: const Text('重新加载')),
            ],
          ),
        ),
      );
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
          if (d.bodyHtml.isEmpty && d.isPaid)
            _paidNotice(context, d)
          else if (d.bodyHtml.isEmpty)
            _emptyBody(context)
          else
            _bodyCard(context),
        ],
      ),
    );
  }

  Widget _bodyCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SizedBox(
          height: _bodyHeight > 0 ? _bodyHeight : MediaQuery.of(context).size.height * .72,
          child: WebViewWidget(controller: _bodyController!),
        ),
      ),
    );
  }

  Widget _emptyBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        children: [
          Icon(Icons.article_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 10),
          Text('该主题暂时没有可显示的正文。', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _paidNotice(BuildContext context, ThreadDetail d) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.surface]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(Icons.lock_rounded, size: 30, color: scheme.primary),
          ),
          const SizedBox(height: 14),
          Text('这是一个付费主题', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(d.price == null ? '购买后即可查看完整内容' : '支付 ${d.price} ${d.currency} 后查看完整内容', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 17),
          FilledButton.icon(onPressed: _buying ? null : _openPurchase, icon: const Icon(Icons.shopping_bag_outlined), label: const Text('购买主题')),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, ThreadDetail d) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .025), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.boardName.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: d.fid == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BoardThreadListPage(filter: d.boardName, fid: d.fid))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.forum_outlined, size: 14, color: scheme.primary), const SizedBox(width: 5), Text(d.boardName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary))]),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(d.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 21, height: 1.3, fontWeight: FontWeight.w800, letterSpacing: -.2)),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: d.avatar.isNotEmpty ? NetworkImage(d.avatar) : null,
                child: d.avatar.isNotEmpty ? null : Icon(Icons.person_rounded, size: 22, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(d.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                        if (d.level.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(8)), child: Text(d.level, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer))),
                        ],
                      ],
                    ),
                    if (d.time.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(d.time, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (d.isPaid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.workspace_premium_outlined, size: 14, color: scheme.onTertiaryContainer), const SizedBox(width: 4), Text('付费', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer))]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}