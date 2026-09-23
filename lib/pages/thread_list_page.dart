import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/thread_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/favorite_service.dart';
import '../services/site_config.dart';
import '../services/site_fallback_service.dart';
import '../widgets/thread_list_view.dart';

/// 版块帖子列表页：带分页, 并展示网页端的「主题分类」筛选标签。
/// 顶部额外展示从移动版头解析来的版块卡片(头像/名称/统计/关注按钮)。
class BoardThreadListPage extends StatefulWidget {
  final int fid;
  final String filter;

  const BoardThreadListPage({super.key, required this.fid, required this.filter});

  @override
  State<BoardThreadListPage> createState() => _BoardThreadListPageState();
}

class _BoardThreadListPageState extends State<BoardThreadListPage> {
  List<ForumTypeTag> _types = const [];
  int _typeid = 0; // 0 表示「全部」
  FavoriteBoardInfo? _boardInfo;
  bool _loadingBoard = true;

  @override
  void initState() {
    super.initState();
    _loadTypes();
    _loadBoardInfo();
  }

  Future<void> _loadTypes() async {
    try {
      final tags = await ApiService.instance.fetchForumTypes(widget.fid);
      if (!mounted) return;
      setState(() => _types = tags);
    } catch (_) {
      // 无法解析分类时保持为空, 帖子流仍照常显示。
    }
  }

  Future<void> _loadBoardInfo() async {
    final info = await FavoriteBoardService.instance.fetchBoardInfo(widget.fid);
    if (!mounted) return;
    setState(() {
      _boardInfo = info;
      _loadingBoard = false;
    });
  }

  Future<void> _refreshBoardInfo() async {
    final info = await FavoriteBoardService.instance.fetchBoardInfo(widget.fid);
    if (!mounted) return;
    setState(() => _boardInfo = info);
  }

  Future<List<ThreadItem>> _load(int page) async {
    final url = ApiService.forumUrl(widget.fid, page, typeid: _typeid);
    try {
      final primary = await ApiService.instance.fetchThreads(url);
      if (primary.isNotEmpty) return primary;
    } catch (_) {
      // 站点模板变化或请求异常时继续使用兼容解析器。
    }
    return SiteFallbackService.instance.fetchThreads(url);
  }

  Future<void> _toggleFollow() async {
    final board = _boardInfo;
    if (board == null) return;
    final ok = await AuthService.instance.checkLoggedIn();
    if (!ok || !AuthService.instance.isLoggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录论坛再关注版块')),
      );
      return;
    }
    final prev = board.followed;
    setState(() => _boardInfo = _boardInfo?.copyWith(followed: !prev));
    final err = await FavoriteBoardService.instance.toggle(
      fid: widget.fid,
      follow: !prev,
    );
    if (!mounted) return;
    if (err != null) {
      // 失败回滚
      setState(() => _boardInfo = _boardInfo?.copyWith(followed: prev));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      // 成功后重新抓一下最新状态(关注数会+1/-1)
      await _refreshBoardInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _boardInfo;
    final loggedIn = AuthService.instance.isLoggedIn;
    return Scaffold(
      appBar: AppBar(
        title: Text(board?.name.isNotEmpty == true ? board!.name : widget.filter),
        actions: [
          if (board != null && loggedIn)
            IconButton(
              tooltip: board.followed ? '取消关注' : '关注版块',
              onPressed: _toggleFollow,
              icon: Icon(
                board.followed
                    ? Icons.group_add_rounded
                    : Icons.person_add_alt_1_outlined,
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _boardCard(context),
            if (_types.isNotEmpty) _typeBar(context),
            Expanded(
              child: ThreadListView(
                key: ValueKey<int>(_typeid),
                paginate: true,
                loader: _load,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardCard(BuildContext context) {
    if (_loadingBoard) {
      return const SizedBox(
        height: 140,
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final board = _boardInfo;
    if (board == null) return const SizedBox.shrink();

    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.primaryContainer.withValues(alpha: .55), c.surface],
        ),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: c.primary.withValues(alpha: .12),
            backgroundImage: board.icon.isNotEmpty
                ? NetworkImage(board.icon.startsWith('http') ? board.icon : '${SiteConfig.base}${board.icon}')
                : null,
            onBackgroundImageError: (_, __) {},
            child: board.icon.isEmpty
                ? Icon(Icons.forum_rounded, color: c.primary, size: 26)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  board.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _stats(board),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _followButton(context, board),
        ],
      ),
    );
  }

  String _stats(FavoriteBoardInfo b) {
    final parts = <String>[];
    if (b.today.isNotEmpty) parts.add('今日 $b.today');
    if (b.threads.isNotEmpty) parts.add('主题 $b.threads');
    if (b.followers.isNotEmpty) parts.add('${b.followers}人已关注');
    return parts.isEmpty ? '版块 ${b.fid}' : parts.join(' · ');
  }

  Widget _followButton(BuildContext context, FavoriteBoardInfo board) {
    final c = Theme.of(context).colorScheme;
    final loggedIn = AuthService.instance.isLoggedIn;
    return Material(
      color: board.followed ? c.primaryContainer : c.primary,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: loggedIn ? _toggleFollow : () async {
          final ok = await AuthService.instance.checkLoggedIn();
          if (!ok || !AuthService.instance.isLoggedIn || !context.mounted) return;
          await _toggleFollow();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                board.followed ? Icons.check_rounded : Icons.add_rounded,
                size: 17,
                color: board.followed ? c.onPrimaryContainer : c.onPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                board.followed ? '已关注' : '关注',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: board.followed ? c.onPrimaryContainer : c.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 分类筛选栏: 横向胶囊标签布局。
  Widget _typeBar(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        itemCount: _types.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _tagChip(context, 0, '全部');
          }
          final tag = _types[index - 1];
          return _tagChip(context, tag.typeid, tag.name);
        },
      ),
    );
  }

  Widget _tagChip(BuildContext context, int typeid, String name) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = typeid == _typeid;

    return Semantics(
      button: true,
      selected: selected,
      label: '主题分类$name',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            if (typeid == _typeid) return;
            setState(() => _typeid = typeid);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? scheme.primaryContainer : scheme.outlineVariant,
                width: selected ? 1 : 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
