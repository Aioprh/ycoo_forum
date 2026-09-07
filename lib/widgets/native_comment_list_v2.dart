import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../pages/native_profile_page.dart';
import '../services/auth_service.dart';
import '../services/comment_profile_resolver.dart';
import '../services/comment_reply_resolver.dart';
import 'native_post_content.dart';
import 'resolved_user_avatar.dart';

/// 更紧凑的原生评论列表。
///
/// 设计目标：评论优先、操作其次；减少无意义留白；楼中楼按需加载，
/// 避免打开评论区时一次性为每一楼发起网络请求。
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
      final pid = int.tryParse(card.attributes['data-pid'] ?? '') ?? 0;
      final author = _text(authorNode);
      result.add(_CommentFloor(
        pid: pid,
        uid: _extractUid(card, authorNode),
        floor: _text(card.querySelector('.p-floor')),
        author: author,
        level: _text(card.querySelector('.p-level')),
        time: _text(card.querySelector('.p-time')),
        replyCount: int.tryParse(replyMatch?.group(1) ?? '0') ?? 0,
        hasReplies: card.attributes['data-replies'] == '1',
        bodyHtml: _compactHtml(body.innerHtml),
      ));
    }
    return result;
  }

  static String _compactHtml(String raw) {
    if (raw.trim().isEmpty) return '';
    final doc = parser.parseFragment(raw);
    final elements = doc.querySelectorAll('*').toList().reversed;
    for (final e in elements) {
      final tag = (e.localName ?? '').toLowerCase();
      if (tag == 'img' || tag == 'br') continue;
      if (e.text.trim().isEmpty && e.querySelector('img') == null) e.remove();
    }
    return doc.nodes
        .map((n) => n is dom.Element ? n.outerHtml : (n.text ?? ''))
        .join()
        .trim();
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Center(
          child: Text('暂无评论', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    final root = parser.parseFragment(html);
    final section = root.querySelector('.comments-section');
    final tid = int.tryParse(section?.attributes['data-tid'] ?? '') ?? 0;
    final fid = int.tryParse(section?.attributes['data-fid'] ?? '') ?? 0;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final comment = comments[index];
        return _CommentCard(
          key: ValueKey('comment-${comment.pid}-$index'),
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

  Future<void> _handleReply(BuildContext context, int tid, int fid, int index, _CommentFloor comment) async {
    var pid = comment.pid;
    if (pid <= 0 && tid > 0) {
      pid = await CommentReplyResolver.instance.resolvePid(
        tid: tid, commentIndex: index, author: comment.author, floor: comment.floor,
      );
    }
    await _replyByPid(context, tid, fid, pid, comment.author);
  }

  Future<void> _replyByPid(BuildContext context, int tid, int fid, int pid, String author) async {
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NativeProfilePage(uid: uid, username: comment.author)),
    );
  }

  Future<void> _replyDialog(BuildContext context, int tid, int fid, int pid, String author) async {
    if (tid <= 0 || fid <= 0 || pid <= 0) return;
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录后回复')));
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
          decoration: const InputDecoration(hintText: '输入回复内容…', border: OutlineInputBorder()),
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
    final error = await AuthService.instance.replyFloor(tid, pid, message);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? '已回复 $author')));
    if (error == null && onReplySent != null) await onReplySent!(pid, author);
  }
}

class _CommentFloor {
  final int pid, uid, replyCount;
  final bool hasReplies;
  final String floor, author, level, time, bodyHtml;
  const _CommentFloor({
    required this.pid,
    required this.uid,
    required this.replyCount,
    required this.hasReplies,
    required this.floor,
    required this.author,
    required this.level,
    required this.time,
    required this.bodyHtml,
  });
}

class _CommentCard extends StatefulWidget {
  final _CommentFloor comment;
  final int index, tid, fid;
  final Future<void> Function() onReply;
  final VoidCallback onProfile;

  const _CommentCard({
    super.key,
    required this.comment,
    required this.index,
    required this.tid,
    required this.fid,
    required this.onReply,
    required this.onProfile,
  });

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _loadingReplies = false;
  bool _repliesExpanded = false;
  bool? _hasReplies;
  String _replyHtml = '';
  String? _replyError;
  int _pid = 0;

  @override
  void initState() {
    super.initState();
    _pid = widget.comment.pid;
    // 不再为每条评论预加载楼中楼；点击时再请求，明显降低首屏网络与布局压力。
  }

  @override
  void didUpdateWidget(covariant _CommentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.pid != widget.comment.pid) {
      _pid = widget.comment.pid;
      _replyHtml = '';
      _replyError = null;
      _loadingReplies = false;
      _repliesExpanded = false;
      _hasReplies = null;
    }
  }

  bool get _replyCandidate => widget.comment.replyCount > 0 || widget.comment.hasReplies;

  Future<void> _loadReplies({bool force = false}) async {
    if (_loadingReplies || widget.tid <= 0) return;
    setState(() {
      _loadingReplies = true;
      _replyError = null;
    });
    try {
      if (_pid <= 0) {
        _pid = await CommentReplyResolver.instance.resolvePid(
          tid: widget.tid,
          commentIndex: widget.index,
          author: widget.comment.author,
          floor: widget.comment.floor,
        );
      }
      if (_pid <= 0) {
        if (!mounted) return;
        setState(() {
          _loadingReplies = false;
          _hasReplies = false;
          _repliesExpanded = false;
        });
        return;
      }
      _replyHtml = await CommentReplyResolver.instance.fetchReplies(tid: widget.tid, pid: _pid);
      final replies = _parseReplies();
      if (!mounted) return;
      setState(() {
        _loadingReplies = false;
        _hasReplies = replies.isNotEmpty;
        _replyError = null;
        _repliesExpanded = replies.isNotEmpty && (force || widget.comment.hasReplies);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingReplies = false;
        _repliesExpanded = false;
        _replyError = '$e';
      });
    }
  }

  Future<void> _toggleReplies() async {
    if (_loadingReplies) return;
    if (_repliesExpanded) {
      setState(() => _repliesExpanded = false);
      return;
    }
    if (_hasReplies == null) await _loadReplies(force: true);
    if (!mounted) return;
    if (_hasReplies != true) {
      if (_replyError != null) {
        setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该楼层暂时没有楼中楼回复')),
        );
      }
      return;
    }
    setState(() {
      _repliesExpanded = true;
      _replyError = null;
    });
  }

  List<_FloorReply> _parseReplies() {
    if (_replyHtml.trim().isEmpty) return const [];
    var doc = parser.parseFragment(_replyHtml);
    final nodes = <dom.Element>[];
    const selectors = [
      '.replyfloor_content_ul > .replyfloor_content_li',
      '.replyfloor_content_ul > li',
      '.replyfloor_content_li',
      '.replyfloor_content li',
      'li.replyfloor_li',
      '.replyfloor_box li',
      '.replyfloor_reply',
      '.replyfloor_item',
    ];

    bool isReplyNode(dom.Element n) {
      final cls = (n.attributes['class'] ?? '').toLowerCase();
      final id = (n.attributes['id'] ?? '').toLowerCase();
      return cls.contains('replyfloor_content_li') ||
          id.contains('replyfloor_content_li') ||
          cls.contains('replyfloor_li') ||
          id.startsWith('replyfloor_content_li_') ||
          cls == 'replyfloor_reply' ||
          cls == 'replyfloor_item';
    }

    for (final selector in selectors) {
      for (final node in doc.querySelectorAll(selector)) {
        if (isReplyNode(node) && !nodes.contains(node)) nodes.add(node);
      }
    }
    if (nodes.isEmpty) {
      for (final root in doc.querySelectorAll('.replyfloor_content_ul, .replyfloor_content, .replyfloor_box, .replyfloor')) {
        for (final child in root.children) {
          if (!isReplyNode(child)) continue;
          final hasBody = child.text.trim().isNotEmpty || child.querySelector('img') != null;
          if (hasBody && !nodes.contains(child)) nodes.add(child);
        }
      }
    }
    if (nodes.isEmpty) {
      final decoded = doc.text.trim();
      if (decoded.contains('replyfloor')) {
        doc = parser.parseFragment(decoded);
        for (final selector in selectors) {
          for (final node in doc.querySelectorAll(selector)) {
            if (isReplyNode(node) && !nodes.contains(node)) nodes.add(node);
          }
        }
      }
    }
    if (nodes.isEmpty) return const [];

    return nodes
        .map((node) {
          final pid = _extractReplyPid(node);
          final all = <dom.Element>[node, ...node.querySelectorAll('*')];
          var parentPid = 0;
          parentLoop:
          for (final e in all) {
            for (final value in e.attributes.values) {
              final match = RegExp(
                    r'''replyfloor_(?:editor|report)\s*\(\s*["']?(\d+)''',
                    caseSensitive: false,
                  ).firstMatch(value) ??
                  RegExp(r'replyfloor_(?:box|bd|content)_(\d+)', caseSensitive: false).firstMatch(value);
              final valuePid = int.tryParse(match?.group(1) ?? '');
              if (valuePid != null && valuePid > 0) {
                parentPid = valuePid;
                break parentLoop;
              }
            }
          }
          return _FloorReply(
            pid: pid,
            uid: NativeCommentList._extractUid(node, node.querySelector('a[href*="uid="]')),
            parentPid: parentPid,
            author: _firstText(node, const [
              '.replyfloor_content_user a',
              '.replyfloor_content_user',
              '.replyfloor_author',
              '.replyfloor_user',
              '.replyfloor_username',
              '.xw1',
              '.authi a',
              'a[href*="uid="]',
            ]),
            time: _firstText(node, const [
              '.replyfloor_content_time',
              '.replyfloor_time',
              '.replyfloor_dateline',
              '.replyfloor_date',
              'time',
              'em',
            ]),
            bodyHtml: _extractReplyBody(node),
          );
        })
        .where((r) => r.author.isNotEmpty || r.bodyHtml.trim().isNotEmpty)
        .toList();
  }

  static int _extractReplyPid(dom.Element node) {
    final elements = <dom.Element>[node, ...node.querySelectorAll('*')];
    final patterns = <RegExp>[
      RegExp(r'(?:[?&]|%3F|%26|&amp;)repquote(?:=|%3D)(\d+)', caseSensitive: false),
      RegExp(r'''\brepquote\s*[:=]\s*["']?(\d+)''', caseSensitive: false),
      RegExp(r'''replyfloor_reply\s*\(\s*["']?(\d+)''', caseSensitive: false),
      RegExp(r'replyfloor_content_li_(\d+)', caseSensitive: false),
      RegExp(r'''replyfloor_(?:editor|report)\s*\(\s*["']?\d+["']?\s*,\s*["']?(\d+)''', caseSensitive: false),
    ];
    for (final element in elements) {
      for (final value in element.attributes.values) {
        for (final pattern in patterns) {
          final pid = int.tryParse(pattern.firstMatch(value)?.group(1) ?? '');
          if (pid != null && pid > 0) return pid;
        }
      }
    }
    const keys = ['data-pid', 'data-post-id', 'data-reply-id', 'data-reppid', 'pid', 'reppid', 'replypid', 'replyid', 'repquote', 'data-id'];
    for (final key in keys) {
      final pid = int.tryParse(node.attributes[key] ?? '');
      if (pid != null && pid > 0) return pid;
    }
    return 0;
  }

  static String _extractReplyBody(dom.Element node) {
    final body = node.querySelector(
      '.replyfloor_content_main, .replyfloor_msg, .replyfloor_message, '
      '.replyfloor_body, .replyfloor_text, .reply_content, .replyfloor_content_text',
    );
    if (body != null && (body.querySelector('img') != null || body.text.trim().isNotEmpty)) {
      return body.innerHtml;
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
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: '输入回复内容…', border: OutlineInputBorder()),
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
    if (message == null || message.isEmpty || !mounted) return;
    final error = await AuthService.instance.replyFloor(widget.tid, parentPid, message, msgid: pid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? '已回复 $author')));
    if (error == null) await _loadReplies(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final c = Theme.of(context).colorScheme;
    final replies = _parseReplies();
    final showReplyToggle = _hasReplies == true || (_hasReplies == null && _replyCandidate);

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(color: c.shadow.withValues(alpha: .025), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ResolvedUserAvatar(
                  uid: comment.uid,
                  username: comment.author,
                  radius: 18,
                  onTap: widget.onProfile,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onProfile,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  comment.author.isEmpty ? '匿名用户' : comment.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (comment.level.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _levelChip(c, comment.level),
                              ],
                            ],
                          ),
                          if (comment.time.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(comment.time, style: TextStyle(fontSize: 10.5, color: c.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surfaceContainerHighest.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    comment.floor.isEmpty ? '${widget.index + 1}楼' : comment.floor,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Divider(height: 1, color: c.outlineVariant.withValues(alpha: .28)),
            const SizedBox(height: 9),
            if (comment.bodyHtml.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 1, right: 1),
                child: NativePostContent(html: comment.bodyHtml),
              ),
            if (_replyError != null && !_loadingReplies)
              Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 3),
                child: Text('楼中楼：$_replyError', style: TextStyle(fontSize: 11, color: c.error)),
              ),
            if (_repliesExpanded && replies.isNotEmpty)
              _RepliesPanel(
                replies: replies,
                onReply: _replyNested,
              ),
            if (showReplyToggle || _replyError != null)
              _CommentActionRow(
                c: c,
                loading: _loadingReplies,
                expanded: _repliesExpanded,
                replyCount: _hasReplies == true ? replies.length : comment.replyCount,
                onReplies: _toggleReplies,
                onReply: widget.onReply,
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: _CompactAction(
                  icon: Icons.reply_rounded,
                  label: '回复本楼',
                  onTap: widget.onReply,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _levelChip(ColorScheme c, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.secondaryContainer,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(text, style: TextStyle(fontSize: 9.5, color: c.onSecondaryContainer, fontWeight: FontWeight.w600)),
      );
}

class _CommentActionRow extends StatelessWidget {
  final ColorScheme c;
  final bool loading, expanded;
  final int replyCount;
  final VoidCallback onReplies;
  final Future<void> Function() onReply;

  const _CommentActionRow({
    required this.c,
    required this.loading,
    required this.expanded,
    required this.replyCount,
    required this.onReplies,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            if (replyCount > 0 || loading)
              _CompactAction(
                icon: expanded ? Icons.keyboard_arrow_up_rounded : Icons.forum_outlined,
                label: loading ? '加载中…' : '${expanded ? '收起' : '查看回复'}${replyCount > 0 ? ' · $replyCount' : ''}',
                onTap: onReplies,
                loading: loading,
              ),
            const Spacer(),
            _CompactAction(
              icon: Icons.reply_rounded,
              label: '回复本楼',
              onTap: onReply,
            ),
          ],
        ),
      );
}

class _CompactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const _CompactAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: loading ? null : onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        foregroundColor: c.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      icon: loading
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8))
          : Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _RepliesPanel extends StatelessWidget {
  final List<_FloorReply> replies;
  final Future<void> Function(_FloorReply reply) onReply;

  const _RepliesPanel({required this.replies, required this.onReply});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 5, bottom: 2),
      padding: const EdgeInsets.fromLTRB(11, 5, 11, 2),
      decoration: BoxDecoration(
        color: c.primaryContainer.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.primary.withValues(alpha: .10)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < replies.length; i++)
            _FloorReplyTile(
              reply: replies[i],
              onReply: () => onReply(replies[i]),
              isLast: i == replies.length - 1,
            ),
        ],
      ),
    );
  }
}

class _FloorReply {
  final int pid, uid, parentPid;
  final String author, time, bodyHtml;

  const _FloorReply({
    required this.pid,
    required this.uid,
    required this.parentPid,
    required this.author,
    required this.time,
    required this.bodyHtml,
  });
}

class _FloorReplyTile extends StatelessWidget {
  final _FloorReply reply;
  final VoidCallback onReply;
  final bool isLast;

  const _FloorReplyTile({
    required this.reply,
    required this.onReply,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final doc = parser.parseFragment(reply.bodyHtml);
    final images = doc.querySelectorAll('img').map((e) => e.outerHtml).toList();
    for (final img in doc.querySelectorAll('img').toList()) img.remove();
    final textHtml = doc.nodes.map((e) => e is dom.Element ? e.outerHtml : (e.text ?? '')).join().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(2, 7, 2, 6),
      decoration: isLast
          ? null
          : BoxDecoration(border: Border(bottom: BorderSide(color: c.outlineVariant.withValues(alpha: .25)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ResolvedUserAvatar(uid: reply.uid, username: reply.author, radius: 12),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  reply.author.isEmpty ? '楼中楼回复' : reply.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (reply.time.isNotEmpty)
                Text(reply.time, style: TextStyle(fontSize: 9.5, color: c.onSurfaceVariant)),
            ],
          ),
          if (textHtml.isNotEmpty) ...[
            const SizedBox(height: 3),
            NativePostContent(html: textHtml),
          ],
          for (final image in images) NativePostContent(html: image),
          Align(
            alignment: Alignment.centerRight,
            child: _CompactAction(
              icon: Icons.reply_rounded,
              label: '回复',
              onTap: onReply,
            ),
          ),
        ],
      ),
    );
  }
}
