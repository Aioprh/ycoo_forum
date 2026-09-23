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
  final String addUrl; // 关注用的完整 action URL (formhash 已嵌入)
  final String deleteUrl; // 取消关注用的完整 action URL
  final String globalHash; // 页面级全局 formhash

  const FavoriteBoardInfo({
    required this.fid,
    required this.name,
    required this.icon,
    this.today = '',
    this.threads = '',
    this.followers = '',
    this.followed = false,
    this.addUrl = '',
    this.deleteUrl = '',
    this.globalHash = '',
  });

  FavoriteBoardInfo copyWith({
    int? fid,
    String? name,
    String? icon,
    String? today,
    String? threads,
    String? followers,
    bool? followed,
    String? addUrl,
    String? deleteUrl,
    String? globalHash,
  }) =>
      FavoriteBoardInfo(
        fid: fid ?? this.fid,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        today: today ?? this.today,
        threads: threads ?? this.threads,
        followers: followers ?? this.followers,
        followed: followed ?? this.followed,
        addUrl: addUrl ?? this.addUrl,
        deleteUrl: deleteUrl ?? this.deleteUrl,
        globalHash: globalHash ?? this.globalHash,
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
    String addUrl = '';
    String deleteUrl = '';

    // 页面级全局 formhash (Discuz 所有 action 共用)
    final globalHash = _globalHash(doc, html);

    // ========== 主选择器: Comiis 移动版 .comiis_forumlist_head ==========
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

      // 关注按钮 .comiis_forum_fav
      // 已登录+未关注 → href 就是 add URL
      // 已登录+已关注 → href 是 delete URL (带 op=delete)
      // 未登录 → href 是 javascript:popup.open(...)
      final favBtn = head.querySelector('.comiis_forum_fav');
      if (favBtn != null) {
        final btnText = favBtn.text.trim();
        final href = (favBtn.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (href.startsWith('home.php')) {
          // 登录态
          if (href.contains('op=delete')) {
            // 当前状态 = 已关注, href 是 delete URL
            followed = true;
            deleteUrl = href;
            // 反过来拼 add URL
            addUrl = _buildAddUrl(fid, globalHash);
          } else {
            // 当前状态 = 未关注, href 是 add URL
            followed = false;
            addUrl = href;
            // delete URL 需要 favid, 在 toggle 时动态拿或用 JS 里的方式
          }
        }
      }
    }

    // ========== 兜底 1: PC 版 Comiis N7 .comiis_lhd_tinfo ==========
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

    // ========== 兜底 2: <title> ==========
    if (name.isEmpty) {
      final tM = RegExp(r'<title>\s*([^<\s\-|]+)').firstMatch(html);
      if (tM != null) {
        final t = tM.group(1)!.trim();
        if (!RegExp(r'^(登录|注册|源论坛|首页|需要积分)', caseSensitive: false).hasMatch(t)) {
          name = t;
        }
      }
    }

    // ========== 兜底 3: 面包屑 ==========
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

    // 兜底 addUrl / deleteUrl
    if (addUrl.isEmpty && globalHash.isNotEmpty) addUrl = _buildAddUrl(fid, globalHash);

    return FavoriteBoardInfo(
      fid: fid,
      name: name.isEmpty ? '版块 $fid' : name,
      icon: icon,
      today: today,
      threads: threads,
      followers: followers,
      followed: followed,
      addUrl: addUrl,
      deleteUrl: deleteUrl,
      globalHash: globalHash,
    );
  }

  static String _buildAddUrl(int fid, String hash) {
    if (hash.isEmpty) return '';
    return 'home.php?mod=spacecp&ac=favorite&type=forum&id=$fid&formhash=$hash&handlekey=forum_fav';
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

  Future<String?> toggle({required int fid, required bool follow}) async {
    if (fid <= 0) return '版块无效';
    final cookie = AuthService.instance.authCookie ?? '';
    if (cookie.isEmpty) return '请先登录论坛';

    // 1) 用一次请求拿完整信息 (含 globalHash + addUrl/deleteUrl)
    final info = await fetchBoardInfo(fid);
    if (info == null) return '无法获取版块信息, 请稍后重试';

    if (info.followed == follow) return null;

    // 2) 选 action URL
    String action;
    if (follow) {
      action = info.addUrl;
      if (action.isEmpty) return '未找到关注操作入口, 请刷新后重试';
    } else {
      action = info.deleteUrl;
      if (action.isEmpty) return '未找到取消关注入口, 请先关注后在版块内取消';
    }

    // action URL 可能带相对路径, 转绝对
    final uri = Uri.tryParse(_absolute(action));
    if (uri == null) return '操作链接无效';

    // 3) 发请求 —— 跟 follow_service 一样, 去掉 X-Requested-With 避免 Discuz 返回异常格式
    final client = await NetClient.instance.client;
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Referer': boardUrl(fid),
      'Cookie': cookie,
    };

    try {
      final resp = await NetClient.retry(() => client.get(uri, headers: headers))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return '操作失败 HTTP ${resp.statusCode}';
      final body = NetClient.decode(resp.bodyBytes);

      // 4) 判定 (跟 follow_service 完全一致的顺序)
      if (_success(body, follow)) return null;
      if (_looksLikeLogin(body)) return '登录态已失效, 请重新登录论坛';
      if (_tokenError(body)) return '操作令牌已失效, 请刷新后重试';
      return follow ? '关注失败, 请稍后重试' : '取消关注失败, 请稍后重试';
    } catch (_) {
      return '操作失败, 请检查网络后重试';
    }
  }

  static bool _success(String body, bool follow) {
    final lower = body.toLowerCase();
    if (lower.contains('succeed') || body.contains('成功')) return true;
    if (follow && (body.contains('已关注') || body.contains('取消关注'))) return true;
    if (!follow && (body.contains('关注') || body.contains('已关注'))) {
      // 取消关注后按钮回到"关注"文字也算成功
      return !lower.contains('失败') && !lower.contains('error');
    }
    // Discuz AJAX handlekey 响应格式: XML 包裹 JS call
    // <root><![CDATA[succeedhandle_forum_fav(...)]]></root>
    // <root><![CDATA[errorhandle_forum_fav(...)]]></root>
    if (body.contains('succeedhandle_')) return true;
    if (body.contains('errorhandle_')) return false;
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
