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
  String get commentsHtml => _sanitizeForumHtml(_commentsHtml);

  /// 已购买的付费主题可能仍残留“购买主题”节点，因此只在没有正文时显示购买 UI。
  final bool _paid;
  bool get isPaid => _paid && bodyHtml.trim().isEmpty;
  final int? price;
  final String currency;
  final String purchaseUrl;

  final int firstPid;
  final int likeCount;
  final bool likedByMe;

  const ThreadDetail({
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