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
  if (tag == 'img') return _isRealImage(node);
  if (tag == 'a' && node.querySelector('img') != null) {
    return _isRealImage(node.querySelector('img')!);
  }
  if (tag == 'ul' || tag == 'ol') {
    return node.children.any(_hasRenderableListItem);
  }
  if (tag == 'li') return _hasRenderableListItem(node);
  return true;
}

bool _hasRenderableListItem(dom.Element item) {
  final text = _visibleListText(item);
  if (text.isNotEmpty) return true;
  for (final media in item.querySelectorAll('img,video,iframe,audio,table,pre')) {
    final tag = (media.localName ?? '').toLowerCase();
    if (tag != 'img' || _isRealImage(media)) return true;
  }
  return false;
}

String _visibleListText(dom.Element element) {
  return element.text
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'^[•●○◦▪▫‣⁃∙·・\-–—*_.,。．、]+'), '')
      .replaceAll(RegExp(r'[•●○◦▪▫‣⁃∙·・]'), '')
      .trim();
}

bool _isRealImage(dom.Element image) {
  final raw = _rawImageValue(image);
  if (raw.isEmpty || _isPlaceholderImage(raw)) return false;

  final parent = image.parent;
  if (parent is dom.Element && (parent.localName ?? '').toLowerCase() == 'a') {
    final href = parent.attributes['href']?.trim() ?? '';
    final uri = Uri.tryParse(_resolveUrl(href));
    if (_isFileAttachment(uri) && !_isImageEndpoint(uri) && !_isImageFileName(uri)) {
      return false;
    }
  }
  return true;
}

String _rawImageValue(dom.Element image) {
  const keys = <String>[
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
  for (final key in keys) {
    final value = image.attributes[key]?.trim() ?? '';
    if (value.isNotEmpty && !value.startsWith('data:')) return value;
  }
  return image.attributes['srcset']?.trim() ?? '';
}

String _resolveUrl(String value) {
  var v = value.trim();
  if (v.isEmpty) return '';
  if (v.startsWith('//')) return 'https:$v';
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  return SiteConfig.resolve(v);
}

bool _isFileAttachment(Uri? uri) {
  if (uri == null) return false;
  final path = uri.path.toLowerCase();
  final query = uri.queryParameters;
  return path.endsWith('attachment.php') ||
      path.contains('/attachment/') ||
      query['mod']?.toLowerCase() == 'attachment' ||
      query.containsKey('aid');
}

bool _isImageEndpoint(Uri? uri) {
  if (uri == null) return false;
  final query = uri.queryParameters;
  return query['mod']?.toLowerCase() == 'image' ||
      query['action']?.toLowerCase() == 'image';
}

bool _isImageFileName(Uri? uri) {
  if (uri == null) return false;
  final value = '${uri.path} ${uri.queryParameters['filename'] ?? ''} ${uri.queryParameters['_f'] ?? ''}'.toLowerCase();
  return RegExp(r'\.(?:jpe?g|png|gif|webp|bmp|svg|heic|heif|avif)(?:$|[?#\s])').hasMatch(value);
}

bool _isPlaceholderImage(String value) {
  final v = value.toLowerCase();
  return v.contains('none.gif') ||
      v.contains('none.png') ||
      v.contains('loading.gif') ||
      v.contains('lazyload') ||
      v.contains('placeholder') ||
      v.contains('/filetype/') ||
      v.contains('/common/filetype/') ||
      v.contains('/icon_') ||
      v.endsWith('question.png');
}

class _NodeList extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;

  const _NodeList({required this.nodes, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final node in nodes)
          _NodeWidget(node: node, onLinkTap: onLinkTap),
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
      return _TextBlock(nodes: [node], onLinkTap: onLinkTap);
    }
    if (node is! dom.Element) return const SizedBox.shrink();

    final element = node as dom.Element;
    final tag = (element.localName ?? '').toLowerCase();

    switch (tag) {
      case 'br':
        return const SizedBox.shrink();
      case 'img':
        return _imageWidget(context, element, null);
      case 'a':
        final image = element.querySelector('img');
        if (image != null) {
          return _imageWidget(context, image, element);
        }
        return _TextBlock(nodes: element.nodes, onLinkTap: onLinkTap);
      case 'p':
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        if (element.querySelector('img') != null) {
          return _NodeList(
            nodes: element.nodes.where(_hasRenderableNode).toList(),
            onLinkTap: onLinkTap,
          );
        }
        final heading = tag.startsWith('h');
        final size = tag == 'h1'
            ? 24.0
            : tag == 'h2'
                ? 21.0
                : tag == 'h3'
                    ? 19.0
                    : 17.0;
        return _TextBlock(
          nodes: element.nodes,
          onLinkTap: onLinkTap,
          style: heading
              ? TextStyle(fontSize: size, height: 1.35, fontWeight: FontWeight.w800)
              : null,
          padding: heading
              ? const EdgeInsets.only(top: 6, bottom: 10)
              : const EdgeInsets.only(bottom: 9),
        );
      case 'ul':
      case 'ol':
        return _ListBlock(
          element: element,
          ordered: tag == 'ol',
          onLinkTap: onLinkTap,
        );
      case 'li':
        return _ListItemBlock(
          element: element,
          ordered: false,
          index: 1,
          onLinkTap: onLinkTap,
        );
      case 'blockquote':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: _NodeList(
            nodes: element.nodes.where(_hasRenderableNode).toList(),
            onLinkTap: onLinkTap,
          ),
        );
      case 'pre':
        return _CodeBlock(text: element.text);
      case 'hr':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1),
        );
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
          padding: const EdgeInsets.only(bottom: 8),
          child: _NodeList(
            nodes: element.nodes.where(_hasRenderableNode).toList(),
            onLinkTap: onLinkTap,
          ),
        );
      default:
        return _TextBlock(nodes: element.nodes, onLinkTap: onLinkTap);
    }
  }

  Widget _imageWidget(
    BuildContext context,
    dom.Element image,
    dom.Element? link,
  ) {
    if (!_isRealImage(image)) return const SizedBox.shrink();
    final src = _imageUrl(image);
    if (src.isEmpty) return const SizedBox.shrink();

    final href = link?.attributes['href']?.trim();
    VoidCallback? onTap;
    if (href != null && href.isNotEmpty) {
      onTap = () => _openLink(href);
    } else if (onLinkTap != null) {
      onTap = () => onLinkTap!(src);
    }

    return _ImageBlock(
      src: src,
      alt: image.attributes['alt'],
      onTap: onTap,
    );
  }

  Future<void> _openLink(String href) async {
    if (_isAttachmentLink(href) && onLinkTap != null) {
      onLinkTap!(href);
      return;
    }
    final uri = Uri.tryParse(_resolveUrl(href));
    if (uri == null) return;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _TextBlock extends StatelessWidget {
  final List<dom.Node> nodes;
  final ValueChanged<String>? onLinkTap;
  final TextStyle? style;
  final EdgeInsets padding;

  const _TextBlock({
    required this.nodes,
    this.onLinkTap,
    this.style,
    this.padding = const EdgeInsets.only(bottom: 9),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontSize: style?.fontSize ?? 16,
      height: style?.height ?? 1.62,
    );
    final spans = <InlineSpan>[];
    _appendNodes(spans, nodes, base, scheme);
    if (spans.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: SelectableText.rich(
        TextSpan(children: spans),
        selectionColor: scheme.primary.withValues(alpha: .22),
        contextMenuBuilder: (context, state) {
          return AdaptiveTextSelectionToolbar.editableText(
            editableTextState: state,
          );
        },
      ),
    );
  }

  void _appendNodes(
    List<InlineSpan> spans,
    List<dom.Node> source,
    TextStyle current,
    ColorScheme scheme,
  ) {
    for (final node in source) {
      _appendNode(spans, node, current, scheme);
    }
  }

  void _appendNode(
    List<InlineSpan> spans,
    dom.Node node,
    TextStyle current,
    ColorScheme scheme,
  ) {
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
    if (tag == 'strong' || tag == 'b') {
      next = current.copyWith(fontWeight: FontWeight.w800);
    } else if (tag == 'em' || tag == 'i') {
      next = current.copyWith(fontStyle: FontStyle.italic);
    } else if (tag == 'del' || tag == 's') {
      next = current.copyWith(decoration: TextDecoration.lineThrough);
    } else if (tag == 'code') {
      next = current.copyWith(
        fontFamily: 'monospace',
        backgroundColor: scheme.surfaceContainerHighest,
      );
    }

    if (tag == 'a') {
      if (node.querySelector('img') != null) return;
      final href = node.attributes['href']?.trim() ?? '';
      final uri = Uri.tryParse(_resolveUrl(href));
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        _appendNodes(spans, node.nodes, next, scheme);
        return;
      }
      spans.add(
        TextSpan(
          text: node.text,
          style: next.copyWith(
            color: scheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _openUrl(href),
        ),
      );
      return;
    }

    _appendNodes(spans, node.nodes, next, scheme);
  }

  void _appendTextWithLinks(
    List<InlineSpan> spans,
    String text,
    TextStyle current,
    ColorScheme scheme,
  ) {
    if (text.isEmpty) return;
    const trailing = '.,!?;:)]}，。！？；：、）》】」』”’';
    final regexp = RegExp(r'https?://[^\s<>　]+', caseSensitive: false);
    var cursor = 0;

    for (final match in regexp.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, match.start),
          style: current,
        ));
      }

      final raw = match.group(0)!;
      var end = raw.length;
      while (end > 0 && trailing.contains(raw[end - 1])) {
        end--;
      }
      final href = raw.substring(0, end);
      if (href.isNotEmpty) {
        spans.add(
          TextSpan(
            text: href,
            style: current.copyWith(
              color: scheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()..onTap = () => _openUrl(href),
          ),
        );
      }
      if (end < raw.length) {
        spans.add(TextSpan(
          text: raw.substring(end),
          style: current,
        ));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: current));
    }
  }

  Future<void> _openUrl(String href) async {
    if (_isAttachmentLink(href) && onLinkTap != null) {
      onLinkTap!(href);
      return;
    }
    final uri = Uri.tryParse(_resolveUrl(href));
    if (uri == null) return;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
        .where(_hasRenderableListItem)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    var index = 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            _ListItemBlock(
              element: item,
              ordered: ordered,
              index: index++,
              onLinkTap: onLinkTap,
            ),
        ],
      ),
    );
  }
}

class _ListItemBlock extends StatelessWidget {
  final dom.Element element;
  final bool ordered;
  final int index;
  final ValueChanged<String>? onLinkTap;

  const _ListItemBlock({
    required this.element,
    required this.ordered,
    required this.index,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasMedia = element.querySelector('img,video,iframe,audio,table,pre') != null;
    if (hasMedia && _visibleListText(element).isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _NodeList(
          nodes: element.nodes.where(_hasRenderableNode).toList(),
          onLinkTap: onLinkTap,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 28, child: Text(ordered ? '$index.' : '•')),
        Expanded(
          child: _TextBlock(
            nodes: element.nodes,
            onLinkTap: onLinkTap,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;

  const _CodeBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
        ),
        selectionColor: scheme.primary.withValues(alpha: .22),
        contextMenuBuilder: (context, state) {
          return AdaptiveTextSelectionToolbar.editableText(
            editableTextState: state,
          );
        },
      ),
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
        errorBuilder: (context, error, stackTrace) {
          if (alt != null && alt!.trim().isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(alt!),
            );
          }
          return const SizedBox.shrink();
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: onTap == null
          ? image
          : GestureDetector(onTap: onTap, child: image),
    );
  }
}

String _imageUrl(dom.Element element) {
  const keys = <String>[
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

  for (final key in keys) {
    final raw = element.attributes[key]?.trim() ?? '';
    if (raw.isEmpty || raw.startsWith('data:')) continue;

    var value = raw;
    if (value.contains(',')) {
      value = value.split(',').first.trim().split(RegExp(r'\s+')).first;
    }
    final url = key == 'comiis_loadimages'
        ? _resolveUrl(value)
        : _resolveUrl(value);
    if (url.isNotEmpty && !_isPlaceholderImage(url)) return url;
  }

  final srcset = element.attributes['srcset']?.trim() ?? '';
  if (srcset.isNotEmpty) {
    final url = _resolveUrl(srcset.split(',').first.trim().split(RegExp(r'\s+')).first);
    if (url.isNotEmpty && !_isPlaceholderImage(url)) return url;
  }
  return '';
}

bool _isAttachmentLink(String href) {
  final v = href.toLowerCase();
  return v.contains('attachment.php') ||
      v.contains('mod=attachment') ||
      v.contains('aid=') ||
      v.contains('noupdate=yes') ||
      v.contains('/attachment/') ||
      v.contains('/download/');
}
