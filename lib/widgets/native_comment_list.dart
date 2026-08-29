import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

class NativeCommentList extends StatelessWidget {
  final String html;
  const NativeCommentList({super.key, required this.html});

  List<_CommentFloor> _parse() {
    if (html.trim().isEmpty) return const [];
    final doc = parser.parseFragment(html);
    final cards = doc.querySelectorAll('.post-card');
    final result = <_CommentFloor>[];
    for (final card in cards) {
      final body = card.querySelector('.p-body');
      if (body == null) continue;
      result.add(_CommentFloor(
        floor: _text(card.querySelector('.p-floor')),
        author: _text(card.querySelector('.p-author')),
        level: _text(card.querySelector('.p-level')),
        time: _text(card.querySelector('.p-time')),
        body: body,
      ));
    }
    return result;
  }

  static String _text(dom.Element? e) => e?.text.replaceAll(RegExp(r'\\s+'), ' ').trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final comments = _parse();
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂无评论', style: TextStyle(color: Colors.grey))),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      itemCount: comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _CommentCard(comment: comments[index], index: index),
    );
  }
}

class _CommentFloor {
  final String floor;
  final String author;
  final String level;
  final String time;
  final dom.Element body;
  const _CommentFloor({required this.floor, required this.author, required this.level, required this.time, required this.body});
}

class _CommentCard extends StatelessWidget {
  final _CommentFloor comment;
  final int index;
  const _CommentCard({required this.comment, required this.index});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: s.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.outlineVariant.withValues(alpha: .55)),
        boxShadow: [BoxShadow(color: s.shadow.withValues(alpha: .035), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: s.secondaryContainer,
            child: Text(comment.author.isEmpty ? '?' : comment.author.characters.first, style: TextStyle(fontWeight: FontWeight.w800, color: s.onSecondaryContainer)),
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(comment.author.isEmpty ? '匿名用户' : comment.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              if (comment.level.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: s.secondaryContainer, borderRadius: BorderRadius.circular(7)), child: Text(comment.level, style: TextStyle(fontSize: 9.5, color: s.onSecondaryContainer))),
              ],
            ]),
            if (comment.time.isNotEmpty) Text(comment.time, style: TextStyle(fontSize: 10.5, color: s.onSurfaceVariant)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: s.surfaceContainerHighest, borderRadius: BorderRadius.circular(9)), child: Text(comment.floor.isEmpty ? '${index + 2}楼' : comment.floor, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: s.onSurfaceVariant))),
        ]),
        const SizedBox(height: 11),
        Container(height: 1, color: s.outlineVariant.withValues(alpha: .35)),
        const SizedBox(height: 11),
        _HtmlNodes(element: comment.body),
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
      final text = node.data.replaceAll(RegExp(r'\\s+'), ' ').trim();
      return text.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 7), child: Text(text, style: const TextStyle(fontSize: 14, height: 1.7)));
    }
    if (node is! dom.Element) return const SizedBox.shrink();
    final tag = node.localName?.toLowerCase() ?? '';
    if (tag == 'img') {
      final src = node.attributes['src'] ?? node.attributes['data-src'] ?? '';
      if (src.isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(src, width: double.infinity, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink())));
    }
    if (tag == 'br') return const SizedBox(height: 5);
    if (tag == 'blockquote') return Container(margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.fromLTRB(12, 8, 10, 8), decoration: BoxDecoration(color: s.primaryContainer.withValues(alpha: .42), borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: s.primary, width: 3))), child: _HtmlNodes(element: node));
    if (tag == 'pre' || tag == 'code') return Container(width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: s.surfaceContainerHighest, borderRadius: BorderRadius.circular(9)), child: Text(node.text.trim(), style: const TextStyle(fontSize: 12.5, height: 1.55, fontFamily: 'monospace')));
    if (tag == 'a') return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(node.text.trim(), style: TextStyle(fontSize: 14, height: 1.7, color: s.primary, decoration: TextDecoration.underline)));
    if (tag == 'p' || tag == 'div' || tag == 'section' || tag == 'article' || tag == 'li') return Padding(padding: const EdgeInsets.only(bottom: 5), child: _HtmlNodes(element: node));
    return _HtmlNodes(element: node);
  }
}