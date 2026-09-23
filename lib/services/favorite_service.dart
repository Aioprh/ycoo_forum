import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

class FavoriteBoardInfo {
  final int fid;
  final String name;
  final String icon;
  final String today;
  final String threads;
  final String followers;
  final bool followed;

  const FavoriteBoardInfo({
    required this.fid,
    required this.name,
    required this.icon,
    this.today = '',
    this.threads = '',
    this.followers = '',
    this.followed = false,
  });

  FavoriteBoardInfo copyWith({
    int? fid,
    String? name,
    String? icon,
    String? today,
    String? threads,
    String? followers,
    bool? followed,
  }) =>
      FavoriteBoardInfo(
        fid: fid ?? this.fid,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        today: today ?? this.today,
        threads: threads ?? this.threads,
        followers: followers ?? this.followers,
        followed: followed ?? this.followed,
      );
}

class FavoriteBoardService {
  FavoriteBoardService._();
  static final instance = FavoriteBoardService._();
  static String get _base => SiteConfig.base;

  static String boardUrl(int fid, {int page = 1}) =>
      '${_base}forum.php?mod=forumdisplay&fid=$fid&mobile=2&page=$page';

  Future<FavoriteBoardInfo?> fetchBoardInfo(int fid) async {
    if (fid <= 0) return null;
    final cookie = AuthService.instance.authCookie ?? '';
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': _base,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
    try {
      final resp = await NetClient.retry(() async {
        final client = await NetClient.instance.client;
        return client.get(Uri.parse(boardUrl(fid)), headers: headers);
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      final html = NetClient.decode(resp.bodyBytes);
      return parseBoardInfo(html, fid);
    } catch (_) {
      return null;
    }
  }

  static FavoriteBoardInfo parseBoardInfo(String html, int fid) {
    final doc = parser.parse(html);

    String name = '';
    String icon = '';
    String today = '';
    String threads = '';
    String followers = '';
    bool followed = false;

    final head = doc.querySelector('.comiis_forumlist_head');
    if (head != null) {
      name = head.querySelector('.top_left h2')?.text.trim() ?? '';
      if (name.isEmpty) name = head.querySelector('.top_left em, .top_left a')?.text.trim() ?? '';
      icon = head.querySelector('.top_ico img')?.attributes['src']?.trim() ?? '';

      final allText = head.text;
      final tRe = RegExp(r'今日\s*[:：]\s*(\d+)');
      final thRe = RegExp(r'(?:主题|帖数|帖子)\s*[:：]\s*(\d+)');
      final fRe = RegExp(r'(\d+)\s*人(?:已)?关注');
      final tMatch = tRe.firstMatch(allText);
      final thMatch = thRe.firstMatch(allText);
      final fMatch = fRe.firstMatch(allText);
      if (tMatch != null) today = tMatch.group(1)!;
      if (thMatch != null) threads = thMatch.group(1)!;
      if (fMatch != null) followers = fMatch.group(1)!;

      final favBtn = head.querySelector('.comiis_forum_fav');
      if (favBtn != null) {
        final href = (favBtn.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (href.startsWith('home.php') && href.contains('op=delete')) {
          followed = true;
        }
      }
    }

    if (name.isEmpty) {
      final tinfo = doc.querySelector('.comiis_lhd_tinfo');
      if (tinfo != null) {
        name = tinfo.querySelector('.km_name')?.text.trim() ?? '';
        icon = tinfo.querySelector('.km_img img')?.attributes['src']?.trim() ?? icon;
        final statsAll = tinfo.text;
        final t = RegExp(r'今日\s*[:：]\s*(\d+)').firstMatch(statsAll);
        final th = RegExp(r'(?:主题|帖数)\s*[:：]\s*(\d+)').firstMatch(statsAll);
        final f = RegExp(r'(\d+)\s*人(?:已)?收藏').firstMatch(statsAll);
        if (t != null) today = t.group(1)!;
        if (th != null) threads = th.group(1)!;
        if (f != null) followers = f.group(1)!;
      }
    }

    if (name.isEmpty) {
      final tM = RegExp(r'<title>\s*([^<\s\-|]+)').firstMatch(html);
      if (tM != null) {
        final t = tM.group(1)!.trim();
        if (!RegExp(r'^(登录|注册|源论坛|首页|需要积分)', caseSensitive: false).hasMatch(t)) {
          name = t;
        }
      }
    }

    if (name.isEmpty) {
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('forum-$fid-') || (href.contains('fid=$fid') && href.contains('forumdisplay'))) {
          final t = a.text.trim();
          if (t.isNotEmpty && t.length < 30 && !RegExp(r'(首页|论坛)').hasMatch(t)) {
            name = t;
            break;
          }
        }
      }
    }

    return FavoriteBoardInfo(
      fid: fid,
      name: name.isEmpty ? '版块 $fid' : name,
      icon: icon,
      today: today,
      threads: threads,
      followers: followers,
      followed: followed,
    );
  }

  // ============== 下面全部照抄 follow_service 的模式 ==============

  Future<String?> toggle({required int fid, required bool follow}) async {
    if (fid <= 0) return '版块无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';

    final client = await NetClient.instance.client;
    final pageUrl = boardUrl(fid);

    try {
      // 1) 抓版块页 —— 跟 follow_service 抓 profileUrl 一模一样
      final pageResp = await NetClient.retry(() => client.get(
            Uri.parse(pageUrl),
            headers: {
              'User-Agent': NetClient.ua,
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
              'Referer': _base,
              'Cookie': cookie,
            },
          )).timeout(const Duration(seconds: 20));

      if (pageResp.statusCode != 200) return '读取版块信息失败 HTTP ${pageResp.statusCode}';
      final html = NetClient.decode(pageResp.bodyBytes);
      if (_looksLikeLogin(html)) return '登录态已失效, 请重新登录论坛';

      // 2) 从页面找 action URL (照抄 follow_service._findFollowAction)
      final action = _findFavoriteAction(html, fid, follow);
      if (action == null) {
        return '版块页未找到有效的关注操作, 请刷新后重试';
      }

      // 3) 发 action 请求 —— 跟 follow_service 结构完全一样
      final uri = Uri.parse(_absolute(action));
      final response = await NetClient.retry(() => client.get(
            uri,
            headers: {
              'User-Agent': NetClient.ua,
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Referer': pageUrl,
              'Cookie': cookie,
              'X-Requested-With': 'XMLHttpRequest',
            },
          )).timeout(const Duration(seconds: 20));

      final body = NetClient.decode(response.bodyBytes);
      if (_success(body, follow)) return null;
      if (_looksLikeLogin(body)) return '登录态已失效, 请重新登录论坛';
      if (_tokenError(body)) return '操作令牌已失效, 请刷新后重试';
      return follow ? '关注失败, 请稍后重试' : '取消关注失败, 请稍后重试';
    } catch (_) {
      return '操作失败, 请检查网络后重试';
    }
  }

  /// 照抄 follow_service._findFollowAction 的结构
  static String? _findFavoriteAction(String html, int fid, bool follow) {
    final doc = parser.parse(html);
    final globalHash = _globalHash(doc, html);

    // 候选列表
    final candidates = <String>[];

    // 1) 遍历所有 <a href>
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final decoded = href.replaceAll('&amp;', '&');
      final lower = decoded.toLowerCase();

      if (!lower.contains('mod=spacecp') || !lower.contains('ac=favorite')) continue;
      if (!lower.contains('type=forum')) continue;

      // 关注: type=forum&id=$fid (无 op=delete)
      // 取消关注: op=delete&type=forum&favid=N
      if (follow) {
        // add URL: 要有 id=$fid, 且不能是 delete
        final uri = Uri.tryParse(decoded);
        if (uri == null) continue;
        final idParam = uri.queryParameters['id'];
        if (idParam != '$fid') continue;
        if (lower.contains('op=delete')) continue;

        // 跟 follow_service 一样: 如果 URL 里没 formhash, 补 globalHash
        final hasHash = (uri.queryParameters['formhash'] ?? '').isNotEmpty ||
            (uri.queryParameters['hash'] ?? '').isNotEmpty;
        if (!hasHash && globalHash.isNotEmpty) {
          final rebuilt = <String, String>{
            for (final entry in uri.queryParametersAll.entries) entry.key: entry.value.first,
            'formhash': globalHash,
          };
          candidates.add(uri.replace(queryParameters: rebuilt).toString());
        } else {
          candidates.add(decoded);
        }
      } else {
        // delete URL: 要有 op=delete 和 favid
        if (!lower.contains('op=delete')) continue;
        final uri = Uri.tryParse(decoded);
        if (uri == null) continue;
        final favid = uri.queryParameters['favid'] ?? '';
        if (favid.isEmpty) continue;

        final hasHash = (uri.queryParameters['formhash'] ?? '').isNotEmpty ||
            (uri.queryParameters['hash'] ?? '').isNotEmpty;
        if (!hasHash && globalHash.isNotEmpty) {
          final rebuilt = <String, String>{
            for (final entry in uri.queryParametersAll.entries) entry.key: entry.value.first,
            'formhash': globalHash,
          };
          candidates.add(uri.replace(queryParameters: rebuilt).toString());
        } else {
          candidates.add(decoded);
        }
      }
    }

    if (candidates.isNotEmpty) return candidates.first;

    // 2) 从 JS 字符串兜底搜 (照抄 follow_service)
    if (follow) {
      // add URL pattern: home.php?mod=spacecp&ac=favorite&type=forum&id=$fid...
      final escapedFid = RegExp.escape('$fid');
      final pattern = RegExp(
        'home\\.php\\?mod=spacecp&ac=favorite&type=forum[^"\\\'<>\\s]*?id=$escapedFid[^"\\\'<>\\s]*',
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(html)) {
        var value = match.group(0) ?? '';
        value = value.replaceAll('&amp;', '&');
        final uri = Uri.tryParse(value);
        if (uri == null) continue;
        final hasHash = (uri.queryParameters['formhash'] ?? '').isNotEmpty ||
            (uri.queryParameters['hash'] ?? '').isNotEmpty;
        if (!hasHash && globalHash.isNotEmpty) {
          final rebuilt = <String, String>{
            for (final entry in uri.queryParametersAll.entries) entry.key: entry.value.first,
            'formhash': globalHash,
          };
          return uri.replace(queryParameters: rebuilt).toString();
        }
        return value;
      }
    } else {
      // delete URL pattern: home.php?mod=spacecp&ac=favorite&op=delete&type=forum...&favid=N
      final pattern = RegExp(
        'home\\.php\\?mod=spacecp&ac=favorite&op=delete&type=forum[^"\\\'<>\\s]*',
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(html)) {
        var value = match.group(0) ?? '';
        value = value.replaceAll('&amp;', '&');
        final uri = Uri.tryParse(value);
        if (uri == null) continue;
        final favid = uri.queryParameters['favid'] ?? '';
        if (favid.isEmpty) continue;
        final hasHash = (uri.queryParameters['formhash'] ?? '').isNotEmpty ||
            (uri.queryParameters['hash'] ?? '').isNotEmpty;
        if (!hasHash && globalHash.isNotEmpty) {
          final rebuilt = <String, String>{
            for (final entry in uri.queryParametersAll.entries) entry.key: entry.value.first,
            'formhash': globalHash,
          };
          return uri.replace(queryParameters: rebuilt).toString();
        }
        return value;
      }
    }

    // 3) 终极兜底: 自己拼 URL (只有 add 能拼, delete 因为需要 favid 拼不了)
    if (follow && globalHash.isNotEmpty) {
      return 'home.php?mod=spacecp&ac=favorite&type=forum&id=$fid&formhash=$globalHash&handlekey=forum_fav';
    }

    return null;
  }

  static String _globalHash(dom.Document doc, String html) {
    for (final input in doc.querySelectorAll('input[name="formhash"], input[name="hash"]')) {
      final v = input.attributes['value']?.trim() ?? '';
      if (v.isNotEmpty && v != '0') return v;
    }
    final hashRe = RegExp(
      "var\\s+formhash\\s*=\\s*['\"]([a-zA-Z0-9]{6,})['\"]|(?:formhash|hash)\\s*[=:]\\s*['\"]([a-zA-Z0-9]{6,})['\"]",
      caseSensitive: false,
    );
    for (final m in hashRe.allMatches(html)) {
      final v = (m.group(1) ?? m.group(2) ?? '').trim();
      if (v.isNotEmpty && v != '0') return v;
    }
    return '';
  }

  static bool _success(String body, bool follow) {
    final lower = body.toLowerCase();
    if (lower.contains('succeed') || body.contains('成功')) return true;
    if (body.contains('succeedhandle_')) return true;
    if (follow && (body.contains('已关注') || body.contains('取消关注'))) return true;
    if (!follow && (body.contains('取消关注') || body.contains('关注ta') || body.contains('关注'))) {
      return !lower.contains('失败') && !lower.contains('error');
    }
    return false;
  }

  static bool _tokenError(String body) {
    final lower = body.toLowerCase();
    return lower.contains('formhash') ||
        (lower.contains('hash') &&
            (lower.contains('错误') ||
                lower.contains('invalid') ||
                lower.contains('失效') ||
                lower.contains('wrong')));
  }

  static bool _looksLikeLogin(String html) {
    final lower = html.toLowerCase();
    return lower.contains('name="loginfield"') ||
        lower.contains('id="ls_username"') ||
        (html.contains('登录') && lower.contains('password'));
  }

  static String _absolute(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return _base + value.substring(1);
    return _base + value;
  }
}
