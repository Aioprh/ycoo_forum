import 'package:html/parser.dart' as parser;

import '../models/thread_detail.dart';
import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

class ThreadInteractionState {
  final int likeCount;
  final bool likedByMe;
  final bool favorited;
  const ThreadInteractionState({this.likeCount = 0, this.likedByMe = false, this.favorited = false});
}

/// Discuz 帖子互动：点赞、收藏、打赏。
/// 所有写操作都先从当前帖子页面重新获取 formhash，并优先复用原站页面提供的动作地址。
class ThreadInteractionService {
  ThreadInteractionService._();
  static final instance = ThreadInteractionService._();
  static String get _base => SiteConfig.base;

  bool get _loggedIn => AuthService.instance.isLoggedIn && (AuthService.instance.authCookie ?? '').isNotEmpty;
  String? get _cookie => AuthService.instance.authCookie;

  Map<String, String> _headers(String referer, {bool ajax = false}) => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        'Referer': referer,
        if (ajax) 'X-Requested-With': 'XMLHttpRequest',
        if ((_cookie ?? '').isNotEmpty) 'Cookie': _cookie!,
      };

  Future<String> _fetchThreadHtml(int tid) async {
    final client = await NetClient.instance.client;
    final url = '${_base}thread-$tid-1-1.html?mobile=2&_ycoo_int=${DateTime.now().millisecondsSinceEpoch}';
    final resp = await NetClient.retry(() => client.get(Uri.parse(url), headers: _headers('${_base}thread-$tid-1-1.html')).timeout(NetClient.timeout));
    if (resp.statusCode != 200) throw Exception('读取帖子页面失败 HTTP ${resp.statusCode}');
    return NetClient.decode(resp.bodyBytes);
  }

  String _formhash(String html) {
    final doc = parser.parse(html);
    for (final input in doc.querySelectorAll('input[name="formhash"]')) {
      final value = input.attributes['value']?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final patterns = <RegExp>[
      RegExp(r'''formhash\s*[=:]\s*['"]([a-f0-9]{8})['"]''', caseSensitive: false),
      RegExp(r'''(?:[?&]|\b)formhash=([a-f0-9]{8})''', caseSensitive: false),
      RegExp(r'''(?:[?&]|\b)hash=([a-f0-9]{8})''', caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      if (m != null) return m.group(1)!;
    }
    throw Exception('未取得互动令牌(formhash)，请刷新后重试');
  }

  String? _parseResponse(List<int> bodyBytes) {
    final text = NetClient.decode(bodyBytes);
    final normalized = text.replaceAll(RegExp(r'\\s+'), ' ');
    if (normalized.contains('succeedhandle_') || normalized.contains('succeed') || normalized.contains('do_success') || normalized.contains('操作成功')) return null;
    if (normalized.contains('请先登录') || normalized.contains('登录后才能')) return '请先登录论坛';
    if (normalized.contains('formhash') || normalized.contains('验证失败') || normalized.contains('非法请求') || normalized.contains('来路不正确')) return '操作令牌已失效，请刷新帖子后重试';
    final error = RegExp(r'''showError\(\s*['"]([^'"]+)['"]''').firstMatch(text)?.group(1) ??
        RegExp(r'''(?:alert_error|error_message)[^>]*>\s*(?:<[^>]+>\s*)?([^<]{2,120})''').firstMatch(text)?.group(1);
    return error?.trim();
  }

  Future<String?> toggleLike({required int tid, required int pid, required bool like}) async {
    if (!_loggedIn) return '请先登录论坛';
    if (tid <= 0 || pid <= 0) return '未取得有效的帖子楼层，请刷新帖子后重试';
    try {
      final html = await _fetchThreadHtml(tid);
      final hash = _formhash(html);
      final client = await NetClient.instance.client;
      final referer = '${_base}thread-$tid-1-1.html';
      // Discuz 标准点赞入口使用 recommend，原站移动模板通常把 formhash 放在 hash 参数。
      final doAction = like ? 'add' : 'subtract';
      final uri = Uri.parse('${_base}forum.php').replace(queryParameters: {
        'mod': 'misc',
        'action': 'recommend',
        'do': doAction,
        'tid': '$tid',
        'pid': '$pid',
        'hash': hash,
        'formhash': hash,
        'inajax': '1',
        'mobile': '2',
      });
      final headers = _headers(referer, ajax: true);
      // 先按网页按钮的 GET 语义执行；部分站点改成 POST，则自动回退。
      var resp = await NetClient.retry(() => client.get(uri, headers: headers).timeout(NetClient.timeout));
      var result = _parseResponse(resp.bodyBytes);
      if (resp.statusCode != 200 || (result != null && result != '请先登录论坛')) {
        resp = await NetClient.retry(() => client.post(
          uri,
          headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
          body: {'formhash': hash, 'hash': hash, 'tid': '$tid', 'pid': '$pid', if (like) 'recommendsubmit': 'yes'},
        ).timeout(NetClient.timeout));
        result = _parseResponse(resp.bodyBytes);
      }
      return result;
    } catch (e) {
      return e.toString().contains('互动令牌') ? e.toString().replaceFirst('Exception: ', '') : '点赞请求失败，请检查网络后重试';
    }
  }

  /// 打赏（网页端实际是 Discuz 评分，星币 credit=4）。
  /// 提交参数与登录后网页评分弹窗一致：
  /// forum.php?mod=misc&action=rate&ratesubmit=yes&infloat=yes
  /// formhash / tid / pid / referer / handlekey=rate / score4=数量 / reason=鼓励语 / sendreasonpm=on / ratesubmit=true
  Future<String?> reward({
    required int tid,
    required int pid,
    required int amount,
    String reason = '',
    bool notifyAuthor = true,
  }) async {
    if (!_loggedIn) return '请先登录论坛';
    if (tid <= 0 || pid <= 0) return '未取得有效的帖子楼层，请刷新帖子后重试';
    if (amount <= 0) return '请输入有效的打赏数量';
    try {
      final html = await _fetchThreadHtml(tid);
      final hash = _formhash(html);
      final client = await NetClient.instance.client;
      final referer = '${_base}thread-$tid-1-1.html';

      final uri = Uri.parse('${_base}forum.php').replace(queryParameters: {
        'mod': 'misc',
        'action': 'rate',
        'ratesubmit': 'yes',
        'infloat': 'yes',
      });
      final body = <String, String>{
        'formhash': hash,
        'tid': '$tid',
        'pid': '$pid',
        'referer': _abs('forum.php?mod=viewthread&tid=$tid&page=0#pid$pid'),
        'handlekey': 'rate',
        'score4': '$amount',
        'reason': reason,
        if (notifyAuthor) 'sendreasonpm': 'on',
        'ratesubmit': 'true',
      };
      final resp = await NetClient.retry(() => client.post(
        uri,
        headers: {..._headers(referer, ajax: true), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
        body: body,
      ).timeout(NetClient.timeout));
      final respText = NetClient.decode(resp.bodyBytes);
      if (respText.contains('评级操作成功') || respText.contains('操作成功') || respText.contains('succeed')) return null;
      if (respText.contains('评分等级已用完') || respText.contains('今日评分')) {
        final m = RegExp(r'''showDialog\([^)]*['"]([^'"]+)['"]''').firstMatch(respText);
        return m?.group(1) ?? '今日评分额度已用完';
      }
      return _parseResponse(resp.bodyBytes) ?? '打赏成功';
    } catch (e) {
      return '打赏请求失败，请检查网络后重试';
    }
  }

  String _abs(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$_base${url.substring(1)}';
    return '$_base${url.replaceFirst(RegExp(r'^\./'), '')}';
  }

  Future<(bool, int)> _favoriteInfo(int tid) async {
    final uid = AuthService.instance.uid;
    if (!_loggedIn || uid == null || uid <= 0) return (false, 0);
    try {
      final client = await NetClient.instance.client;
      final resp = await NetClient.retry(() => client.get(
            Uri.parse('${_base}home.php?mod=space&uid=$uid&do=favorite&view=me&mobile=2&_ycoo_ts=${DateTime.now().millisecondsSinceEpoch}'),
            headers: _headers('${_base}home.php?mod=space&uid=$uid'),
          ).timeout(NetClient.timeout));
      if (resp.statusCode != 200) return (false, 0);
      final doc = parser.parse(NetClient.decode(resp.bodyBytes));
      final needle = 'thread-$tid-';
      for (final link in doc.querySelectorAll('a[href]')) {
        final href = link.attributes['href'] ?? '';
        if (!href.contains(needle)) continue;
        for (var node = link.parent; node != null; node = node.parent) {
          final m = RegExp(r'[?&]favid=(\d+)').firstMatch(node.outerHtml);
          if (m != null) return (true, int.tryParse(m.group(1)!) ?? 0);
          if (node.localName == 'li' || node.localName == 'tr') break;
        }
      }
    } catch (_) {}
    return (false, 0);
  }

  Future<String?> toggleFavorite({required int tid, required bool favorite}) async {
    if (!_loggedIn) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final hash = _formhash(await _fetchThreadHtml(tid));
      if (favorite) {
        final url = '${_base}home.php?mod=spacecp&ac=favorite&type=thread&id=$tid&handlekey=favoritebtn&inajax=1&mobile=2';
        final resp = await client.post(Uri.parse(url), headers: {..._headers('${_base}thread-$tid-1-1.html', ajax: true), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: {'formhash': hash, 'favoritesubmit': 'yes', 'type': 'thread', 'id': '$tid'}).timeout(NetClient.timeout);
        return _parseResponse(resp.bodyBytes);
      }
      final (_, favid) = await _favoriteInfo(tid);
      if (favid <= 0) return '未找到收藏记录，请刷新帖子后重试';
      final url = '${_base}home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid&type=all&inajax=1&mobile=2';
      final resp = await client.post(Uri.parse(url), headers: {..._headers('${_base}thread-$tid-1-1.html', ajax: true), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: {'formhash': hash, 'handlekey': 'a_delete_$favid', 'deletesubmit': 'true'}).timeout(NetClient.timeout);
      return _parseResponse(resp.bodyBytes);
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '').contains('令牌') ? e.toString().replaceFirst('Exception: ', '') : '收藏请求失败，请检查网络后重试';
    }
  }

  Future<ThreadInteractionState> fetchState({required ThreadDetail detail}) async {
    var favorited = false;
    if (_loggedIn) {
      final (f, _) = await _favoriteInfo(detail.tid);
      favorited = f;
    }
    return ThreadInteractionState(likeCount: detail.likeCount, likedByMe: detail.likedByMe, favorited: favorited);
  }
}
