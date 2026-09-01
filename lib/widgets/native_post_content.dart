import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../services/auth_service.dart';
import '../services/site_config.dart';

/// Native Flutter renderer for forum post HTML.
/// Supports normal images, Discuz/Comiis lazy-loaded images and protected attachments.
class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;

  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final body = html_parser.parse(html).body;
    if (body == null) return const SizedBox.shrink();
    final nodes = body.nodes
        .where((node) => node is! dom.Text || _nodeText(node).trim().isNotEmpty)
        .toList();
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
          for (final node in nodes)
            _NodeWidget(node: node, onLinkTap: onLinkTap),
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
      return text.isEmpty ? const SizedBox.shrink() : _Paragraph(text);
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
        final src = _imageUrl(e);
        return src.isEmpty
            ? _missingImage(context, e.attributes['alt'])
            : _ImageBlock(src: src, alt: e.attributes['alt'], onTap: (onLinkTap != null && src.isNotEmpty) ? () => onLinkTap(src) : null);
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

  Widget _missingImage(BuildContext context, String? alt) {
    final text = alt?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
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
  const _Paragraph(this.text);

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

  const _Heading({
    required this.level,
    required this.children,
    this.onLinkTap,
  });

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
    final children = <Widget>[];
    final spans = <InlineSpan>[];

    void flushText() {
      if (spans.isEmpty) return;
      children.add(
        Text.rich(
          TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: List<InlineSpan>.from(spans),
          ),
          selectionColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: .22),
        ),
      );
      spans.clear();
    }

    for (final node in nodes) {
      if (node is dom.Element &&
          node.localName?.toLowerCase() == 'a' &&
          _isAttachmentLink(node.attributes['href'])) {
        flushText();
        children.add(_AttachmentCard(
          href: (node.attributes['href'] ?? '').trim(),
          title: node.text.trim(),
          onTap: (onLinkTap != null) ? () => onLinkTap((node.attributes['href'] ?? '').trim()) : null,
        ));
        continue;
      }
      if (node is dom.Element && node.localName?.toLowerCase() == 'img') {
        flushText();
        final src = _imageUrl(node);
        if (src.isNotEmpty) {
          children.add(_ImageBlock(
            src: src,
            alt: node.attributes['alt'],
            onTap:
                (onLinkTap != null) ? () => onLinkTap(src) : null,
          ));
        }
        continue;
      }
      _appendSpan(
        spans,
        node,
        DefaultTextStyle.of(context)
            .style
            .copyWith(fontSize: 16, height: 1.62),
      );
    }
    flushText();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
    if (tag == 'img') return;

    var next = style;
    if (tag == 'strong' || tag == 'b') {
      next = style.copyWith(fontWeight: FontWeight.w800);
    }
    if (tag == 'em' || tag == 'i') {
      next = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (tag == 'del' || tag == 's') {
      next = style.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (tag == 'code') {
      next = style.copyWith(
        fontFamily: 'monospace',
        backgroundColor: const Color(0xfff0f2f6),
      );
    }
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
    for (final child in e.nodes) {
      _appendSpan(spans, child, next);
    }
  }
}

/// Discuz/Comiis 图片可能把真实地址放在 comiis_loadimages，而 src 只是占位图。
String _imageUrl(dom.Element e) {
  const candidates = [
    'comiis_loadimages',
    'data-src',
    'data-original',
    'data-url',
    'lazy-src',
    'original',
    'zoomfile',
    'file',
    'src',
  ];

  String normalize(String value, {bool forumPath = false}) {
    var v = value.trim();
    if (v.isEmpty || v.startsWith('data:')) return '';
    if (v.contains(',')) {
      v = v.split(',').first.trim().split(RegExp(r'\s+')).first;
    }
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    return forumPath ? SiteConfig.resolve(v) : SiteConfig.resolveCdn(v);
  }

  for (final key in candidates) {
    final value = e.attributes[key];
    if (value == null || value.trim().isEmpty) continue;
    final url = normalize(value, forumPath: key == 'comiis_loadimages');
    if (url.isNotEmpty && !_looksLikePlaceholder(url)) return url;
  }

  final srcset = e.attributes['srcset'];
  if (srcset != null) {
    final url = normalize(srcset);
    if (url.isNotEmpty && !_looksLikePlaceholder(url)) return url;
  }
  return '';
}

bool _looksLikePlaceholder(String url) {
  final value = url.toLowerCase();
  return value.contains('none.gif') ||
      value.contains('none.png') ||
      value.contains('loading.gif') ||
      value.contains('lazyload') ||
      value.contains('placeholder') ||
      value.endsWith('/spacer.gif');
}

/// 是否为 Discuz 附件链接(下载、图片附件等)。
bool _isAttachmentLink(String? href) {
  if (href == null || href.isEmpty) return false;
  final u = href.toLowerCase();
  return u.contains('attachment.php') ||
      u.contains('mod=attachment') ||
      u.contains('aid=') ||
      u.contains('noupdate=yes') ||
      u.contains('/attachment/') ||
      u.contains('/download/');
}

class _ImageBlock extends StatelessWidget {
  final String src;
  final String? alt;
  final VoidCallback? onTap;

  const _ImageBlock({required this.src, this.alt, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cookie = AuthService.instance.authCookie;
    final headers = <String, String>{
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Referer': SiteConfig.base,
    };
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        src,
        width: double.infinity,
        fit: BoxFit.contain,
        headers: headers,
        errorBuilder: (_, __, ___) => Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.all(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(alt?.isNotEmpty == true ? alt! : '图片加载失败\n$src'),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: onTap == null
          ? image
          : GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  image,
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.download_rounded,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '点击下载图片',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            _ListItem(item: items[i], ordered: ordered, index: i, onLinkTap: onLinkTap),
        ],
      ),
    );
  }
}

class _ListItem extends StatelessWidget {
  final dom.Element item;
  final bool ordered;
  final int index;
  final ValueChanged<String>? onLinkTap;

  const _ListItem({
    required this.item,
    required this.ordered,
    required this.index,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    // 该 li 里是否直接包含图片（可能被 span/a 等包裹），
    // 若包含则整行渲染为图片，避免 _InlineContent 把 wrapped img 丢弃。
    final img = item.querySelector('img');
    if (img != null) {
      final src = _imageUrl(img);
      if (src.isNotEmpty) {
        return _ImageBlock(
          src: src,
          alt: img.attributes['alt'],
          onTap: (onLinkTap != null) ? () => onLinkTap(src) : null,
        );
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 25,
          child: Text(
            ordered ? '${index + 1}.' : '•',
            style: const TextStyle(fontSize: 16, height: 1.62),
          ),
        ),
        Expanded(
          child: _InlineContent(item.nodes, onLinkTap: onLinkTap),
        ),
      ],
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

/// 正文里的附件链接: 以清晰可点的卡片展示, 点击触发下载。
class _AttachmentCard extends StatelessWidget {
  final String href;
  final String title;
  final VoidCallback? onTap;

  const _AttachmentCard({
    required this.href,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final label = title.isNotEmpty ? title : '下载附件';
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Material(
        color: c.secondaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.attach_file_rounded, color: c.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, height: 1.3),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.download_rounded, color: c.primary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
