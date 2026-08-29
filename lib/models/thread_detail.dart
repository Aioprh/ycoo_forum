/// 帖子详情:原生展示头部,正文 HTML 交给 WebView 渲染。
class ThreadDetail {
  final int tid;
  final String title;
  final String author;
  final String avatar;
  final String level;
  final String time;
  final int fid;
  final String boardName;
  final String bodyHtml;

  /// 主题是否存在站点的付费/购买限制。
  final bool isPaid;
  /// 解析到的购买价格;未解析到时为 null。
  final int? price;
  final String currency;
  /// 原站购买页面/主题页面,用于在共享 WebView 会话中完成购买。
  final String purchaseUrl;

  /// 首楼帖子 id,点赞(recommend)接口需要。
  final int firstPid;
  /// 点赞数。
  final int likeCount;
  /// 当前登录用户是否已点赞首楼。
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
    this.isPaid = false,
    this.price,
    this.currency = '星币',
    this.purchaseUrl = '',
    this.firstPid = 0,
    this.likeCount = 0,
    this.likedByMe = false,
  });
}