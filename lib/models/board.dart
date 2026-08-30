/// 一个子版块(登录论坛里的一个小分区),如「精品软件」。
class ForumBoard {
  final int fid;
  final String name;
  final String icon; // 图标地址
  final String today; // "今日: 22" 等
  const ForumBoard({
    required this.fid,
    required this.name,
    required this.icon,
    required this.today,
  });
}

/// 版块分类,如「网络资源」,内含若干子版块。
class ForumCategory {
  final String name;
  final List<ForumBoard> boards;
  const ForumCategory({required this.name, required this.boards});
}