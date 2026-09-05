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

/// 版块内的主题分类筛选标签(如「综合」「音源」「漫画」)。
///
/// 对应网页端版块页顶部滑动栏里 `filter=typeid&typeid=X` 的链接。
class ForumTypeTag {
  final int typeid;
  final String name;
  const ForumTypeTag({required this.typeid, required this.name});
}