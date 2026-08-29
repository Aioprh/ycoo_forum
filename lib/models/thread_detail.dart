/// 帖子详情:原生展示头部信息,正文 HTML 交给 WebView 渲染。
class ThreadDetail {
  final int tid;
  final String title;
  final String author;
  final String avatar;
  final String level;
  final String time;
  final int fid;
  final String boardName;

  /// 「comiis_message_table」正文的原文 HTML(含 <br>/<img>/<a> 等)。
  final String bodyHtml;

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
  });
}