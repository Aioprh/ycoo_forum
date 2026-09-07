import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/site_config.dart';

class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;
  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final body = html_parser.parse(html).body;
    if (body == null) return const SizedBox.shrink();
    final nodes = body.nodes.where(_hasRenderableNode).toList();
    return _NodeList(nodes: nodes, onLinkTap: onLinkTap);
  }
}

bool _hasRenderableNode(dom.Node node) {
  if (node is dom.Text) return (node.text ?? '').trim().isNotEmpty;
  if (node is! dom.Element) return false;
  final tag = (node.localName ?? '').toLowerCase();
  if (tag == 'br') return false;
  if (tag == 'ul' || tag == 'ol') return node.children.any(_hasRenderableListItem);
  if (tag == 'li') return _hasRenderableListItem(node);
  return true;
}

bool _hasRenderableListItem(dom.Element item) {
  final text = _visibleListText(item);
  if (text.isNotEmpty) return true;
  return item.querySelector('img,video,iframe,audio,table,pre') != null;
}

String _visibleListText(dom.Element element) => element.text
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
    .replaceAll(RegExp(r'^[•●○◦▪▫‣⁃∙·・\-–—*_.,。．、]+'), '')
    .replaceAll(RegExp(r'[•●○◦▪▫‣⁃∙·・]'), '')
    .trim();

class _NodeList extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;
  const _NodeList({required this.nodes, this.onLinkTap});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [for (final node in nodes) _NodeWidget(node: node, onLinkTap: onLinkTap)],
      );
}

class _NodeWidget extends StatelessWidget {
  final dom.Node node;
  final ValueChanged<String>? onLinkTap;
  const _NodeWidget({required this.node, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    if (node is dom.Text) {
      final text = node.text ?? '';
      return text.trim().isEmpty ? const SizedBox.shrink() : _TextBlock(nodes: [node], onLinkTap: onLinkTap);
    }
    if (node is! dom.Element) return const SizedBox.shrink();
    final e = node as dom.Element;
    final tag = (e.localName ?? '').toLowerCase();
    switch (tag) {
      case 'br':
        return const SizedBox.shrink();
      case 'p':
        return e.querySelector('img,video,iframe,audio') != null
            ? _NodeList(nodes: e.nodes.where(_hasRenderableNode).toList(), onLinkTap: onLinkTap)
            : _TextBlock(nodes: e.nodes, onLinkTap: onLinkTap);
      case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6':
        return _TextBlock(
          nodes: e.nodes,
          onLinkTap: onLinkTap,
          style: TextStyle(fontSize: switch (tag) {'h1' => 24, 'h2' => 21, 'h3' => 19, _ => 17}, height: 1.35, fontWeight: FontWeight.w800),
          padding: const EdgeInsets.only(top: 6, bottom: 10),
        );
      case 'blockquote':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 3))),
          child: _NodeList(nodes: e.nodes.where(_hasRenderableNode).toList(), onLinkTap: onLinkTap),
        );
      case 'ul': case 'ol':
        return _ListBlock(element: e, ordered: tag == 'ol', onLinkTap: onLinkTap);
      case 'li':
        return _ListItemBlock(element: e, ordered: false, index: 1, onLinkTap: onLinkTap);
      case 'pre':
        return _CodeBlock(text: e.text);
      case 'img':
        return _imageWidget(context, e, e);
      case 'a':
        final images = e.querySelectorAll('img');
        if (images.isNotEmpty) return _imageWidget(context, images.first, e);
        return _TextBlock(nodes: e.nodes, onLinkTap: onLinkTap);
      case 'hr':
        return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1));
      case 'div': case 'section': case 'article': case 'main': case 'figure': case 'figcaption': case 'dl': case 'dt': case 'dd':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _NodeList(nodes: e.nodes.where(_hasRenderableNode).toList(), onLinkTap: onLinkTap),
        );
      default:
        return _TextBlock(nodes: e.nodes, onLinkTap: onLinkTap);
    }
  }

  Widget _imageWidget(BuildContext context, dom.Element image, dom.Element link) {
    final src = _imageUrl(image);
    if (src.isEmpty) return const SizedBox.shrink();
    final href = link.localName?.toLowerCase() == 'a' ? link.attributes['href']?.trim() : null;
    return _ImageBlock(
      src: src,
      alt: image.attributes['alt'],
      onTap: href != null && href.isNotEmpty ? () => _openLink(href) : (onLinkTap == null ? null : () => onLinkTap!(src)),
    );
  }

  Future<void> _openLink(String href) async {
    if (_isAttachmentLink(href) && onLinkTap != null) {
      onLinkTap!(href);
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _TextBlock extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;
  final TextStyle? style;
  final EdgeInsets padding;
  const _TextBlock({required this.nodes, this.onLinkTap, this.style, this.padding = const EdgeInsets.only(bottom: 9)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    _appendNodes(spans, nodes, (style ?? DefaultTextStyle.of(context).style).copyWith(fontSize: style?.fontSize ?? 16, height: style?.height ?? 1.62), scheme);
    if (spans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: SelectableText.rich(
        TextSpan(children: spans),
        selectionColor: scheme.primary.withValues(alpha: .22),
        contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
      ),
    );
  }

  void _appendNodes(List<InlineSpan> spans, List<dom.Node> nodes, TextStyle current, ColorScheme scheme) {
    for (final node in nodes) _appendNode(spans, node, current, scheme);
  }

  void _appendNode(List<InlineSpan> spans, dom.Node node, TextStyle current, ColorScheme scheme) {
    if (node is dom.Text) {
      _appendTextWithLinks(spans, node.text ?? '', current, scheme);
      return;
    }
    if (node is! dom.Element) return;
    final tag = (node.localName ?? '').toLowerCase();
    if (tag == 'br') {
      spans.add(const TextSpan(text: '\n'));
      return;
    }
    if (tag == 'img') return;
    var next = current;
    if (tag == 'strong' || tag == 'b') next = current.copyWith(fontWeight: FontWeight.w800);
    else if (tag == 'em' || tag == 'i') next = current.copyWith(fontStyle: FontStyle.italic);
    else if (tag == 'del' || tag == 's') next = current.copyWith(decoration: TextDecoration.lineThrough);
    else if (tag == 'code') next = current.copyWith(fontFamily: 'monospace', backgroundColor: scheme.surfaceContainerHighest);
    if (tag == 'a') {
      final href = node.attributes['href']?.trim() ?? '';
      final uri = Uri.tryParse(href);
      if (node.querySelector('img') != null) return;
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        _appendNodes(spans, node.nodes, next, scheme);
        return;
      }
      spans.add(TextSpan(text: node.text, style: next.copyWith(color: scheme.primary, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => _openUrl(href)));
      return;
    }
    _appendNodes(spans, node.nodes, next, scheme);
  }

  void _appendTextWithLinks(List<InlineSpan> spans, String text, TextStyle style, ColorScheme scheme) {
    if (text.isEmpty) return;
    const trailing = '.,!?;:)]}，。！？；：、）》】」』”’';
    final regexp = RegExp(r'https?://[^\s<>　]+', caseSensitive: false);
    var cursor = 0;
    for (final match in regexp.allMatches(text)) {
      if (match.start > cursor) spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
      final raw = match.group(0)!;
      var end = raw.length;
      while (end > 0 && trailing.contains(raw[end - 1])) end--;
      final href = raw.substring(0, end);
      spans.add(TextSpan(text: href, style: style.copyWith(color: scheme.primary, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => _openUrl(href)));
      if (end < raw.length) spans.add(TextSpan(text: raw.substring(end), style: style));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor), style: style));
  }

  Future<void> _openUrl(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    if (_isAttachmentLink(href) && onLinkTap != null) {
      onLinkTap!(href);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ListBlock extends StatelessWidget {
  final dom.Element element;
  final bool ordered;
  final ValueChanged<String>? onLinkTap;
  const _ListBlock({required this.element, required this.ordered, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final items = element.children.where((e) => e.localName?.toLowerCase() == 'li').where(_hasRenderableListItem).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    var index = 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [for (final child in items) _ListItemBlock(element: child, ordered: ordered, index: index++, onLinkTap: onLinkTap)],
      ),
    );
  }
}

class _ListItemBlock extends StatelessWidget {
  final dom.Element element;
  final bool ordered;
  final int index;
  final ValueChanged<String>? onLinkTap;
  const _ListItemBlock({required this.element, required this.ordered, required this.index, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final hasMedia = element.querySelector('img,video,iframe,audio,table,pre') != null;
    if (hasMedia && _visibleListText(element).isEmpty) {
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: _NodeList(nodes: element.nodes.where(_hasRenderableNode).toList(), onLinkTap: onLinkTap));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 28, child: Text(ordered ? '$index.' : '•')),
        Expanded(child: _TextBlock(nodes: element.nodes, onLinkTap: onLinkTap, padding: EdgeInsets.zero)),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;
  const _CodeBlock({required this.text});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.5), contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.editableText(editableTextState: state), selectionColor: c.primary.withValues(alpha: .22)),
    );
  }
}

class _ImageBlock extends StatelessWidget {
  final String src;
  final String? alt;
  final VoidCallback? onTap;
  const _ImageBlock({required this.src, this.alt, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return const SizedBox.shrink();
    final cookie = AuthService.instance.authCookie;
    final headers = <String, String>{
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Referer': SiteConfig.base,
    };
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        src,
        width: double.infinity,
        fit: BoxFit.contain,
        headers: headers,
        errorBuilder: (_, __, ___) => alt?.trim().isNotEmpty == true ? Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(alt!)) : const SizedBox.shrink(),
        loadingBuilder: (context, child, progress) => progress == null ? child : const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
    );
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: onTap == null ? image : GestureDetector(onTap: onTap, child: image));
  }
}

String _imageUrl(dom.Element element) {
  const keys = ['comiis_loadimages', 'data-src', 'data-original', 'data-url', 'lazy-src', 'original', 'zoomfile', 'file', 'src'];

  String normalize(String value, {bool forumPath = false}) {
    var v = value.trim();
    if (v.isEmpty || v.startsWith('data:')) return '';
    if (v.contains(',')) v = v.split(',').first.trim().split(RegExp(r'\s+')).first;
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    return forumPath ? SiteConfig.resolve(v) : SiteConfig.resolveCdn(v);
  }

  for (final key in keys) {
    final raw = element.attributes[key]?.trim() ?? '';
    if (raw.isEmpty) continue;
    final value = normalize(raw, forumPath: key == 'comiis_loadimages');
    if (value.isNotEmpty && !_placeholder(value)) return value;
  }
  final srcset = element.attributes['srcset'];
  if (srcset != null && srcset.trim().isNotEmpty) {
    final value = normalize(srcset);
    if (value.isNotEmpty && !_placeholder(value)) return value;
  }
  return '';
}

bool _placeholder(String url) {
  final v = url.toLowerCase();
  return v.contains('none.gif') || v.contains('none.png') || v.contains('loading.gif') || v.contains('lazyload') || v.contains('placeholder') || v.endsWith('/spacer.gif');
}

bool _isAttachmentLink(String href) {
  final v = href.toLowerCase();
  return v.contains('attachment.php') || v.contains('mod=attachment') || v.contains('aid=') || v.contains('noupdate=yes') || v.contains('/attachment/') || v.contains('/download/');
}
