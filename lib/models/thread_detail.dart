import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// 帖子详情: 原生展示头部, 正文和评论分别交给 Flutter 渲染。
class ThreadDetail {
  final int tid;
  final String title;
  final String author;
  final String avatar;
  final String level;
  final String time;
  final int fid;
  final String boardName;

  final String _bodyHtml;
  final String _commentsHtml;

  String get bodyHtml {
    final sanitized = _sanitizeForumHtml(_bodyHtml);
    if (tid <= 0) return sanitized;
    // Discuz 的附件块经常位于正文容器之外，直接取正文 HTML 会把它漏掉。
    // 这里增加一个内部附件入口，由 AttachmentDownloadService 用当前 Cookie
    // 重新读取帖子并解析真实 attachment.php/aid= 地址，再交给系统下载器。
    final marker = '<div class="ycoo-attachment-entry"><a href="attachment.php?tid=$tid&ycoo=all">📎 查看并下载本帖全部附件</a></div>';
    if (sanitized.contains('ycoo-attachment-entry')) return sanitized;
    return sanitized.isEmpty ? marker : '$sanitized$marker';
  }

  String get commentsHtml {
    final sanitized = _sanitizeForumHtml(_commentsHtml);
    if (sanitized.trim().isEmpty) return '';
    if (sanitized.contains('class="comments-section"')) {
      return sanitized.replaceFirst(
        'class="comments-section"',
        'class="comments-section" data-tid="$tid" data-fid="$fid"',
      );
    }
    return '<div class="comments-section" data-tid="$tid" data-fid="$fid">$sanitized</div>';
  }

  /// Discuz 付费主题可能仍提供一部分免费预览内容。
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
  final int authorUid;

  ThreadDetail({
    required this.tid,
    required this.title,
    required this.author,
    required this.avatar,
    required this.level,
    required this.time,
    required this.fid,
    required this.boardName,
    required String bodyHtml,
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
    this.authorUid = 0,
  })  : _bodyHtml = bodyHtml,
        _commentsHtml = commentsHtml,
        _paid = isPaid;
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
    // Discuz 网页图标字体(<i class="comiis_font">&#xe679;</i>): 内容只有私有区(PUA)字形,
    // 无配套字体时会被渲染成方块乱码, 当作装饰图标整体移除。
    final iconOnly = (tag == 'i' || tag == 'span' || tag == 'em' || tag == 'b' || tag == 'font') &&
        text.isNotEmpty &&
        text.replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').isEmpty;
    if (iconOnly) return true;
    return false;
  }

  void walk(dom.Element e) {
    final children = List<dom.Element>.from(e.children);
    for (final child in children) {
      if (removable(child)) {
        child.remove();
      } else {
        walk(child);
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
