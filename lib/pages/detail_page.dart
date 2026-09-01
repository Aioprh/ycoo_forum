import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/thread_detail.dart';
import '../services/site_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/attachment_download_service.dart';
import '../services/thread_interaction_service.dart';
import '../widgets/native_comment_list.dart';
import '../widgets/resolved_user_avatar.dart';
import '../services/comment_profile_resolver.dart';
import 'native_profile_page.dart';
import '../widgets/native_post_content.dart';
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
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _loading = true, _sending = false, _buying = false, _rewarding = false;
  bool _loggedIn = false,
      _favorited = false,
      _liked = false,
      _interacting = false;
  bool _commentsExpanded = true;
  int _commentPage = 1;
  bool _commentChanging = false;
  String? _error;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await AuthService.instance.init();
    await AuthService.instance.checkLoggedIn();
    if (mounted) setState(() => _loggedIn = AuthService.instance.isLoggedIn);
    await _fetch();
  }

  Future<void> _fetch() async {
    final hadDetail = _detail != null;
    if (mounted)
      setState(() {
        _loading = !hadDetail;
        _error = null;
      });
    try {
      final d = await ApiService.instance.fetchThreadDetail(widget.tid, page: _commentPage);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _likeCount = d.likeCount;
        _liked = d.likedByMe;
      });
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
      final state = await ThreadInteractionService.instance.fetchState(
        detail: d,
      );
      if (!mounted) return;
      setState(() {
        _likeCount = state.likeCount;
        _liked = state.likedByMe;
        _favorited = state.favorited;
      });
    } catch (_) {}
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _login() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (ok == true && mounted) {
      await AuthService.instance.init();
      await AuthService.instance.checkLoggedIn();
      if (!mounted) return;
      setState(() => _loggedIn = AuthService.instance.isLoggedIn);
      await _fetch();
    }
  }

  Future<void> _reply() async {
    final d = _detail, text = _replyCtrl.text.trim();
    if (d == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await AuthService.instance.reply(d.tid, d.fid, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) {
      _replyCtrl.clear();
      _replyFocus.unfocus();
      _snack('回帖成功');
      await _fetch();
    } else
      _snack(error);
  }

  Future<void> _like(ThreadDetail d) async {
    if (!_loggedIn) {
      await _login();
      if (!_loggedIn) return;
    }
    if (_interacting || d.firstPid <= 0) return;
    setState(() => _interacting = true);
    final error = await ThreadInteractionService.instance.toggleLike(
      tid: d.tid,
      pid: d.firstPid,
      like: !_liked,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _interacting = false);
      _snack(error);
      return;
    }
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
      if (_likeCount < 0) _likeCount = 0;
      _interacting = false;
    });
  }

  Future<void> _favorite(ThreadDetail d) async {
    if (!_loggedIn) {
      await _login();
      if (!_loggedIn) return;
    }
    if (_interacting) return;
    setState(() => _interacting = true);
    final error = await ThreadInteractionService.instance.toggleFavorite(
      tid: d.tid,
      favorite: !_favorited,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _interacting = false);
      _snack(error);
      return;
    }
    setState(() {
      _favorited = !_favorited;
      _interacting = false;
    });
  }

  Future<void> _reward(ThreadDetail d) async {
    if (!_loggedIn) {
      await _login();
      if (!_loggedIn) return;
    }
    if (_rewarding || d.firstPid <= 0) return;
    final amountCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    var notify = true;
    final confirm = await showDialog<({int amount, String reason, bool notify})>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('打赏作者'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '星币数量',
                    helperText: '每楼可打赏 1~3 星币',
                    suffixText: '星币',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: '鼓励语（可选）',
                    hintText: '写几句鼓励的话吧',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: notify,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('通知作者'),
                  onChanged: (v) => setDialog(() => notify = v ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(amountCtrl.text.trim()) ?? 0;
                if (v <= 0) return;
                Navigator.pop(c, (amount: v, reason: reasonCtrl.text.trim(), notify: notify));
              },
              child: const Text('确认打赏'),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    reasonCtrl.dispose();
    if (confirm == null || !mounted) return;
    setState(() => _rewarding = true);
    final result = await ThreadInteractionService.instance.reward(
      tid: d.tid,
      pid: d.firstPid,
      amount: confirm.amount,
      reason: confirm.reason,
      notifyAuthor: confirm.notify,
    );
    if (!mounted) return;
    setState(() => _rewarding = false);
    _snack(result ?? '打赏成功');
  }

  Future<void> _purchase() async {
    final d = _detail;
    if (d == null || _buying) return;
    if (!_loggedIn) {
      await _login();
      if (!_loggedIn) return;
    }
    final price = d.price == null ? '以论坛页面为准' : '${d.price} ${d.currency}';
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('购买主题'),
            content: Text('确定购买这个付费主题吗？\n\n价格：$price'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('确定购买'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => _buying = true);
    final result = await ApiService.instance.purchaseThread(d.tid);
    if (!mounted) return;
    setState(() => _buying = false);
    _snack(result.message);
    if (result.success) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        titleSpacing: 8,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        backgroundColor: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _buildBody(context),
      bottomNavigationBar: _composer(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _detail == null) return _errorView(context);
    final d = _detail!;
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        children: [
          _hero(context, d),
          _quickActions(context, d),
          _sectionHeader(context, '正文', '楼主发布的主题内容', Icons.article_rounded),
          d.isPaid
              ? _paidNotice(context, d)
              : (d.bodyHtml.trim().isEmpty
                    ? _empty(context, '暂无正文内容')
                    : _nativeBodyCard(context, d.bodyHtml)),
          if (d.commentsHtml.trim().isNotEmpty) _commentsSection(context, d),
        ],
      ),
    );
  }

  Widget _nativeBodyCard(BuildContext context, String html) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '长按正文任意文字即可自由选择复制',
                style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
              ),
              const Spacer(),
              _copyAllButton(context, html),
            ],
          ),
          const SizedBox(height: 8),
          NativePostContent(html: html, onLinkTap: _handlePostLink),
        ],
      ),
    );
  }

  Widget _copyAllButton(BuildContext context, String html) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12.5),
      ),
      onPressed: () => _copyBodyAll(html),
      icon: const Icon(Icons.copy_all_rounded, size: 16),
      label: const Text('复制全文'),
    );
  }

  Future<void> _copyBodyAll(String html) async {
    final clean = (html_parser.parse(html).body?.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: clean));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正文已复制到剪贴板')));
  }

  Future<void> _handlePostLink(String url) async {
    if (url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      _snack('链接格式无效');
      return;
    }
    if (AttachmentDownloadService.instance.isAttachmentUrl(uri.toString())) {
      if (!_loggedIn) {
        if (mounted) await _login();
        return;
      }
      try {
        final started = await AttachmentDownloadService.instance.download(
          url: uri.toString(),
          cookie: AuthService.instance.authCookie,
          referer: SiteConfig.base,
        );
        if (mounted) _snack(started ? '已开始下载附件' : '当前平台暂不支持原生附件下载');
      } catch (e) {
        if (mounted) _snack('附件下载失败：$e');
      }
      return;
    }
    _snack('链接：${uri.toString()}');
  }

  Widget _errorView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: c.onSurfaceVariant),
            const SizedBox(height: 14),
            const Text(
              '详情加载失败',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 7),
            Text('网络或服务器暂时不可用', style: TextStyle(color: c.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAuthorProfile(BuildContext context, String author) async {
    final name = author.trim();
    if (name.isEmpty) return;
    final uid = await CommentProfileResolver.instance.resolveUid(name);
    if (!context.mounted) return;
    if (uid == null || uid <= 0) {
      _snack('未找到该用户资料，请稍后重试');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NativeProfilePage(uid: uid, username: name)),
    );
  }

  Widget _hero(BuildContext context, ThreadDetail d) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.primaryContainer.withValues(alpha: .72), c.surface],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.boardName.isNotEmpty)
            GestureDetector(
              onTap: d.fid == 0
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BoardThreadListPage(
                          filter: d.boardName,
                          fid: d.fid,
                        ),
                      ),
                    ),
              child: _tag(context, Icons.forum_rounded, d.boardName),
            ),
          const SizedBox(height: 14),
          Text(
            d.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 23,
              height: 1.28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ResolvedUserAvatar(
                uid: 0,
                username: d.author,
                radius: 22,
                onTap: () => _openAuthorProfile(context, d.author),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            d.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (d.level.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          _chip(
                            d.level,
                            c.secondaryContainer,
                            c.onSecondaryContainer,
                          ),
                        ],
                      ],
                    ),
                    if (d.time.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        d.time,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _metaChip(context, Icons.tag_rounded, '主题 ${d.tid}'),
              if (d.isPaid)
                _metaChip(context, Icons.lock_outline_rounded, '付费主题'),
              if (_likeCount > 0)
                _metaChip(
                  context,
                  Icons.favorite_border_rounded,
                  '$_likeCount 点赞',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, IconData icon, String text) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.primary,
            ),
          ),
          const SizedBox(width: 3),
          Icon(Icons.chevron_right_rounded, size: 15, color: c.primary),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
    ),
  );
  Widget _metaChip(BuildContext context, IconData icon, String text) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: c.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context, ThreadDetail d) {
    final c = Theme.of(context).colorScheme;
    Widget item(
      IconData icon,
      String label, {
      bool active = false,
      int? count,
      required VoidCallback onTap,
    }) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? c.primary : c.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                count != null && count > 0 ? '$label · $count' : label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? c.primary : c.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          item(
            _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            _liked ? '已点赞' : '点赞',
            active: _liked,
            count: _likeCount,
            onTap: () => _like(d),
          ),
          item(
            _favorited ? Icons.star_rounded : Icons.star_border_rounded,
            _favorited ? '已收藏' : '收藏',
            active: _favorited,
            onTap: () => _favorite(d),
          ),
          item(
            _rewarding
                ? Icons.hourglass_top_rounded
                : Icons.card_giftcard_outlined,
            '打赏',
            active: _rewarding,
            onTap: () => _reward(d),
          ),
          item(
            Icons.chat_bubble_outline_rounded,
            '回复',
            onTap: () => _replyFocus.requestFocus(),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: c.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paidNotice(BuildContext context, ThreadDetail d) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.primaryContainer, c.surface]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_rounded, size: 34, color: c.primary),
          const SizedBox(height: 14),
          const Text(
            '这是一个付费主题',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            d.price == null
                ? '购买后即可查看完整内容'
                : '支付 ${d.price} ${d.currency} 后查看完整内容',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _buying ? null : _purchase,
            icon: _buying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.shopping_bag_outlined),
            label: Text(_buying ? '购买中…' : '购买主题'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCommentPage(int page) async {
    final d = _detail;
    if (d == null || _commentChanging) return;
    final total = d.commentTotalPages > 0 ? d.commentTotalPages : 1;
    if (page < 1 || page > total) return;
    if (page == _commentPage) return;
    setState(() => _commentChanging = true);
    try {
      final nd = await ApiService.instance.fetchThreadDetail(widget.tid, page: page);
      if (mounted) {
        setState(() {
          _detail = nd;
          _commentPage = page;
          _likeCount = nd.likeCount;
          _liked = nd.likedByMe;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('评论切换失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _commentChanging = false);
    }
  }

  Widget _commentsSection(BuildContext context, ThreadDetail d) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _commentsExpanded = !_commentsExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '评论 / 回复',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    _commentsExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (_commentsExpanded) ...[
            Divider(height: 1, color: c.outlineVariant.withValues(alpha: .35)),
            NativeCommentList(html: d.commentsHtml),
            _commentPager(context, d),
          ],
        ],
      ),
    );
  }

  Widget _commentPager(BuildContext context, ThreadDetail d) {
    final total = d.commentTotalPages > 0 ? d.commentTotalPages : 1;
    if (total <= 1) return const SizedBox.shrink();
    final cur = (_commentPage < 1 || _commentPage > total) ? 1 : _commentPage;
    final pages = <int>[];
    // 简单页码集: 始终包含 1..total (评论页通常不多)
    for (var p = 1; p <= total; p++) {
      pages.add(p);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _commentChanging || cur <= 1 ? null : () => _changeCommentPage(cur - 1),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: '上一页',
          ),
          Flexible(
            child: DropdownButton<int>(
              value: cur,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: pages.map((p) => DropdownMenuItem<int>(value: p, child: Text('第 $p 页'))).toList(),
              onChanged: _commentChanging ? null : (v) { if (v != null) _changeCommentPage(v); },
            ),
          ),
          IconButton(
            onPressed: _commentChanging || cur >= total ? null : () => _changeCommentPage(cur + 1),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: '下一页',
          ),
          if (_commentChanging) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String text) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 44),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .4)),
      ),
      child: Column(
        children: [
          Icon(Icons.article_outlined, size: 34, color: c.onSurfaceVariant),
          const SizedBox(height: 9),
          Text(text, style: TextStyle(color: c.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final d = _detail;
    if (d == null || d.isPaid) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(
            top: BorderSide(color: c.outlineVariant.withValues(alpha: .45)),
          ),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: .045),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: !_loggedIn
            ? OutlinedButton.icon(
                onPressed: _login,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('登录后参与讨论'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      focusNode: _replyFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _reply(),
                      decoration: InputDecoration(
                        hintText: '友善地说点什么…',
                        isDense: true,
                        filled: true,
                        fillColor: c.surfaceContainerHighest.withValues(
                          alpha: .72,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: FilledButton(
                      onPressed: _sending ? null : _reply,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
