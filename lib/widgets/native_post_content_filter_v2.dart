import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'native_post_content_selectable.dart' as selectable;

/// 正文预处理：只移除真正的空列表，不吞掉 Comiis 图片结构。
///
/// 同时把 Discuz/Comiis 的“回帖奖励 +N 星币”从普通正文文本中提取出来，
/// 以独立的奖励条展示。这样原站的红包/回帖奖励不会再和用户正文挤在同一行。
class NativePostContent extends StatelessWidget {
  final String html;
  final ValueChanged<String>? onLinkTap;

  const NativePostContent({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final prepared = _preparePostHtml(html);
    final reward = _extractReplyReward(prepared);
    final content = reward.cleanedHtml;
    final colors = Theme.of(context).colorScheme;

    if (reward.label == null) {
      return selectable.NativePostContent(html: content, onLinkTap: onLinkTap);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFF5E7B2)),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            reward.label!,
            style: TextStyle(
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: colors.tertiary,
            ),
          ),
        ),
        if (content.trim().isNotEmpty)
          selectable.NativePostContent(html: content, onLinkTap: onLinkTap),
      ],
    );
  }
}

class _ReplyRewardParts {
  final String? label;
  final String cleanedHtml;

  const _ReplyRewardParts(this.label, this.cleanedHtml);
}

_ReplyRewardParts _extractReplyReward(String html) {
  if (html.trim().isEmpty) return const _ReplyRewardParts(null, '');

  final root = dom.Element.tag('div');
  root.append(parser.parseFragment(html));

  final rewardPattern = RegExp(
    r'^回帖奖励\s*([+＋-]?\s*\d+)\s*星币$',
  );
  String? label;

  // 优先移除完整的奖励块，例如 <div>回帖奖励 +2 星币</div>、
  // <p><span>回帖奖励</span><b>+2</b>星币</p>。只处理“自身文本就是
  // 奖励”的节点，避免误删用户正常正文。
  for (final element in root.querySelectorAll('*').toList().reversed) {
    final text = _compactText(element.text);
    final match = rewardPattern.firstMatch(text);
    if (match == null) continue;
    label ??= '回帖奖励 ${_normalizeRewardAmount(match.group(1)!)} 星币';
    element.remove();
  }

  // 某些 Discuz 模板会把奖励作为直接文本节点输出，补一次文本节点清理。
  for (final node in root.nodes.toList()) {
    if (node is! dom.Text) continue;
    final raw = node.text ?? '';
    final match = RegExp(
      r'回帖奖励\s*([+＋-]?\s*\d+)\s*星币',
    ).firstMatch(raw);
    if (match == null) continue;
    label ??= '回帖奖励 ${_normalizeRewardAmount(match.group(1)!)} 星币';
    final cleaned = raw.replaceFirst(match.group(0)!, '').trim();
    if (cleaned.isEmpty) {
      node.remove();
    } else {
      node.text = cleaned;
    }
  }

  return _ReplyRewardParts(label, root.innerHtml.trim());
}

String _compactText(String text) => text
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
    .trim();

String _normalizeRewardAmount(String raw) {
  final value = raw.replaceAll(RegExp(r'\s+'), '');
  if (value.startsWith('+') || value.startsWith('＋')) return '+${value.substring(1)}';
  return value;
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
