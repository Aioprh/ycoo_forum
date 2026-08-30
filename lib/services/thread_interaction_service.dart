import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/thread_detail.dart';
import 'auth_service.dart';
import 'net_client.dart';

class ThreadInteractionState {
  final int likeCount;
  final bool likedByMe;
  final bool favorited;
  const ThreadInteractionState({this.likeCount = 0, this.likedByMe = false, this.favorited = false});
}

class ThreadInteractionService {
  ThreadInteractionService._();
  static final instance = ThreadInteractionService._();
  static const _base = 'https://www.ycoo.net/';

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
    final page = '${_base}thread-$tid-1-1.html';
    final uri = Uri.parse(page).replace(queryParameters: {'mobile': '2', '_ycoo_int': DateTime.now().millisecondsSinceEpoch.toString()});
    final resp = await NetClient.retry(() => client.get(uri, headers: _headers(page)).timeout(NetClient.timeout));
    if (resp.statusCode != 200) throw Exception('读取帖子页面失败 HTTP ${resp.statusCode}');
    return NetClient.decode(resp.bodyBytes);
  }

  String _formhash(String html) {
    final doc = parser.parse(html);
    for (final input in doc.querySelectorAll('input[name="formhash"]')) {
      final value = input.attributes['value']?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    for (final re in <RegExp>[
      RegExp(r'''formhash\s*[=:]\s*['"]([A-Za-z0-9_-]{6,64})['"]''', caseSensitive: false),
      RegExp(r'''(?:[?&]|\b)formhash=([A-Za-z0-9_-]{6,64})''', caseSensitive: false),
      RegExp(r'''(?:[?&]|\b)hash=([A-Za-z0-9_-]{6,64})''', caseSensitive: false),
      RegExp(r'''["']formhash["']\s*:\s*["']([A-Za-z0-9_-]{6,64})['"]''', caseSensitive: false),
    ]) {
      final m = re.firstMatch(html);
      if (m != null && m.group(1)!.isNotEmpty) return m.group(1)!;
    }
    throw Exception('未取得互动令牌(formhash)，请刷新后重试');
  }

  String? _parseResponse(List<int> bodyBytes) {
    final text = NetClient.decode(bodyBytes);
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.contains('succeedhandle_') || normalized.contains('succeed') || normalized.contains('do_success') || normalized.contains('操作成功')) return null;
    if (normalized.contains('请先登录') || normalized.contains('登录后才能')) return '请先登录论坛';
    if (normalized.contains('操作令牌已失效') || normalized.contains('表单验证串不符') || normalized.contains('请求来路不正确') || normalized.contains('formhash错误') || normalized.contains('验证失败') || normalized.contains('非法请求')) return '操作令牌已失效，请刷新帖子后重试';
    final error = RegExp(r'''showError\(\s*['"]([^'"]+)['"]''').firstMatch(text)?.group(1) ?? RegExp(r'''(?:alert_error|error_message)[^>]*>\s*(?:<[^>]+>\s*)?([^<]{2,120})''').firstMatch(text)?.group(1);
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
      final uri = Uri.parse('${_base}forum.php').replace(queryParameters: {'mod': 'misc', 'action': 'recommend', 'do': like ? 'add' : 'subtract', 'tid': '$tid', 'hash': hash, 'inajax': '1', 'mobile': '2'});
      final headers = _headers(referer, ajax: true);
      var response = await NetClient.retry(() => client.get(uri, headers: headers).timeout(NetClient.timeout));
      var result = _parseResponse(response.bodyBytes);
      if (result == null) return null;
      response = await NetClient.retry(() => client.post(uri, headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: {'hash': hash, 'formhash': hash, 'tid': '$tid', 'pid': '$pid', if (like) 'recommendsubmit': 'yes'}).timeout(NetClient.timeout));
      return _parseResponse(response.bodyBytes);
    } catch (e) {
      return e.toString().contains('互动令牌') ? e.toString().replaceFirst('Exception: ', '') : '点赞请求失败，请检查网络后重试';
    }
  }

  Future<String?> reward({required int tid, required int pid, required int amount}) async {
    if (!_loggedIn) return '请先登录论坛';
    if (tid <= 0 || pid <= 0) return '未取得有效的帖子楼层，请刷新帖子后重试';
    if (amount < 1 || amount > 3) return '打赏数量只能选择 1～3 星币';
    try {
      // 每次重新读取帖子页面，使用最新 formhash，并复用原站打赏表单。
      final html = await _fetchThreadHtml(tid);
      final doc = parser.parse(html);
      final hash = _formhash(html);
      final client = await NetClient.instance.client;
      final referer = '${_base}thread-$tid-1-1.html';

      for (final e in doc.querySelectorAll('form,a[href],button[onclick],input[onclick]')) {
        final blob = '${e.text} ${e.attributes['title'] ?? ''} ${e.attributes['value'] ?? ''} ${e.attributes['href'] ?? ''} ${e.attributes['onclick'] ?? ''}'.toLowerCase();
        if (!blob.contains('打赏') && !blob.contains('reward')) continue;
        final form = e.localName == 'form' ? e : e.parent?.querySelector('form');
        if (form != null) {
          final action = _abs(form.attributes['action'] ?? '');
          if (action.isEmpty) continue;
          final fields = <String, String>{};
          final amountFields = <String>[];
          for (final input in form.querySelectorAll('input')) {
            final name = input.attributes['name'];
            if (name == null || name.isEmpty) continue;
            fields[name] = input.attributes['value'] ?? '';
            final lower = name.toLowerCase();
            if (lower.contains('reward') || lower.contains('amount') || lower.contains('coin') || lower.contains('star') || lower.contains('extcredit')) amountFields.add(name);
          }
          fields['formhash'] = fields['formhash']?.isNotEmpty == true ? fields['formhash']! : hash;
          fields.putIfAbsent('tid', () => '$tid');
          fields.putIfAbsent('pid', () => '$pid');
          // 优先修改原站表单真实的星币/打赏金额字段；不再把积分字段当成打赏金额。
          if (amountFields.isNotEmpty) {
            for (final name in amountFields) fields[name] = '$amount';
          } else {
            fields['amount'] = '$amount';
            fields['reward'] = '$amount';
          }
          final resp = await client.post(Uri.parse(action), headers: {..._headers(referer, ajax: true), 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}, body: fields).timeout(NetClient.timeout);
          return _parseResponse(resp.bodyBytes) ?? '已打赏 $amount 星币';
        }

        var href = e.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('javascript:')) href = _extractUrl(e.attributes['onclick'] ?? '');
        if (href.isNotEmpty) {
          var uri = Uri.parse(_abs(href));
          uri = uri.replace(queryParameters: {...uri.queryParameters, 'formhash': hash, 'hash': hash, 'tid': '$tid', 'pid': '$pid', 'amount': '$amount', 'reward': '$amount'});
          final resp = await client.get(uri, headers: _headers(referer, ajax: true)).timeout(NetClient.timeout);
          return _parseResponse(resp.bodyBytes) ?? '已打赏 $amount 星币';
        }
      }
      return '当前帖子没有可用的原站打赏入口';
    } catch (_) {
      return '打赏请求失败，请检查网络后重试';
    }
  }

  String _extractUrl(String js) {
    for (final re in <RegExp>[
      RegExp(r'''['"]((?:forum\\.php|home\\.php|plugin\\.php|thread-[^'"]+)[^'"]*)['"]''', caseSensitive: false),
      RegExp(r'''['"](https?://[^'"]+)['"]''', caseSensitive: false),
    ]) {
      final m = re.firstMatch(js);
      if (m != null) return m.group(1)!;
    }
    return '';
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
      final uri = Uri.parse('${_base}home.php').replace(queryParameters: {'mod': 'space', 'uid': '$uid', 'do': 'favorite', 'view': 'me', 'mobile': '2', '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString()});
      final resp = await NetClient.retry(() => client.get(uri, headers: _headers('${_base}home.php?mod=space&uid=$uid')).timeout(NetClient.timeout));
      if (resp.statusCode != 200) return (false, 0);
      final doc = parser.parse(NetClient.decode(resp.bodyBytes));
      final needle = 'thread-$tid-';
      for (final link in doc.querySelectorAll('a[href]')) {
        final href = link.attributes['href'] ?? '';
        if (!href.contains(needle)) continue;
        for (dom.Element? node = link.parent; node != null; node = node.parent) {
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
      final referer = '${_base}thread-$tid-1-1.html';
      if (favorite) {
        final uri = Uri.parse('${_base}home.php').replace(queryParameters: {'mod': 'spacecp', 'ac': 'favorite', 'type': 'thread', 'id': '$tid', 'formhash': hash, 'handlekey': 'favoritebtn', 'inajax': '1', 'mobile': '2'});
        final resp = await client.get(uri, headers: _headers(referer, ajax: true)).timeout(NetClient.timeout);
        return _parseResponse(resp.bodyBytes);
      }
      final (_, favid) = await _favoriteInfo(tid);
      if (favid <= 0) return '未找到收藏记录，请刷新帖子后重试';
      final uri = Uri.parse('${_base}home.php').replace(queryParameters: {'mod': 'spacecp', 'ac': 'favorite', 'op': 'delete', 'favid': '$favid', 'type': 'all', 'formhash': hash, 'handlekey': 'a_delete_$favid', 'inajax': '1', 'mobile': '2'});
      final resp = await client.get(uri, headers: _headers(referer, ajax: true)).timeout(NetClient.timeout);
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
