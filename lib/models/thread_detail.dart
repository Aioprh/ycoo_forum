import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// 帖子详情: 原生展示头部, 正文和评论分别交给 WebView 渲染。
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

  String get bodyHtml => _sanitizeForumHtml(_bodyHtml);
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
  /// 不能再用“清洗后的正文为空”判断付费状态，否则购买按钮会消失。
  final bool _paid;
  bool get isPaid => _paid;
  final int? price;
  final String currency;
  final String purchaseUrl;

  final int firstPid;
  final int likeCount;
  final bool likedByMe;

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
  })  : _bodyHtml = bodyHtml,
        _commentsHtml = commentsHtml,
        _paid = isPaid;
}

String _sanitizeForumHtml(String html) {
  if (html.trim().isEmpty) return '';
  final fragment = parser.parseFragment(html);

  bool removable(dom.Element e) {
    final attrs = '${e.localName ?? ''} ${e.attributes['id'] ?? ''} ${e.attributes['class'] ?? ''}'.toLowerCase();
    final style = (e.attributes['style'] ?? '').toLowerCase().replaceAll(' ', '');
    if (style.contains('display:none') || style.contains('visibility:hidden')) return true;
    if (RegExp(r'(^|[-_])(pay|paid|buy|purchase|locked|lock|price)([-_]|$)').hasMatch(attrs)) return true;
    final text = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.contains('本主题需向作者支付') || text.contains('购买后查看完整内容')) return true;
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
  return root.innerHtml.trim();
}