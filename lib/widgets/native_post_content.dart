import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// Native Flutter renderer for forum post HTML.
/// The widget participates in Flutter's normal layout, so its height follows
/// the actual content instead of a WebView measurement.
class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;

  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return const SizedBox.shrink();
    final nodes = body.nodes
        .where((node) => node is! dom.Text || _nodeText(node).trim().isNotEmpty)
        .toList();
    // 用 SelectionArea 让整段正文支持长按选择并复制文本。
    return SelectionArea(
      child: _NodeList(nodes: nodes, onLinkTap: onLinkTap),
    );
  }
}

String _nodeText(dom.Node node) => node.text ?? '';

class _NodeList extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;
  const _NodeList({required this.nodes, this.onLinkTap});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final node in nodes) _NodeWidget(node: node, onLinkTap: onLinkTap),
    ],
  );
}

class _NodeWidget extends StatelessWidget {
  final dom.Node node;
  final ValueChanged<String>? onLinkTap;
  const _NodeWidget({required this.node, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    if (node is dom.Text) {
      final text = _nodeText(node).trim();
      return text.isEmpty ? const SizedBox.shrink() : _Paragraph(text: text);
    }
    if (node is! dom.Element) return const SizedBox.shrink();
    final e = node as dom.Element;
    final tag = e.localName?.toLowerCase() ?? '';
    switch (tag) {
      case 'br':
        return const SizedBox(height: 6);
      case 'p':
        return _Block(child: _InlineContent(e.nodes, onLinkTap: onLinkTap));
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _Heading(
          level: int.tryParse(tag.substring(1)) ?? 3,
          children: e.nodes,
          onLinkTap: onLinkTap,
        );
      case 'blockquote':
        return _Quote(children: e.nodes, onLinkTap: onLinkTap);
      case 'ul':
        return _ListBlock(element: e, ordered: false, onLinkTap: onLinkTap);
      case 'ol':
        return _ListBlock(element: e, ordered: true, onLinkTap: onLinkTap);
      case 'pre':
        return _CodeBlock(text: e.text);
      case 'code':
        return _InlineCode(text: e.text);
      case 'img':
        final rawSrc = e.attributes['src']?.trim() ?? '';
        final src = _resolveUrl(rawSrc);
        return src.isEmpty
            ? const SizedBox.shrink()
            : _ImageBlock(src: src, alt: e.attributes['alt']);
      case 'hr':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1),
        );
      case 'table':
        return _TableBlock(element: e, onLinkTap: onLinkTap);
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
          child: _NodeList(nodes: e.nodes, onLinkTap: onLinkTap),
        );
      default:
        return _Block(child: _InlineContent(e.nodes, onLinkTap: onLinkTap));
    }
  }
}

class _Block extends StatelessWidget {
  final Widget child;
  const _Block({required this.child});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 11), child: child);
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
    final size = switch (level) {
      1 => 24.0,
      2 => 21.0,
      3 => 19.0,
      _ => 17.0,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 7, bottom: 10),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: size,
          height: 1.35,
          fontWeight: FontWeight.w800,
        ),
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
    for (final node in nodes)
      _appendSpan(
        spans,
        node,
        DefaultTextStyle.of(context).style.copyWith(fontSize: 16, height: 1.62),
      );
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }

  void _appendSpan(List<InlineSpan> spans, dom.Node node, TextStyle style) {
    if (node is dom.Text) {
      final text = _nodeText(node);
      if (text.isNotEmpty) spans.add(TextSpan(text: text, style: style));
      return;
    }
    if (node is! dom.Element) return;
    final e = node as dom.Element;
    final tag = e.localName?.toLowerCase() ?? '';
    var next = style;
    if (tag == 'strong' || tag == 'b')
      next = style.copyWith(fontWeight: FontWeight.w800);
    if (tag == 'em' || tag == 'i')
      next = style.copyWith(fontStyle: FontStyle.italic);
    if (tag == 'del' || tag == 's')
      next = style.copyWith(decoration: TextDecoration.lineThrough);
    if (tag == 'code')
      next = style.copyWith(
        fontFamily: 'monospace',
        backgroundColor: const Color(0xfff0f2f6),
      );
    if (tag == 'a') {
      final href = e.attributes['href']?.trim() ?? '';
      final recognizer = TapGestureRecognizer()
        ..onTap = () => onLinkTap?.call(href);
      spans.add(
        TextSpan(
          text: e.text,
          style: style.copyWith(
            color: const Color(0xff4d63d8),
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        ),
      );
      return;
    }
    if (tag == 'br') {
      spans.add(const TextSpan(text: '\n'));
      return;
    }
    for (final child in e.nodes) _appendSpan(spans, child, next);
  }
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
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
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
  const _ListBlock({
    required this.element,
    required this.ordered,
    this.onLinkTap,
  });
  @override
  Widget build(BuildContext context) {
    final items = element.children
        .where((e) => e.localName?.toLowerCase() == 'li')
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 25,
                  child: Text(
                    ordered ? '${i + 1}.' : '•',
                    style: const TextStyle(fontSize: 16, height: 1.62),
                  ),
                ),
                Expanded(
                  child: _InlineContent(items[i].nodes, onLinkTap: onLinkTap),
                ),
              ],
            ),
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
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
    ),
  );
}

class _InlineCode extends StatelessWidget {
  final String text;
  const _InlineCode({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
    ),
  );
}

String _resolveUrl(String value) {
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('/')) return 'https://www.ycoo.net$value';
  if (!value.startsWith('http://') && !value.startsWith('https://'))
    return 'https://www.ycoo.net/$value';
  return value;
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
      child: Image.network(
        src,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          padding: const EdgeInsets.all(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(alt?.isNotEmpty == true ? alt! : '图片加载失败'),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
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
          border: TableBorder.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          children: [
            for (final row in rows)
              TableRow(
                children: [
                  for (final cell in row.children.where(
                    (e) => e.localName == 'td' || e.localName == 'th',
                  ))
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: _InlineContent(cell.nodes, onLinkTap: onLinkTap),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
