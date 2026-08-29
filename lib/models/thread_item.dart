/// 帖子(主题)条目,来自导读 / 版块列表页的 `li.forumlist_li` 卡片。
class ThreadItem {
  final int tid;
  final String title;
  final String author; // 发布者昵称
  final String avatar; // 头像地址(可能为空字符串)
  final int fid; // 所属版块 fid
  final String boardName; // 版块名
  final String level; // 用户等级,如 Lv.4
  final String time; // 相对时间文本,如 "2 小时前"
  final String subtitle; // 摘要 / 付费提示等一行简介
  final String cover; // 缩略图地址(可能为空)
  final int likeCount; // 点赞
  final int replyCount; // 回复
  final int viewCount; // 浏览

  const ThreadItem({
    required this.tid,
    required this.title,
    required this.author,
    required this.avatar,
    required this.fid,
    required this.boardName,
    required this.level,
    required this.time,
    required this.subtitle,
    required this.cover,
    required this.likeCount,
    required this.replyCount,
    required this.viewCount,
  });

  String get url => 'https://www.ycoo.net/thread-$tid-1-1.html';
}