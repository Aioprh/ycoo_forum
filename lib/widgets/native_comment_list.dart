import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../pages/native_profile_page.dart';
import '../services/auth_service.dart';
import '../services/comment_profile_resolver.dart';
import 'resolved_user_avatar.dart';

class NativeCommentList extends StatelessWidget {
  final String html;
  final void Function(int pid, String author)? onReply;
  const NativeCommentList({super.key, required this.html, this.onReply});

  List<_CommentFloor> _parse() {
    if (html.trim().isEmpty) return const [];
    final doc = parser.parseFragment(html);
    final result = <_CommentFloor>[];
    for (final card in doc.querySelectorAll('.post-card')) {
      final body = card.querySelector('.p-body');
      if (body == null) continue;
      final authorNode = card.querySelector('.p-author');
      result.add(_CommentFloor(
        pid: int.tryParse(card.attributes['data-pid'] ?? '0') ?? 0,
        uid: _extractUid(card, authorNode),
        floor: _text(card.querySelector('.p-floor')),
        author: _text(authorNode),
        level: _text(card.querySelector('.p-level')),
        time: _text(card.querySelector('.p-time')),
        body: body,
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
      final raw = '${node.attributes['href'] ?? ''} ${node.attributes['src'] ?? ''} ${node.attributes['data-src'] ?? ''}';
      final uid = _uidFromUrl(raw);
      if (uid > 0) return uid;
    }
    return 0;
  }

  static int _uidFromUrl(String value) {
    const patterns = [
      r'(?:[?&]|%3F|%26)uid(?:=|%3D)(\d+)',
      r'home\.php[^\s#]*[?&]uid=(\d+)',
      r'(?:^|[/?_-])space-uid-(\d+)',
      r'(?:^|[/?_-])space/uid/(\d+)',
      r'(?:^|[/?_-])uid[-_/](\d+)',
    ];
    for (final source in patterns) {
      final match = RegExp(source, caseSensitive: false).firstMatch(value);
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

  static String _text(dom.Element? e) => e?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

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
    final tid = int.tryParse(section?.attributes['data-tid'] ?? '0') ?? 0;
    final fid = int.tryParse(section?.attributes['data-fid'] ?? '0') ?? 0;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      itemCount: comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _CommentCard(
        comment: comments[index],
        index: index,
        onReply: onReply ?? (pid, author) => _replyDialog(context, tid, fid, pid, author),
        onProfile: () => _openProfile(context, comments[index]),
      ),
    );
  }

  Future<void> _openProfile(BuildContext context, _CommentFloor comment) async {
    var uid = comment.uid;
    if (uid <= 0 && comment.author.trim().isNotEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(content: Text('正在获取用户资料…')));
      uid = await CommentProfileResolver.instance.resolveUid(comment.author) ?? 0;
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
    }
    if (!context.mounted) return;
    if (uid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到该用户资料，请稍后重试')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NativeProfilePage(uid: uid, username: comment.author),
      ),
    );
  }

  Future<void> _replyDialog(BuildContext context, int tid, int fid, int pid, String author) async {
    if (tid <= 0 || fid <= 0 || pid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未取得楼层信息，请刷新帖子后重试')));
      return;
    }
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
              if (controller.text.trim().isNotEmpty) Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在回复…')));
    final error = await AuthService.instance.reply(tid, fid, message, replyPid: pid);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(error ?? '已回复本楼')));
  }
}

class _CommentFloor {
  final int pid, uid;
  final String floor, author, level, time;
  final dom.Element body;
  const _CommentFloor({
    required this.pid,
    required this.uid,
    required this.floor,
    required this.author,
    required this.level,
    required this.time,
    required this.body,
  });
}

class _CommentCard extends StatelessWidget {
  final _CommentFloor comment;
  final int index;
  final void Function(int pid, String author) onReply;
  final VoidCallback onProfile;
  const _CommentCard({required this.comment, required this.index, required this.onReply, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
      decoration: BoxDecoration(
        color: s.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.outlineVariant.withValues(alpha: .55)),
        boxShadow: [BoxShadow(color: s.shadow.withValues(alpha: .035), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ResolvedUserAvatar(
            uid: comment.uid,
            username: comment.author,
            radius: 18,
            onTap: onProfile,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: InkWell(
              onTap: onProfile,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(comment.author.isEmpty ? '匿名用户' : comment.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                  if (comment.level.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: s.secondaryContainer, borderRadius: BorderRadius.circular(7)),
                      child: Text(comment.level, style: TextStyle(fontSize: 9.5, color: s.onSecondaryContainer)),
                    ),
                  ],
                ]),
                if (comment.time.isNotEmpty) Text(comment.time, style: TextStyle(fontSize: 10.5, color: s.onSurfaceVariant)),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: s.surfaceContainerHighest, borderRadius: BorderRadius.circular(9)),
            child: Text(comment.floor.isEmpty ? '${index + 2}楼' : comment.floor, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: s.onSurfaceVariant)),
          ),
        ]),
        const SizedBox(height: 11),
        Container(height: 1, color: s.outlineVariant.withValues(alpha: .35)),
        const SizedBox(height: 10),
        _HtmlNodes(element: comment.body),
        if (comment.pid > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: () => onReply(comment.pid, comment.author), icon: const Icon(Icons.reply_rounded, size: 17), label: const Text('回复本楼')),
          ),
      ]),
    );
  }
}

class _HtmlNodes extends StatelessWidget {
  final dom.Element element;
  const _HtmlNodes({required this.element});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: element.nodes.map((n) => _node(context, n)).toList());

  Widget _node(BuildContext context, dom.Node node) {
    final s = Theme.of(context).colorScheme;
    if (node is dom.Text) {
      final text = node.data.replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 7), child: Text(text, style: const TextStyle(fontSize: 14, height: 1.7)));
    }
    if (node is! dom.Element) return const SizedBox.shrink();
    final tag = node.localName?.toLowerCase() ?? '';
    if (tag == 'img') {
      var src = node.attributes['src'] ?? node.attributes['data-src'] ?? '';
      if (src.startsWith('//')) src = 'https:$src';
      else if (src.startsWith('/')) src = 'https://www.ycoo.net$src';
      else if (!src.startsWith('http://') && !src.startsWith('https://')) src = 'https://www.ycoo.net/$src';
      if (src.isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(src, width: double.infinity, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink())));
    }
    if (tag == 'br') return const SizedBox(height: 5);
    if (tag == 'blockquote') return Container(margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.fromLTRB(12, 8, 10, 8), decoration: BoxDecoration(color: s.primaryContainer.withValues(alpha: .42), borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: s.primary, width: 3))), child: _HtmlNodes(element: node));
    if (tag == 'pre' || tag == 'code') return Container(width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: s.surfaceContainerHighest, borderRadius: BorderRadius.circular(9)), child: Text(node.text.trim(), style: const TextStyle(fontSize: 12.5, height: 1.55, fontFamily: 'monospace')));
    if (tag == 'a') return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(node.text.trim(), style: TextStyle(fontSize: 14, height: 1.7, color: s.primary, decoration: TextDecoration.underline));
    if (tag == 'p' || tag == 'div' || tag == 'section' || tag == 'article' || tag == 'li') return Padding(padding: const EdgeInsets.only(bottom: 5), child: _HtmlNodes(element: node));
    return _HtmlNodes(element: node);
  }
}
