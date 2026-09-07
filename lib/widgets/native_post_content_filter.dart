import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'native_post_content_selectable.dart' as selectable;

/// 在进入原生正文渲染器前清理论坛模板产生的空列表。
/// 仅移除真正没有可见文字/媒体内容的 li，保留正常列表、链接和图片。
class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;

  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return selectable.NativePostContent(
      html: _removeEmptyLists(html),
      onLinkTap: onLinkTap,
    );
  }
}

String _removeEmptyLists(String html) {
  if (html.trim().isEmpty) return '';
  final root = dom.Element.html('<div>${parser.parseFragment(html).outerHtml}</div>');

  // 反复清理，处理 ul/ol -> li -> ul/ol 这类嵌套空列表。
  bool changed;
  do {
    changed = false;
    for (final li in root.querySelectorAll('li').toList()) {
      final text = li.text.replaceAll(RegExp(r'\s+'), '').trim();
      final rich = li.querySelector('img,video,iframe,audio,table,pre,code') != null;
      final nestedList = li.querySelector('ul,ol') != null;
      if (text.isEmpty && !rich && !nestedList) {
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

  return root.innerHtml.trim();
}
