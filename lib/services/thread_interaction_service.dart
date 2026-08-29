import 'package:html/parser.dart' as parser;

import '../models/thread_detail.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 帖子详情页互动状态。
class ThreadInteractionState {
  final int likeCount;
  final bool likedByMe;
  final bool favorited;
  const ThreadInteractionState({
    this.likeCount = 0,
    this.likedByMe = false,
    this.favorited = false,
  });
}

/// 详情页「点赞 / 收藏」的原生接口，对齐 Discuz 标准端点。
///
/// 点赞使用 misc.recommend，收藏使用 spacecp.favorite；两者都需要当前
/// 登录会话的 formhash 令牌。全部接口均为标准 Discuz X 端点，与网页版
/// comiis 模板按钮底层一致，而非仅只读展示。
class ThreadInteractionService {
  ThreadInteractionService._();
  static final instance = ThreadInteractionService._();
  static const _base = 'https://www.ycoo.net/';

  bool get _loggedIn =>
      AuthService.instance.isLoggedIn && (AuthService.instance.authCookie ?? '').isNotEmpty;
  String? get _cookie => AuthService.instance.authCookie;

  Map<String, String> _headers(String referer) => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        'Referer': referer,
        if ((_cookie ?? '').isNotEmpty) 'Cookie': _cookie!,
      };

  /// 抓取详情页并提取 formhash（Discuz 互动请求的必需令牌）。
  Future<String> _fetchFormhash(int tid) async {
    final client = await NetClient.instance.client;
    final resp = await NetClient.retry(() => client.get(
          Uri.parse('${_base}thread-$tid-1-1.html?mobile=2&_ycoo_int=${DateTime.now().millisecondsSinceEpoch}'),
          headers: _headers('${_base}thread-$tid-1-1.html'),
        ).timeout(NetClient.timeout));
    if (resp.statusCode != 200) throw Exception('读取帖子页面失败 HTTP ${resp.statusCode}');
    final html = NetClient.decode(resp.bodyBytes);
    final doc = parser.parse(html);
    for (final input in doc.querySelectorAll('input[name="formhash"]')) {
      final v = input.attributes['value']?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    // 兼容内联 JS 中声明的 formhash 变量。
    final m = RegExp(r'''formhash\s*=\s*['"]([a-f0-9]{8})['"]''', caseSensitive: false).firstMatch(html);
    if (m != null) return m.group(1)!;
    throw Exception('未取得互动令牌(formhash)，请刷新后重试');
  }

  /// 解析 Discuz AJAX 响应；返回 null 表示成功，否则返回失败提示。
  String? _parseResponse(List<int> bodyBytes) {
    final text = NetClient.decode(bodyBytes);
    if (text.contains('succeedhandle_') || text.contains('succeed') || text.contains('do_success')) {
      return null;
    }
    if (text.contains('请先登录') || text.contains('登录后才能')) return '请先登录论坛';
    if (text.contains('formhash') || text.contains('验证失败') || text.contains('非法请求')) {
      return '操作令牌已失效，请刷新帖子后重试';
    }
    final errorText = RegExp(r'''showError\(\s*['"]([^'"]+)['"]''').firstMatch(text)?.group(1) ??
        RegExp(r'''alert_error[^>]*>\s*(?:<p>)?([^<]{2,60})''').firstMatch(text)?.group(1);
    return errorText?.trim();
  }

  /// 查询收藏列表，返回 (是否已收藏, 收藏记录 id)。未登录时返回 (false, 0)。
  Future<(bool, int)> _favoriteInfo(int tid) async {
    final uid = AuthService.instance.uid;
    if (!_loggedIn || uid == null || uid <= 0) return (false, 0);
    try {
      final client = await NetClient.instance.client;
      final resp = await NetClient.retry(() => client.get(
            Uri.parse('${_base}home.php?mod=space&uid=$uid&do=favorite&view=me&mobile=2&_ycoo_ts=${DateTime.now().millisecondsSinceEpoch}'),
            headers: _headers('${_base}home.php?mod=space&uid=$uid'),
          ).timeout(NetClient.timeout));
      final html = NetClient.decode(resp.bodyBytes);
      final idx = html.indexOf('thread-$tid-');
      if (idx < 0) return (false, 0);
      final start = idx > 2000 ? idx - 2000 : 0;
      final end = idx + 2000 < html.length ? idx + 2000 : html.length;
      final favid = int.tryParse(RegExp(r'favid=(\d+)').firstMatch(html.substring(start, end))?.group(1) ?? '') ?? 0;
      return (true, favid);
    } catch (_) {
      return (false, 0);
    }
  }

  /// 点赞 / 取消点赞（Discuz misc.recommend）。
  Future<String?> toggleLike({required int tid, required int pid, required bool like}) async {
    if (!_loggedIn) return '请先登录论坛';
    try {
      final hash = await _fetchFormhash(tid);
      final client = await NetClient.instance.client;
      final url = '${_base}forum.php?mod=misc&action=recommend&do=${like ? 'add' : 'del'}'
          '&tid=$tid&pid=$pid&formhash=$hash&mobile=2';
      final resp = await NetClient.retry(() => client.post(
        Uri.parse(url),
        headers: {
          ..._headers('${_base}thread-$tid-1-1.html'),
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: <String, String>{
          'formhash': hash,
          if (like) 'recommendsubmit': 'yes',
          'tid': '$tid',
          'pid': '$pid',
        },
      ).timeout(NetClient.timeout));
      if (resp.statusCode != 200) return '操作失败 HTTP ${resp.statusCode}';
      return _parseResponse(resp.bodyBytes);
    } catch (e) {
      return '点赞请求失败，请检查网络后重试';
    }
  }

  /// 收藏 / 取消收藏（Discuz spacecp.favorite）。
  Future<String?> toggleFavorite({required int tid, required bool favorite}) async {
    if (!_loggedIn) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      if (favorite) {
        final hash = await _fetchFormhash(tid);
        final url = '${_base}home.php?mod=spacecp&ac=favorite&type=thread&id=$tid'
            '&handlekey=favoritebtn&inajax=1&mobile=2';
        final resp = await NetClient.retry(() => client.post(
          Uri.parse(url),
          headers: {
            ..._headers('${_base}thread-$tid-1-1.html'),
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
          },
          body: <String, String>{'formhash': hash, 'favoritesubmit': 'yes', 'type': 'thread', 'id': '$tid'},
        ).timeout(NetClient.timeout));
        if (resp.statusCode != 200) return '操作失败 HTTP ${resp.statusCode}';
        return _parseResponse(resp.bodyBytes);
      }
      // 取消收藏：先查收藏记录 id，再按 Discuz 标准删除接口提交。
      final (_, favid) = await _favoriteInfo(tid);
      if (favid <= 0) return '未找到收藏记录，可能已取消';
      final url = '${_base}home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid'
          '&handlekey=favoritebtn&inajax=1&mobile=2';
      final resp = await NetClient.retry(() => client.get(
        Uri.parse(url),
        headers: _headers('${_base}home.php?mod=space&uid=${AuthService.instance.uid ?? 0}'),
      ).timeout(NetClient.timeout));
      if (resp.statusCode != 200) return '操作失败 HTTP ${resp.statusCode}';
      return _parseResponse(resp.bodyBytes);
    } catch (e) {
      return '收藏请求失败，请检查网络后重试';
    }
  }

  /// 读取互动状态（点赞数 / 是否已赞 / 是否已收藏）。
  Future<ThreadInteractionState> fetchState({required ThreadDetail detail}) async {
    var favorited = false;
    if (_loggedIn) {
      final (f, _) = await _favoriteInfo(detail.tid);
      favorited = f;
    }
    return ThreadInteractionState(
      likeCount: detail.likeCount,
      likedByMe: detail.likedByMe,
      favorited: favorited,
    );
  }
}
