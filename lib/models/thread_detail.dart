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

  /// 首楼正文。
  final String bodyHtml;
  /// 后续评论/回复楼层。
  final String commentsHtml;

  /// 主题是否存在站点的付费/购买限制。
  ///
  /// 已购买的付费主题通常仍可能在原站 HTML 中保留“购买主题”相关节点，
  /// 因此 UI 层应以是否已经拿到正文为最终判断依据。
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
    required this.bodyHtml,
    this.commentsHtml = '',
    bool isPaid = false,
    this.price,
    this.currency = '星币',
    this.purchaseUrl = '',
    this.firstPid = 0,
    this.likeCount = 0,
    this.likedByMe = false,
  }) : _paid = isPaid;
}