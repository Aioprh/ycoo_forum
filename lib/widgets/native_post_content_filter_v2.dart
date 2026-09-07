import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'native_post_content_selectable.dart' as selectable;

/// 正文预处理：只移除真正的空列表，不吞掉 Comiis 图片结构。
class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;

  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return selectable.NativePostContent(
      html: _preparePostHtml(html),
      onLinkTap: onLinkTap,
    );
  }
}

String _preparePostHtml(String html) {
  if (html.trim().isEmpty) return '';
  final fragment = parser.parseFragment(html);
  final root = dom.Element.tag('div');
  root.append(fragment);

  // Comiis 常见图片结构：
  // .comiis_img_list > li > span > img
  // 文字渲染器不能把 span/img 放进 TextSpan，因此只展开“纯图片包装层”。
  _flattenImageWrappers(root);
  _removeEmptyLists(root);

  return root.innerHtml.trim();
}

void _flattenImageWrappers(dom.Element root) {
  const wrappers = <String>{'span', 'font', 'b', 'strong', 'em', 'i'};
  bool changed;
  do {
    changed = false;
    for (final wrapper in root.querySelectorAll('span,font,b,strong,em,i').toList()) {
      final tag = (wrapper.localName ?? '').toLowerCase();
      if (!wrappers.contains(tag)) continue;
      final images = wrapper.querySelectorAll('img');
      if (images.length != 1) continue;

      // wrapper 里除了这一张图片外只能有空白文本，避免误伤正常富文本。
      final hasVisibleText = wrapper.nodes.any((node) {
        return node is dom.Text && (node.text ?? '').trim().isNotEmpty;
      });
      if (hasVisibleText) continue;

      final image = images.first;
      wrapper.replaceWith(image);
      changed = true;
    }
  } while (changed);
}

void _removeEmptyLists(dom.Element root) {
  bool changed;
  do {
    changed = false;

    for (final li in root.querySelectorAll('li').toList()) {
      final text = li.text
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
          .replaceAll(RegExp(r'^[•●○◦▪▫‣⁃∙·・\-–—*_.,。．、]+'), '')
          .replaceAll(RegExp(r'[•●○◦▪▫‣⁃∙·・]'), '')
          .trim();
      final media = li.querySelector('img,video,iframe,audio,table,pre') != null;
      final nestedList = li.querySelector('ul,ol') != null;
      if (text.isEmpty && !media && !nestedList) {
        li.remove();
        changed = true;
      }
    }

    for (final list in root.querySelectorAll('ul,ol').toList()) {
      if (list.querySelector('li') == null && list.text.trim().isEmpty) {
        list.remove();
        changed = true;
      }
    }
  } while (changed);
}
