import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// Native Flutter renderer for forum post HTML.
///
/// It deliberately renders the common subset used by forum posts instead of
/// embedding a browser. The widget therefore participates in Flutter's normal
/// layout and its height follows the actual content automatically.
class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;

  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return const SizedBox.shrink();

    final nodes = body.nodes.where((node) => !_isWhitespace(node)).toList();
    return _NodeList(nodes: nodes, onLinkTap: onLinkTap);
  }

  bool _isWhitespace(dom.Node node) =>
      node is dom.Text && node.data.trim().isEmpty;
}

class _NodeList extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;

  const _NodeList({required this.nodes, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes) _NodeWidget(node: node, onLinkTap: onLinkTap),
      ],
    );
  }
}

class _NodeWidget extends StatelessWidget {
  final dom.Node node;
  final ValueChanged<String>? onLinkTap;

  const _NodeWidget({required this.node, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    if (node is dom.Text) {
      final text = node.data.trim();
      return text.isEmpty ? const SizedBox.shrink() : _Paragraph(text: text);
    }

    if (node is! dom.Element) return const SizedBox.shrink();
    final element = node as dom.Element;
    final tag = element.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'br':
        return const SizedBox(height: 6);
      case 'p':
        return _Block(child: _InlineContent(element.nodes, onLinkTap: onLinkTap));
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _Heading(level: int.tryParse(tag.substring(1)) ?? 3, children: element.nodes, onLinkTap: onLinkTap);
      case 'blockquote':
        return _Quote(children: element.nodes, onLinkTap: onLinkTap);
      case 'ul':
        return _ListBlock(element: element, ordered: false, onLinkTap: onLinkTap);
      case 'ol':
        return _ListBlock(element: element, ordered: true, onLinkTap: onLinkTap);
      case 'pre':
        return _CodeBlock(text: element.text);
      case 'code':
        return _InlineCode(text: element.text);
      case 'img':
        final src = element.attributes['src']?.trim() ?? '';
        return src.isEmpty ? const SizedBox.shrink() : _ImageBlock(src: src, alt: element.attributes['alt']);
      case 'hr':
        return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1));
      case 'table':
        return _TableBlock(element: element, onLinkTap: onLinkTap);
      case 'div':
      case 'section':
      case 'article':
      case 'main':
      case 'figure':
      case 'figcaption':
      case 'dl':
      case 'dt':
      case 'dd':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _NodeList(nodes: element.nodes, onLinkTap: onLinkTap),
        );
      default:
        return _Block(child: _InlineContent(element.nodes, onLinkTap: onLinkTap));
    }
  }
}

class _Block extends StatelessWidget {
  final Widget child;
  const _Block({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: child,
      );
}

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Text(text, style: const TextStyle(fontSize: 16, height: 1.62)),
      );
}

class _Heading extends StatelessWidget {
  final int level;
  final List<dom.Node> children;
  final ValueChanged<String>? onLinkTap;
  const _Heading({required this.level, required this.children, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final size = switch (level) { 1 => 24.0, 2 => 21.0, 3 => 19.0, _ => 17.0 };
    return Padding(
      padding: const EdgeInsets.only(top: 7, bottom: 10),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: size, height: 1.35, fontWeight: FontWeight.w800),
        child: _InlineContent(children, onLinkTap: onLinkTap),
      ),
    );
  }
}

class _InlineContent extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;
  const _InlineContent(this.nodes, {this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      _appendSpan(spans, node, const TextStyle(fontSize: 16, height: 1.62));
    }
    return RichText(text: TextSpan(style: DefaultTextStyle.of(context).style, children: spans));
  }

  void _appendSpan(List<InlineSpan> spans, dom.Node node, TextStyle style) {
    if (node is dom.Text) {
      if (node.data.isNotEmpty) spans.add(TextSpan(text: node.data, style: style));
      return;
    }
    if (node is! dom.Element) return;
    final e = node as dom.Element;
    final tag = e.localName?.toLowerCase() ?? '';
    var next = style;
    if (tag == 'strong' || tag == 'b') next = style.copyWith(fontWeight: FontWeight.w800);
    if (tag == 'em' || tag == 'i') next = style.copyWith(fontStyle: FontStyle.italic);
    if (tag == 'del' || tag == 's') next = style.copyWith(decoration: TextDecoration.lineThrough);
    if (tag == 'code') {
      next = style.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0xfff0f2f6));
    }
    if (tag == 'a') {
      final href = e.attributes['href']?.trim() ?? '';
      spans.add(TextSpan(
        text: e.text,
        style: style.copyWith(color: const Color(0xff4d63d8), decoration: TextDecoration.underline),
        recognizer: _TapRecognizer(() => onLinkTap?.call(href)),
      ));
      return;
    }
    if (tag == 'br') {
      spans.add(const TextSpan(text: '\n'));
      return;
    }
    for (final child in e.nodes) {
      _appendSpan(spans, child, next);
    }
  }
}

class _TapRecognizer extends Object with _TapRecognizerMixin {
  final VoidCallback callback;
  _TapRecognizer(this.callback);
  @override
  void invoke() => callback();
}

mixin _TapRecognizerMixin {
  void invoke();
}

class _Quote extends StatelessWidget {
  final List<dom.Node> children;
  final ValueChanged<String>? onLinkTap;
  const _Quote({required this.children, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 2),
      decoration: BoxDecoration(
        color: c.primaryContainer.withValues(alpha: .34),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(14), bottomRight: Radius.circular(14)),
        border: Border(left: BorderSide(color: c.primary, width: 3)),
      ),
      child: _NodeList(nodes: children, onLinkTap: onLinkTap),
    );
  }
}

class _ListBlock extends StatelessWidget {
  final dom.Element element;
  final bool ordered;
  final ValueChanged<String>? onLinkTap;
  const _ListBlock({required this.element, required this.ordered, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final items = element.children.where((e) => e.localName?.toLowerCase() == 'li').toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 25, child: Text(ordered ? '${i + 1}.' : '•', style: const TextStyle(fontSize: 16, height: 1.62))),
              Expanded(child: _InlineContent(items[i].nodes, onLinkTap: onLinkTap)),
            ]),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;
  const _CodeBlock({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.55))),
      );
}

class _InlineCode extends StatelessWidget {
  final String text;
  const _InlineCode({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
      );
}

class _ImageBlock extends StatelessWidget {
  final String src;
  final String? alt;
  const _ImageBlock({required this.src, this.alt});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(src, width: double.infinity, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(padding: const EdgeInsets.all(14), color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Text(alt?.isNotEmpty == true ? alt! : '图片加载失败')),
            loadingBuilder: (context, child, progress) => progress == null ? child : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        ),
      );
}

class _TableBlock extends StatelessWidget {
  final dom.Element element;
  final ValueChanged<String>? onLinkTap;
  const _TableBlock({required this.element, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final rows = element.querySelectorAll('tr');
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant),
          children: [
            for (final row in rows)
              TableRow(children: [
                for (final cell in row.children.where((e) => e.localName == 'td' || e.localName == 'th'))
                  Padding(padding: const EdgeInsets.all(8), child: _InlineContent(cell.nodes, onLinkTap: onLinkTap)),
              ]),
          ],
        ),
      ),
    );
  }
}
