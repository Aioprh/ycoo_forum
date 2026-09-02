import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../pages/native_profile_page.dart';
import '../services/auth_service.dart';
import '../services/comment_profile_resolver.dart';
import '../services/comment_reply_resolver.dart';
import 'native_post_content.dart';
import 'resolved_user_avatar.dart';

/// 原生评论列表。
///
/// 每个评论都会尝试读取 Discuz replyfloor。楼中楼中的每一条回复都
/// 使用自己的 PID，因此可以直接回复任意一条回复。
class NativeCommentList extends StatelessWidget {
  final String html;
  final void Function(int pid, String author)? onReply;
  final Future<void> Function(int pid, String author)? onReplySent;

  const NativeCommentList({
    super.key,
    required this.html,
    this.onReply,
    this.onReplySent,
  });

  List<_CommentFloor> _parse() {
    if (html.trim().isEmpty) return const [];
    final doc = parser.parseFragment(html);
    final result = <_CommentFloor>[];
    for (final card in doc.querySelectorAll('.post-card')) {
      final body = card.querySelector('.p-body');
      if (body == null) continue;
      final authorNode = card.querySelector('.p-author');
      final rawText = card.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final replyMatch = RegExp(r'回复\s*\((\d+)\)').firstMatch(rawText);
      result.add(_CommentFloor(
        pid: int.tryParse(card.attributes['data-pid'] ?? '') ?? 0,
        uid: _extractUid(card, authorNode),
        floor: _text(card.querySelector('.p-floor')),
        author: _text(authorNode),
        level: _text(card.querySelector('.p-level')),
        time: _text(card.querySelector('.p-time')),
        replyCount: int.tryParse(replyMatch?.group(1) ?? '0') ?? 0,
        bodyHtml: body.innerHtml,
      ));
    }
    return result;
  }

  static int _extractUid(dom.Element card, dom.Element? author) {
    const keys = [
      'data-uid', 'data-user-id', 'data-author-id', 'uid', 'userid',
      'user-id', 'author-id',
    ];
    for (final key in keys) {
      final uid = _firstInt(card.attributes[key] ?? author?.attributes[key]);
      if (uid != null && uid > 0) return uid;
    }
    final nodes = <dom.Element>[
      card,
      if (author != null) author,
      ...card.querySelectorAll('a[href], img[src], img[data-src]'),
    ];
    for (final node in nodes) {
      final raw = '${node.attributes['href'] ?? ''} '
          '${node.attributes['src'] ?? ''} '
          '${node.attributes['data-src'] ?? ''}';
      final match = RegExp(
        r'(?:[?&]|%3F|%26)uid(?:=|%3D)(\d+)',
        caseSensitive: false,
      ).firstMatch(raw);
      final uid = int.tryParse(match?.group(1) ?? '');
      if (uid != null && uid > 0) return uid;
    }
    return 0;
  }

  static int? _firstInt(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static String _text(dom.Element? e) =>
      e?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final comments = _parse();
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂无评论', style: TextStyle(color: Colors.grey))),
      );
    }
    final root = parser.parseFragment(html);
    final section = root.querySelector('.comments-section');
    final tid = int.tryParse(section?.attributes['data-tid'] ?? '') ?? 0;
    final fid = int.tryParse(section?.attributes['data-fid'] ?? '') ?? 0;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      itemCount: comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final comment = comments[index];
        return _CommentCard(
          comment: comment,
          index: index,
          tid: tid,
          fid: fid,
          onReply: () => _handleReply(context, tid, fid, index, comment),
          onProfile: () => _openProfile(context, comment),
        );
      },
    );
  }

  Future<void> _handleReply(BuildContext context, int tid, int fid, int index,
      _CommentFloor comment) async {
    var pid = comment.pid;
    if (pid <= 0 && tid > 0) {
      pid = await CommentReplyResolver.instance.resolvePid(
        tid: tid, commentIndex: index, author: comment.author, floor: comment.floor,
      );
    }
    await _replyByPid(context, tid, fid, pid, comment.author);
  }

  Future<void> _replyByPid(BuildContext context, int tid, int fid, int pid,
      String author) async {
    if (!context.mounted) return;
    if (pid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未取得评论楼层，请刷新帖子后重试')),
      );
      return;
    }
    if (onReply != null) {
      onReply!(pid, author);
      return;
    }
    await _replyDialog(context, tid, fid, pid, author);
  }

  Future<void> _openProfile(BuildContext context, _CommentFloor comment) async {
    var uid = comment.uid;
    if (uid <= 0 && comment.author.trim().isNotEmpty) {
      uid = await CommentProfileResolver.instance.resolveUid(comment.author) ?? 0;
    }
    if (!context.mounted) return;
    if (uid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到该用户资料，请稍后重试')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NativeProfilePage(uid: uid, username: comment.author),
    ));
  }

  Future<void> _replyDialog(BuildContext context, int tid, int fid, int pid,
      String author) async {
    if (tid <= 0 || fid <= 0 || pid <= 0) return;
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后回复')),
      );
      return;
    }
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(author.isEmpty ? '回复本楼' : '回复 $author'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText: '输入回复内容…', border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty || !context.mounted) return;
    final error = await AuthService.instance.reply(tid, fid, message, replyPid: pid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '已回复 $author')),
    );
    if (error == null && onReplySent != null) await onReplySent!(pid, author);
  }
}

class _CommentFloor {
  final int pid, uid, replyCount;
  final String floor, author, level, time, bodyHtml;
  const _CommentFloor({
    required this.pid, required this.uid, required this.replyCount,
    required this.floor, required this.author, required this.level,
    required this.time, required this.bodyHtml,
  });
}

class _CommentCard extends StatefulWidget {
  final _CommentFloor comment;
  final int index, tid, fid;
  final VoidCallback onReply, onProfile;
  const _CommentCard({
    required this.comment, required this.index, required this.tid, required this.fid,
    required this.onReply, required this.onProfile,
  });
  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _loadingReplies = false, _repliesExpanded = false;
  String _replyHtml = '';
  String? _replyError;
  int _pid = 0;

  @override
  void initState() {
    super.initState();
    _pid = widget.comment.pid;
    if (widget.tid > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadReplies());
    }
  }

  Future<void> _loadReplies() async {
    if (_loadingReplies || widget.tid <= 0) return;
    setState(() { _loadingReplies = true; _replyError = null; });
    try {
      if (_pid <= 0) {
        _pid = await CommentReplyResolver.instance.resolvePid(
          tid: widget.tid, commentIndex: widget.index,
          author: widget.comment.author, floor: widget.comment.floor,
        );
      }
      if (_pid <= 0) throw Exception('未取得评论楼层');
      _replyHtml = await CommentReplyResolver.instance.fetchReplies(
        tid: widget.tid, pid: _pid,
      );
      if (!mounted) return;
      final replies = _parseReplies();
      setState(() {
        _loadingReplies = false;
        _repliesExpanded = replies.isNotEmpty;
        if (replies.isEmpty && widget.comment.replyCount > 0) {
          _replyError = '暂时没有取得楼中楼内容';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingReplies = false;
        _replyError = widget.comment.replyCount > 0 ? '$e' : null;
      });
    }
  }

  void _toggleReplies() {
    if (_loadingReplies) return;
    if (_replyHtml.trim().isEmpty) { _loadReplies(); return; }
    setState(() => _repliesExpanded = !_repliesExpanded);
  }

  List<_FloorReply> _parseReplies() {
    if (_replyHtml.trim().isEmpty) return const [];
    var doc = parser.parseFragment(_replyHtml);
    var nodes = <dom.Element>[];
    const selectors = [
      '.replyfloor_content_ul > .replyfloor_content_li',
      '.replyfloor_content_ul > li', '.replyfloor_content_li',
      '.replyfloor_content li', 'li.replyfloor_li', '.replyfloor_box li',
      '.replyfloor_reply', '.replyfloor_item',
    ];
    for (final selector in selectors) {
      for (final node in doc.querySelectorAll(selector)) {
        if (!nodes.contains(node)) nodes.add(node);
      }
    }
    if (nodes.isEmpty) {
      for (final root in doc.querySelectorAll(
          '.replyfloor_content_ul, .replyfloor_content, .replyfloor_box, .replyfloor')) {
        for (final child in root.children) {
          if (child.text.trim().isNotEmpty && !nodes.contains(child)) nodes.add(child);
        }
      }
    }
    if (nodes.isEmpty) {
      final decoded = doc.text?.trim() ?? '';
      if (decoded.contains('replyfloor') || decoded.contains('回复 举报')) {
        doc = parser.parseFragment(decoded);
        for (final selector in selectors) {
          for (final node in doc.querySelectorAll(selector)) {
            if (!nodes.contains(node)) nodes.add(node);
          }
        }
      }
    }
    if (nodes.isEmpty) return const [];
    return nodes.map((node) {
      final pid = _extractReplyPid(node);
      // 父楼 Discuz postpid: Comiis replyfloor_editor / replyfloor_report
      // 的第一个参数就是挂载该 replyfloor_box 的父楼 postpid。
      // fallback: replyfloor_box_XXX / replyfloor_content_XXX 的 id 后缀。
      int parentPid = 0;
      final all = <dom.Element>[node, ...node.querySelectorAll('*')];
      parentLoop:
      for (final e in all) {
        for (final v in e.attributes.values) {
          final m = RegExp(r'''replyfloor_(?:editor|report)\s*\(\s*["']?(\d+)''', caseSensitive: false).firstMatch(v) ??
              RegExp(r'replyfloor_(?:box|bd|content)_(\d+)', caseSensitive: false).firstMatch(v);
          final val = int.tryParse(m?.group(1) ?? '');
          if (val != null && val > 0) { parentPid = val; break parentLoop; }
        }
      }
      return _FloorReply(
        pid: pid,
        uid: NativeCommentList._extractUid(node, node.querySelector('a[href*="uid="]')),
        parentPid: parentPid,
        author: _firstText(node, const [
          '.replyfloor_content_user a', '.replyfloor_content_user',
          '.replyfloor_author', '.replyfloor_user', '.replyfloor_username',
          '.xw1', '.authi a', '.authi strong a', 'a[href*="uid="]',
        ]),
        time: _firstText(node, const [
          '.replyfloor_content_time', '.replyfloor_time',
          '.replyfloor_dateline', '.replyfloor_date', 'time', 'em',
        ]),
        bodyHtml: _extractReplyBody(node),
      );
    }).where((r) => r.author.isNotEmpty || r.bodyHtml.trim().isNotEmpty).toList();
  }

  static int _extractReplyPid(dom.Element node) {
    // Discuz replyfloor 的“回复”按钮通常把目标楼层放在 repquote 中。
    // 必须优先读取 repquote，否则同一个回复节点里同时存在父楼 PID 时，
    // 会错误地把父楼 PID 当成当前楼中楼 PID。
    final elements = <dom.Element>[node, ...node.querySelectorAll('*')];
    // Comiis 手机版模板的回复按钮常常是 onclick="replyfloor_reply('repquote=123')"，
    // 此时 repquote 前后没有 ?/& 分隔符，必须同时匹配裸格式与直接携带 PID 的形式。
    final pidPatterns = <RegExp>[
      // 带 query 前缀: &repquote=123 / ?repquote=123 / 编码形式
      RegExp(r'(?:[?&]|%3F|%26|&amp;)repquote(?:=|%3D)(\d+)', caseSensitive: false),
      // 裸 repquote=123 / repquote:"123" / repquote:123 (常见于 onclick 内)
      RegExp(r'''\brepquote\s*[:=]\s*["']?(\d+)''', caseSensitive: false),
      // replyfloor_reply('123') 直接携带 PID
      RegExp(r'''replyfloor_reply\s*\(\s*["']?(\d+)''', caseSensitive: false),
      // Comiis mobile: 楼中楼 li 的 id="replyfloor_content_li_<PID>"，id 后缀即该条回复真正的 PID
      RegExp(r'replyfloor_content_li_(\d+)', caseSensitive: false),
      // Comiis mobile: 回复按钮 onclick="replyfloor_editor('<postPid>', <PID>, ...)"，
      // 举报按钮 replyfloor_report('<postPid>', <PID>)，第二个整型参数即是楼中楼回复 PID
      RegExp(r'''replyfloor_(?:editor|report)\s*\(\s*["']?\d+["']?\s*,\s*["']?(\d+)''', caseSensitive: false),
    ];
    for (final element in elements) {
      for (final value in element.attributes.values) {
        for (final pattern in pidPatterns) {
          final match = pattern.firstMatch(value);
          final pid = int.tryParse(match?.group(1) ?? '');
          if (pid != null && pid > 0) return pid;
        }
      }
    }

    const keys = [
      'data-pid', 'data-post-id', 'data-reply-id', 'data-reppid',
      'pid', 'reppid', 'replypid', 'replyid', 'repquote', 'data-id',
    ];
    for (final key in keys) {
      final pid = int.tryParse(node.attributes[key] ?? '');
      if (pid != null && pid > 0) return pid;
    }

    for (final element in elements) {
      for (final value in element.attributes.values) {
        final direct = RegExp(
          r'(?:[?&]|%3F|%26|&amp;)(?:reppid|replypid|replyid|pid)(?:=|%3D)(\d+)',
          caseSensitive: false,
        ).firstMatch(value);
        final directPid = int.tryParse(direct?.group(1) ?? '');
        if (directPid != null && directPid > 0) return directPid;
        final named = RegExp(
          r'(?:reply(?:floor)?|post|pid)[_-]?(\d+)',
          caseSensitive: false,
        ).firstMatch(value);
        final namedPid = int.tryParse(named?.group(1) ?? '');
        if (namedPid != null && namedPid > 0) return namedPid;
      }
    }
    return 0;
  }

  static String _extractReplyBody(dom.Element node) {
    // 楼中楼正文: 优先取正文容器 .replyfloor_content_main, 它同时包住文字
    // (.replyfloor_content_text) 与该楼附带的图片 (.replyfloor_content_image)。
    // 若只取 .replyfloor_content_text, 会丢掉同级的图片容器, 导致楼中楼不显示图片。
    final body = node.querySelector(
      '.replyfloor_content_main, .replyfloor_msg, .replyfloor_message, '
      '.replyfloor_body, .replyfloor_text, .reply_content, '
      '.replyfloor_content_text',
    );
    if (body != null) {
      if (body.querySelector('img') != null || body.text.trim().isNotEmpty) return body.innerHtml;
    }
    final clone = dom.Element.html('<div>${node.innerHtml}</div>');
    for (final selector in [
      '.replyfloor_content_user', '.replyfloor_content_time', '.replyfloor_time',
      '.replyfloor_dateline', '.replyfloor_date', '.replyfloor_author',
      '.replyfloor_user', '.replyfloor_username', '.replyfloor_actions',
      '.replyfloor_tools', '.authi',
    ]) {
      for (final e in clone.querySelectorAll(selector).toList()) e.remove();
    }
    return clone.innerHtml;
  }

  static String _firstText(dom.Element node, List<String> selectors) {
    for (final selector in selectors) {
      final e = node.querySelector(selector);
      if (e != null && e.text.trim().isNotEmpty) return e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return '';
  }

  Future<void> _replyNested(_FloorReply reply) async {
    if (!mounted) return;
    if (reply.parentPid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未取得这条楼中楼所属楼层的编号，请刷新后重试')),
      );
      return;
    }
    await _showReplyDialog(reply.pid, reply.parentPid, reply.author);
  }

  Future<void> _showReplyDialog(int pid, int parentPid, String author) async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录后回复')));
      return;
    }
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(author.isEmpty ? '回复楼中楼' : '回复 $author'),
        content: TextField(
          controller: controller, autofocus: true, minLines: 2, maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: '输入回复内容…', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(dialogContext, value);
          }, child: const Text('发送')),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty || !mounted) return;
    final error = await AuthService.instance.reply(
      widget.tid, widget.fid, message,
      replyPid: pid, nestedParentPid: parentPid,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? '已回复 $author')));
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final colors = Theme.of(context).colorScheme;
    final replies = _parseReplies();
    final showReplyToggle = replies.isNotEmpty || comment.replyCount > 0 || _replyError != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ResolvedUserAvatar(uid: comment.uid, username: comment.author, radius: 18, onTap: widget.onProfile),
          const SizedBox(width: 9),
          Expanded(child: InkWell(onTap: widget.onProfile, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(comment.author.isEmpty ? '匿名用户' : comment.author,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                if (comment.level.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(7)),
                    child: Text(comment.level, style: TextStyle(fontSize: 9.5, color: colors.onSecondaryContainer))),
                ],
              ]),
              if (comment.time.isNotEmpty) Text(comment.time,
                  style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant)),
            ],
          ))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(9)),
            child: Text(comment.floor.isEmpty ? '${widget.index + 1}楼' : comment.floor,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant))),
        ]),
        const SizedBox(height: 11),
        Container(height: 1, color: colors.outlineVariant.withValues(alpha: .35)),
        const SizedBox(height: 10),
        NativePostContent(html: comment.bodyHtml),
        if (showReplyToggle) ...[
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: _toggleReplies,
            icon: _loadingReplies ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_repliesExpanded ? Icons.keyboard_arrow_up_rounded : Icons.forum_outlined, size: 17),
            label: Text(_loadingReplies ? '正在加载…' : (_repliesExpanded ? '收起' : '展开')),
          )),
          if (_replyError != null && !_loadingReplies)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('楼中楼：$_replyError', style: TextStyle(fontSize: 11, color: colors.error))),
          if (_repliesExpanded && replies.isNotEmpty)
            Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              decoration: BoxDecoration(color: colors.primaryContainer.withValues(alpha: .22), borderRadius: BorderRadius.circular(14)),
              child: Column(children: [for (final reply in replies) _FloorReplyTile(reply: reply, onReply: () => _replyNested(reply))])),
        ],
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: widget.onReply,
          icon: const Icon(Icons.reply_rounded, size: 17),
          label: const Text('回复本楼'),
        )),
      ]),
    );
  }
}

class _FloorReply {
  /// 该条楼中楼回复的 replyfloor 内部 PID (如 20568)。
  final int pid, uid;

  /// 挂载该 replyfloor 的父楼 Discuz 原生 postpid (如 2657801)。
  /// 构造 Discuz reply 的 repquote / reppid 参数必须用它，replyfloor 的内部 PID
  /// Discuz 根本不认识。
  final int parentPid;
  final String author, time, bodyHtml;
  const _FloorReply({
    required this.pid, required this.uid, required this.parentPid,
    required this.author, required this.time, required this.bodyHtml,
  });
}

class _FloorReplyTile extends StatelessWidget {
  final _FloorReply reply;
  final VoidCallback onReply;
  const _FloorReplyTile({required this.reply, required this.onReply});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final doc = parser.parseFragment(reply.bodyHtml);
    final images = doc.querySelectorAll('img').map((e) => e.outerHtml).toList();
    for (final img in doc.querySelectorAll('img').toList()) img.remove();
    final textHtml = doc.nodes.map((e) => e is dom.Element ? e.outerHtml : (e.text ?? '')).join();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: .3)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(reply.author.isEmpty ? '楼中楼回复' : reply.author,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          if (reply.time.isNotEmpty) Text(reply.time, style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        ]),
        if (textHtml.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          NativePostContent(html: textHtml),
        ],
        for (final image in images) NativePostContent(html: image),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: onReply,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: const Icon(Icons.reply_rounded, size: 15),
          label: const Text('回复'),
        )),
      ]),
    );
  }
}
