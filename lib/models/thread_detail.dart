import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// 帖子详情: 原生展示头部, 正文和评论分别交给 Flutter 渲染。
class ThreadDetail {
  final int tid;
  final String title;
  String author;
  String avatar;
  String level;
  final String time;
  final int fid;
  final String boardName;

  String _bodyHtml;
  final String _commentsHtml;

  String get bodyHtml => _sanitizeForumHtml(_bodyHtml);

  String get commentsHtml {
    final sanitized = _sanitizeForumHtml(_commentsHtml);
    if (sanitized.trim().isEmpty) return '';
    final compacted = _compactCommentHtml(sanitized);
    if (compacted.trim().isEmpty) return '';
    if (compacted.contains('class="comments-section"')) {
      return compacted.replaceFirst(
        'class="comments-section"',
        'class="comments-section" data-tid="$tid" data-fid="$fid"',
      );
    }
    return '<div class="comments-section" data-tid="$tid" data-fid="$fid">$compacted</div>';
  }

  final bool _paid;
  bool get isPaid => _paid;
  final int? price;
  final String currency;
  final String purchaseUrl;

  final int firstPid;
  final int likeCount;
  final bool likedByMe;
  final int commentPage;
  final int commentTotalPages;
  int authorUid;

  static final Map<int, ThreadDetail> _firstPageCache = <int, ThreadDetail>{};

  ThreadDetail({
    required this.tid,
    required this.title,
    required String bodyHtml,
    required String author,
    required String avatar,
    required String level,
    required this.time,
    required this.fid,
    required this.boardName,
    String commentsHtml = '',
    bool isPaid = false,
    this.price,
    this.currency = '星币',
    this.purchaseUrl = '',
    this.firstPid = 0,
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentPage = 1,
    this.commentTotalPages = 1,
    int authorUid = 0,
  })  : _bodyHtml = bodyHtml,
        author = author,
        avatar = avatar,
        level = level,
        _commentsHtml = commentsHtml,
        this.authorUid = authorUid,
        _paid = isPaid {
    // Discuz 评论分页第 2 页开始通常只包含回帖。
    // 楼主信息和正文必须沿用第 1 页，不能被当前页第一条回复覆盖。
    if (commentPage <= 1) {
      _firstPageCache[tid] = this;
    } else {
      final firstPage = _firstPageCache[tid];
      if (firstPage != null) {
        this.author = firstPage.author;
        this.avatar = firstPage.avatar;
        this.level = firstPage.level;
        _bodyHtml = firstPage._bodyHtml;
        this.authorUid = firstPage.authorUid;
      }
    }
  }
}

/// 评论正文只保留内容附近的一点留白，避免论坛模板中的连续换行占位
/// 把一条很短的评论撑成大块空白。
String _compactCommentHtml(String html) {
  final root = dom.Element.html('<div>$html</div>');

  for (final body in root.querySelectorAll('.p-body').toList()) {
    var previousWasBreak = false;
    for (final node in List<dom.Node>.from(body.nodes)) {
      if (node is dom.Element && node.localName?.toLowerCase() == 'br') {
        if (previousWasBreak) {
          node.remove();
        } else {
          previousWasBreak = true;
        }
      } else if (node is dom.Text) {
        previousWasBreak = node.text?.trim().isEmpty == true;
      } else {
        previousWasBreak = false;
      }
    }

    for (final e in body.querySelectorAll('p, div, section, article').toList()) {
      final hasMedia = e.querySelector('img,video,iframe,audio,table,pre') != null;
      if (e.text.trim().isEmpty && !hasMedia) e.remove();
    }

    while (body.nodes.isNotEmpty && _isEmptyBreakNode(body.nodes.first)) {
      body.nodes.first.remove();
    }
    while (body.nodes.isNotEmpty && _isEmptyBreakNode(body.nodes.last)) {
      body.nodes.last.remove();
    }
  }

  return root.innerHtml.trim();
}

bool _isEmptyBreakNode(dom.Node node) {
  if (node is dom.Element) return node.localName?.toLowerCase() == 'br';
  if (node is dom.Text) return node.text?.trim().isEmpty == true;
  return false;
}

String _sanitizeForumHtml(String html) {
  if (html.trim().isEmpty) return '';
  final fragment = parser.parseFragment(html);

  bool removable(dom.Element e) {
    final tag = e.localName ?? '';
    final attrs = '$tag ${e.attributes['id'] ?? ''} ${e.attributes['class'] ?? ''}'.toLowerCase();
    final style = (e.attributes['style'] ?? '').toLowerCase().replaceAll(' ', '');
    if (style.contains('display:none') || style.contains('visibility:hidden')) return true;
    if (RegExp(r'(^|[-_])(pay|paid|buy|purchase|locked|lock|price)([-_]|$)').hasMatch(attrs)) return true;
    final text = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.contains('本主题需向作者支付') || text.contains('购买后查看完整内容')) return true;
    final iconOnly = (tag == 'i' || tag == 'span' || tag == 'em' || tag == 'b' || tag == 'font') &&
        text.isNotEmpty &&
        text.replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').isEmpty;
    if (iconOnly) return true;
    return false;
  }

  bool emptyLayoutNode(dom.Element e) {
    final tag = (e.localName ?? '').toLowerCase();
    const layoutTags = {
      'p', 'div', 'section', 'article', 'main', 'figure', 'figcaption',
      'dl', 'dt', 'dd', 'blockquote', 'center',
    };
    if (!layoutTags.contains(tag)) return false;
    if (e.text.trim().isNotEmpty) return false;
    return e.querySelector('img,video,iframe,audio,table,pre,a,code') == null;
  }

  void walk(dom.Element e) {
    final children = List<dom.Element>.from(e.children);
    for (final child in children) {
      if (removable(child) || emptyLayoutNode(child)) {
        child.remove();
      } else {
        walk(child);
        // 清理掉子节点清理后留下的空布局容器。
        if (emptyLayoutNode(child)) child.remove();
      }
    }
  }

  final root = dom.Element.tag('div');
  root.append(fragment);
  walk(root);

  final text = root.text.replaceAll(RegExp(r'\s+'), '').trim();
  final hasMedia = root.querySelector('img,video,iframe,audio,table,pre') != null;
  if (text.isEmpty && !hasMedia) return '';
  return _stripTofu(root.innerHtml).trim();
}

bool _isTofuCodePoint(int cp) {
  if (cp == 0xFFFD) return true;
  if (cp == 0xFEFF) return true;
  if (cp >= 0xE000 && cp <= 0xF8FF) return true;
  if (cp >= 0xF0000 && cp <= 0xFFFFD) return true;
  if (cp >= 0x100000 && cp <= 0x10FFFD) return true;
  if (cp <= 0x8 || cp == 0xB || cp == 0xC || (cp >= 0xE && cp <= 0x1F)) return true;
  return false;
}

String _stripTofu(String value) {
  final out = StringBuffer();
  for (final codePoint in value.runes) {
    if (!_isTofuCodePoint(codePoint)) out.writeCharCode(codePoint);
  }
  return out.toString();
}