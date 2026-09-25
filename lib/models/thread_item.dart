import '../services/site_config.dart';

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
  final List<String> covers; // 列表展示用缩略图, 0~3 张(来自列表页的 pyqlist 图组)
  final List<String> fullCovers; // 点击查看用原图地址, 与 covers 按索引对应
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
    required this.covers,
    this.fullCovers = const <String>[],
    required this.likeCount,
    required this.replyCount,
    required this.viewCount,
  });

  String get url => '${SiteConfig.base}thread-$tid-1-1.html';
}