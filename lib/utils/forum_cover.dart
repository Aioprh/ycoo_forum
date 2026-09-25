import 'package:html/dom.dart' as dom;

import '../services/site_config.dart';

/// 列表图片的缩略图 + 原图地址。
class ForumCover {
  final String thumbnail;
  final String original;

  const ForumCover({required this.thumbnail, required this.original});
}

/// 解析帖子列表中的图片。
///
/// img.src 通常是论坛生成的缩略图；外层 a.href 或 data-original/data-src/
/// zoomfile 等字段才可能指向原图。两者必须分开保存。
List<ForumCover> forumCoverSources(dom.Element? node, {
  bool fallbackToFirstImage = false,
  int max = 3,
}) {
  if (node == null) return const <ForumCover>[];

  final result = <ForumCover>[];
  for (final img in node.querySelectorAll('[class*="comiis_pyqlist_img"] img')) {
    final thumbnail = _abs(img.attributes['src'] ?? '');
    if (thumbnail.isEmpty || result.any((e) => e.thumbnail == thumbnail)) continue;
    final original = _findOriginal(img, thumbnail);
    result.add(ForumCover(
      thumbnail: thumbnail,
      original: original.isEmpty ? thumbnail : original,
    ));
    if (result.length >= max) break;
  }

  if (result.isNotEmpty || !fallbackToFirstImage) return result;
  final img = node.querySelector('img');
  final thumbnail = _abs(img?.attributes['src'] ?? '');
  if (thumbnail.isEmpty) return const <ForumCover>[];
  final original = _findOriginal(img!, thumbnail);
  return [ForumCover(
    thumbnail: thumbnail,
    original: original.isEmpty ? thumbnail : original,
  )];
}

/// 兼容旧调用方，只返回缩略图。
List<String> forumCovers(dom.Element? node, {
  bool fallbackToFirstImage = false,
  int max = 3,
}) => forumCoverSources(
  node,
  fallbackToFirstImage: fallbackToFirstImage,
  max: max,
).map((e) => e.thumbnail).toList(growable: false);

String _findOriginal(dom.Element img, String thumbnail) {
  const attrs = ['data-original', 'data-src', 'data-url', 'zoomfile', 'comiis_loadimages'];
  for (final key in attrs) {
    final value = _abs(img.attributes[key] ?? '');
    if (_isUsableOriginal(value, thumbnail)) return value;
  }

  // Comiis 常见结构：<a href="原图"><img src="缩略图"></a>
  final anchor = img.parent;
  if (anchor != null && anchor.localName == 'a') {
    final href = _abs(anchor.attributes['href'] ?? '');
    if (_isUsableOriginal(href, thumbnail)) return href;
  }
  return '';
}

bool _isUsableOriginal(String value, String thumbnail) {
  if (value.isEmpty || value == thumbnail) return false;
  final lower = value.toLowerCase();
  if (lower.startsWith('javascript:') || lower == '#') return false;
  // 避免把包住图片的帖子链接误认为原图。
  if (lower.contains('thread-') || lower.contains('mod=viewthread') || lower.endsWith('.html')) {
    return false;
  }
  return true;
}

String _abs(String value) {
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('//')) return 'https:$value';
  final base = SiteConfig.base;
  if (value.startsWith('/')) return base + value.substring(1);
  return base + value.replaceFirst(RegExp(r'^\./'), '');
}
