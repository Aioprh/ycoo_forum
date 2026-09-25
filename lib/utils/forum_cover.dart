import 'package:html/dom.dart';

import '../services/site_config.dart';

/// 取列表页帖子的预览缩略图(绝对地址)。
///
/// 站点在 `li.forumlist_li` 里用三种图组承载预览图, 类名不同:
///   - `.comiis_pyqlist_img`                          单图
///   - `.comiis_pyqlist_imgs .comiis_pyqlist_img2p`   双图
///   - `.comiis_pyqlist_imgs .comiis_pyqlist_img3p`   三图
/// 只按单图那个类名去取会漏掉全部多图帖子(列表里表现为没有缩略图),
/// 所以这里统一用类名前缀匹配, 最多取 [max] 张。
///
/// [fallbackToFirstImage] 为 true 时, 容器里没有图组就退回第一张图
/// —— 泛化解析那几条老路径一直这么取(拿到的通常是发帖人头像), 保留原行为。
List<String> forumCovers(
  dom.Element? node, {
  bool fallbackToFirstImage = false,
  int max = 3,
}) {
  if (node == null) return const <String>[];
  final covers = <String>[];
  for (final img in node.querySelectorAll('[class*="comiis_pyqlist_img"] img')) {
    final src = _abs(img.attributes['src'] ?? '');
    if (src.isEmpty || covers.contains(src)) continue;
    covers.add(src);
    if (covers.length >= max) break;
  }
  if (covers.isNotEmpty || !fallbackToFirstImage) return covers;
  final first = _abs(node.querySelector('img')?.attributes['src'] ?? '');
  return first.isEmpty ? const <String>[] : [first];
}

String _abs(String value) {
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('//')) return 'https:$value';
  final base = SiteConfig.base;
  if (value.startsWith('/')) return base + value.substring(1);
  return base + value.replaceFirst(RegExp(r'^\./'), '');
}