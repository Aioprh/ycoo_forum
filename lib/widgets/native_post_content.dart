import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../services/auth_service.dart';
import '../services/site_config.dart';
import 'forum_attachment_section.dart';

/// Native Flutter renderer for forum post HTML.
/// Supports HTML links, bare http/https URLs, lazy images and attachments.
class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;

  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final body = html_parser.parse(html).body;
    if (body == null) return const SizedBox.shrink();
    return SelectionArea(child: _NodeList(nodes: body.nodes, onLinkTap: onLinkTap));
  }
}

class _NodeList extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;
  const _NodeList({required this.nodes, this.onLinkTap});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final n in nodes) _NodeWidget(node: n, onLinkTap: onLinkTap)],
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
      return text.trim().isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _LinkifiedText(
                text: text,
                style: const TextStyle(fontSize: 16, height: 1.62),
                onLinkTap: onLinkTap,
              ),
            );
    }
    if (node is! dom.Element) return const SizedBox.shrink();
    final e = node as dom.Element;
    final tag = (e.localName ?? '').toLowerCase();
    switch (tag) {
      case 'br': return const SizedBox(height: 6);
      case 'p':
      case 'div':
      case 'section':
      case 'article':
      case 'main':
      case 'figure':
      case 'figcaption':
      case 'dl':
      case 'dt':
      case 'dd':
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: _NodeList(nodes: e.nodes, onLinkTap: onLinkTap));
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final size = {'h1': 24.0, 'h2': 21.0, 'h3': 19.0}[tag] ?? 17.0;
        return Padding(
          padding: const EdgeInsets.only(top: 7, bottom: 10),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: size, height: 1.35, fontWeight: FontWeight.w800),
            child: _InlineContent(e.nodes, onLinkTap: onLinkTap),
          ),
        );
      case 'blockquote':
        return _Quote(nodes: e.nodes, onLinkTap: onLinkTap);
      case 'ul':
      case 'ol':
        return _ListBlock(element: e, ordered: tag == 'ol', onLinkTap: onLinkTap);
      case 'pre': return _CodeBlock(text: e.text);
      case 'code': return _InlineCode(text: e.text);
      case 'img':
        final src = _imageUrl(e);
        return src.isEmpty ? const SizedBox.shrink() : _ImageBlock(src: src, alt: e.attributes['alt'], onTap: onLinkTap == null ? null : () => onLinkTap!(src));
      case 'hr': return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1));
      case 'table': return _TableBlock(element: e, onLinkTap: onLinkTap);
      default: return _InlineContent(e.nodes, onLinkTap: onLinkTap);
    }
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
    final scheme = Theme.of(context).colorScheme;

    void flush() {
      if (spans.isEmpty) return;
      children.add(Text.rich(TextSpan(children: List<InlineSpan>.from(spans))));
      spans.clear();
    }

    for (final node in nodes) {
      if (node is dom.Element) {
        final tag = (node.localName ?? '').toLowerCase();
        if (tag == 'a' && _isAttachmentLink(node.attributes['href'])) {
          flush();
          final href = _normalizeLink(node.attributes['href'] ?? '');
          children.add(_AttachmentCard(
            href: href,
            title: node.text.trim(),
            onTap: onLinkTap == null ? null : () => onLinkTap!(href),
          ));
          continue;
        }
        if (tag == 'img') {
          flush();
          final src = _imageUrl(node);
          if (src.isNotEmpty) children.add(_ImageBlock(src: src, alt: node.attributes['alt'], onTap: onLinkTap == null ? null : () => onLinkTap!(src)));
          continue;
        }
      }
      _appendSpan(spans, node, const TextStyle(fontSize: 16, height: 1.62), scheme);
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  void _appendSpan(List<InlineSpan> spans, dom.Node node, TextStyle style, ColorScheme scheme) {
    if (node is dom.Text) {
      final text = node.text ?? '';
      if (text.isNotEmpty) spans.addAll(_linkSpans(text, style, onLinkTap, scheme));
      return;
    }
    if (node is! dom.Element) return;
    final e = node as dom.Element;
    final tag = (e.localName ?? '').toLowerCase();
    if (tag == 'img') return;
    if (tag == 'a') {
      final href = _normalizeLink(e.attributes['href'] ?? '');
      spans.add(TextSpan(
        text: e.text,
        style: style.copyWith(color: scheme.primary, decoration: TextDecoration.underline),
        recognizer: onLinkTap == null ? null : (TapGestureRecognizer()..onTap = () => onLinkTap!(href)),
      ));
      return;
    }
    var next = style;
    if (tag == 'strong' || tag == 'b') next = next.copyWith(fontWeight: FontWeight.w800);
    if (tag == 'em' || tag == 'i') next = next.copyWith(fontStyle: FontStyle.italic);
    if (tag == 'del' || tag == 's') next = next.copyWith(decoration: TextDecoration.lineThrough);
    if (tag == 'code') next = next.copyWith(fontFamily: 'monospace', backgroundColor: scheme.surfaceContainerHighest);
    if (tag == 'br') { spans.add(const TextSpan(text: '\n')); return; }
    for (final child in e.nodes) _appendSpan(spans, child, next, scheme);
  }
}

class _LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final ValueChanged<String>? onLinkTap;
  const _LinkifiedText({required this.text, required this.style, this.onLinkTap});

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: _linkSpans(text, style, onLinkTap, Theme.of(context).colorScheme)));
}

List<InlineSpan> _linkSpans(String text, TextStyle style, ValueChanged<String>? onLinkTap, ColorScheme scheme) {
  final result = <InlineSpan>[];
  final re = RegExp(r'(?:(?:https?|ftp)://|www\.)[^\s<>()\[\]{}"\u3001\u3002]+', caseSensitive: false);
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) result.add(TextSpan(text: text.substring(last, m.start), style: style));
    var raw = m.group(0)!;
    var trailing = '';
    while (raw.isNotEmpty && RegExp(r'[.,!?;:，。！？；：）】》、]').hasMatch(raw[raw.length - 1])) {
      trailing = raw[raw.length - 1] + trailing;
      raw = raw.substring(0, raw.length - 1);
    }
    final url = raw.startsWith('www.') ? 'https://$raw' : raw;
    result.add(TextSpan(
      text: raw,
      style: style.copyWith(color: scheme.primary, decoration: TextDecoration.underline),
      recognizer: onLinkTap == null ? null : (TapGestureRecognizer()..onTap = () => onLinkTap(url)),
    ));
    if (trailing.isNotEmpty) result.add(TextSpan(text: trailing, style: style));
    last = m.end;
  }
  if (last < text.length) result.add(TextSpan(text: text.substring(last), style: style));
  return result;
}

String _normalizeLink(String raw) {
  var value = raw.trim().replaceAll('&amp;', '&');
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  return SiteConfig.resolve(value);
}

String _imageUrl(dom.Element e) {
  const keys = ['comiis_loadimages','data-src','data-original','data-url','lazy-src','original','zoomfile','file','src'];
  for (final key in keys) {
    final raw = e.attributes[key]?.trim() ?? '';
    if (raw.isEmpty || raw.startsWith('data:')) continue;
    final value = raw.startsWith('//') ? 'https:$raw' : (raw.startsWith('http://') || raw.startsWith('https://') ? raw : (key == 'comiis_loadimages' ? SiteConfig.resolve(raw) : SiteConfig.resolveCdn(raw)));
    if (!_looksLikePlaceholder(value)) return value;
  }
  return '';
}

bool _looksLikePlaceholder(String url) {
  final v = url.toLowerCase();
  return v.contains('none.gif') || v.contains('none.png') || v.contains('loading.gif') || v.contains('lazyload') || v.contains('placeholder') || v.endsWith('/spacer.gif');
}

bool _isAttachmentLink(String? href) {
  if (href == null || href.trim().isEmpty) return false;
  final u = href.toLowerCase();
  return u.contains('attachment.php') || u.contains('mod=attachment') || u.contains('aid=') || u.contains('noupdate=yes') || u.contains('/attachment/') || u.contains('/download/') || u.contains('ycoo=all');
}

class _ImageBlock extends StatelessWidget {
  final String src;
  final String? alt;
  final VoidCallback? onTap;
  const _ImageBlock({required this.src, this.alt, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cookie = AuthService.instance.authCookie;
    final headers = <String,String>{'Accept':'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8','Referer':SiteConfig.base};
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(src, width: double.infinity, fit: BoxFit.contain, headers: headers,
        errorBuilder: (_, __, ___) => Container(padding: const EdgeInsets.all(14), color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Text(alt?.isNotEmpty == true ? alt! : '图片加载失败\n$src')),
      ),
    );
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: onTap == null ? image : GestureDetector(onTap: onTap, child: image));
  }
}

class _Quote extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;
  const _Quote({required this.nodes, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.fromLTRB(14,11,14,2),
      decoration: BoxDecoration(color: c.primaryContainer.withValues(alpha:.34), borderRadius: const BorderRadius.only(topRight: Radius.circular(14),bottomRight: Radius.circular(14)), border: Border(left: BorderSide(color:c.primary,width:3))),
      child: _NodeList(nodes:nodes,onLinkTap:onLinkTap),
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
      padding: const EdgeInsets.only(bottom:10),
      child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        for (var i=0;i<items.length;i++) Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:25,child:Text(ordered?'${i+1}.':'•')),
          Expanded(child:_InlineContent(items[i].nodes,onLinkTap:onLinkTap)),
        ]),
      ]),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;
  const _CodeBlock({required this.text});
  @override
  Widget build(BuildContext context) => Container(width:double.infinity,margin:const EdgeInsets.only(bottom:13),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(14)),child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:SelectableText(text,style:const TextStyle(fontFamily:'monospace',fontSize:13.5))));
}

class _InlineCode extends StatelessWidget {
  final String text;
  const _InlineCode({required this.text});
  @override
  Widget build(BuildContext context) => Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(6)),child:Text(text,style:const TextStyle(fontFamily:'monospace',fontSize:14)));
}

class _TableBlock extends StatelessWidget {
  final dom.Element element;
  final ValueChanged<String>? onLinkTap;
  const _TableBlock({required this.element, this.onLinkTap});
  @override
  Widget build(BuildContext context) {
    final rows = element.querySelectorAll('tr');
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(padding:const EdgeInsets.only(bottom:13),child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Table(border:TableBorder.all(color:Theme.of(context).colorScheme.outlineVariant),defaultColumnWidth:const IntrinsicColumnWidth(),children:[
      for(final row in rows) TableRow(children:[for(final cell in row.children.where((e)=>e.localName=='td'||e.localName=='th')) Padding(padding:const EdgeInsets.all(8),child:_InlineContent(cell.nodes,onLinkTap:onLinkTap))])
    ])));
  }
}

/// Attachment card: tap to download, or copy the exact URL for external use.
class _AttachmentCard extends StatelessWidget {
  final String href;
  final String title;
  final VoidCallback? onTap;
  const _AttachmentCard({required this.href, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    final lower = href.toLowerCase();
    if (lower.contains('ycoo=all')) {
      final uri = Uri.tryParse(href);
      final tid = int.tryParse(uri?.queryParameters['tid'] ?? '') ?? 0;
      if (tid > 0) return ForumAttachmentSection(tid:tid,cookie:AuthService.instance.authCookie,referer:SiteConfig.base);
    }
    final c = Theme.of(context).colorScheme;
    final label = title.isNotEmpty ? title : '下载附件';

    Future<void> copyLink() async {
      await Clipboard.setData(ClipboardData(text: href));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('附件下载链接已复制')));
    }

    return Padding(
      padding:const EdgeInsets.only(bottom:13),
      child:Material(
        color:c.secondaryContainer.withValues(alpha:.45),
        borderRadius:BorderRadius.circular(12),
        child:InkWell(
          borderRadius:BorderRadius.circular(12),
          onTap:onTap,
          child:Padding(
            padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
            child:Row(children:[
              Icon(Icons.attach_file_rounded,color:c.primary,size:24),
              const SizedBox(width:12),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(label,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:14.5,height:1.3)),
                const SizedBox(height:3),
                Text(href,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11,color:c.onSurfaceVariant)),
              ])),
              IconButton(tooltip:'复制下载链接',onPressed:copyLink,icon:const Icon(Icons.link_rounded)),
              Icon(Icons.download_rounded,color:c.primary,size:20),
            ]),
          ),
        ),
      ),
    );
  }
}
