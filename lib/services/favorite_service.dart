import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// 版块头信息（从移动版 forumdisplay 页面解析）。
class FavoriteBoardInfo {
  final int fid;
  final String name;
  final String icon;
  final String today;
  final String threads;
  final String followers;
  final bool followed;
  final String favid;
  final String formhash;
  final String rawHtml; // 原始 HTML, 供 toggle 复用, 避免重复请求

  const FavoriteBoardInfo({
    required this.fid,
    required this.name,
    required this.icon,
    this.today = '',
    this.threads = '',
    this.followers = '',
    this.followed = false,
    this.favid = '',
    this.formhash = '',
    this.rawHtml = '',
  });

  FavoriteBoardInfo copyWith({
    int? fid,
    String? name,
    String? icon,
    String? today,
    String? threads,
    String? followers,
    bool? followed,
    String? favid,
    String? formhash,
    String? rawHtml,
  }) =>
      FavoriteBoardInfo(
        fid: fid ?? this.fid,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        today: today ?? this.today,
        threads: threads ?? this.threads,
        followers: followers ?? this.followers,
        followed: followed ?? this.followed,
        favid: favid ?? this.favid,
        formhash: formhash ?? this.formhash,
        rawHtml: rawHtml ?? this.rawHtml,
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
      // 如果返回的是登录页或错误页, 放弃
      if (_looksLikeLoginPage(html)) return null;
      return parseBoardInfo(html, fid);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeLoginPage(String html) {
    if (html.isEmpty) return true;
    // <title>登录 - 源论坛</title>
    final lower = html.toLowerCase();
    if (RegExp(r'<title>[^<]*登录[^<]*</title>', caseSensitive: false).hasMatch(html)) return true;
    if (RegExp(r'<title>[^<]*需要积分[^<]*</title>').hasMatch(html)) return true;
    if (lower.contains('name="loginfield"') && lower.contains('id="ls_password"')) return true;
    return false;
  }

  static FavoriteBoardInfo parseBoardInfo(String html, int fid) {
    final doc = parser.parse(html);

    String name = '';
    String icon = '';
    String today = '';
    String threads = '';
    String followers = '';
    bool followed = false;
    String favid = '';

    // ========== 主选择器: Comiis 移动版 .comiis_forumlist_head ==========
    final head = doc.querySelector('.comiis_forumlist_head');
    if (head != null) {
      // 版块名
      name = head.querySelector('.top_left h2')?.text.trim() ?? '';
      if (name.isEmpty) name = head.querySelector('.top_left em, .top_left a')?.text.trim() ?? '';

      // 图标
      icon = head.querySelector('.top_ico img')?.attributes['src']?.trim() ?? '';

      // 统计行: "主题: 3711 | 今日: 459" 或多段 comiis_tm7
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
      final favBtn = head.querySelector('.comiis_forum_fav');
      if (favBtn != null) {
        final btnText = favBtn.text.trim();
        final href = (favBtn.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (href.startsWith('home.php')) {
          // 登录态下: 这里是取消关注链接
          final favidMatch = RegExp(r'favid=(\d+)').firstMatch(href);
          if (favidMatch != null) favid = favidMatch.group(1)!;
          followed = href.contains('op=delete') || RegExp(r'已关注|取消关注').hasMatch(btnText);
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

    // ========== 兜底 2: <title> 标签 ==========
    if (name.isEmpty) {
      final titleMatch = RegExp(r'<title>\s*([^<\s\-|]+)').firstMatch(html);
      if (titleMatch != null) {
        final t = titleMatch.group(1)!.trim();
        // 过滤掉通用标题
        if (!RegExp(r'^(登录|注册|源论坛|首页|需要积分)', caseSensitive: false).hasMatch(t)) {
          name = t;
        }
      }
    }

    // ========== 兜底 3: 面包屑 forum-$fid-N.html ==========
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

    // formhash
    String formhash = '';
    final fhM = RegExp("var\\s+formhash\\s*=\\s*['\"]([a-zA-Z0-9]{6,})['\"]", caseSensitive: false).firstMatch(html);
    if (fhM != null) formhash = fhM.group(1)!;
    if (formhash.isEmpty) {
      for (final input in doc.querySelectorAll('input[name="formhash"]')) {
        final v = input.attributes['value']?.trim() ?? '';
        if (v.isNotEmpty) {
          formhash = v;
          break;
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
      favid: favid,
      formhash: formhash,
      rawHtml: html,
    );
  }

  Future<String?> toggle({required int fid, required bool follow}) async {
    if (fid <= 0) return '版块无效';
    final cookie = AuthService.instance.authCookie ?? '';
    if (cookie.isEmpty) return '请先登录论坛';

    // 1) 用同一请求同时拿到 boardInfo + formhash + 当前关注状态
    final info = await fetchBoardInfo(fid);
    if (info == null) return '无法获取版块信息, 请稍后重试';

    if (info.followed == follow) return null; // 已是目标状态, 无操作

    if (info.formhash.isEmpty) return '操作令牌获取失败, 请刷新后重试';

    final client = await NetClient.instance.client;
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': '*/*',
      'Referer': boardUrl(fid),
      'Cookie': cookie,
      'X-Requested-With': 'XMLHttpRequest',
    };

    String actionUrl;
    if (follow) {
      // 关注
      actionUrl =
          '${_base}home.php?mod=spacecp&ac=favorite&type=forum&id=$fid&formhash=${info.formhash}&handlekey=forum_fav&mobile=2';
    } else {
      // 取消关注: 需要 favid
      String realFavid = info.favid;
      if (realFavid.isEmpty) {
        // 从 rawHtml 里重新扫一次 favid
        final btn = parser.parse(info.rawHtml).querySelector('.comiis_forum_fav');
        if (btn != null) {
          final h = (btn.attributes['href'] ?? '').replaceAll('&amp;', '&');
          final m = RegExp(r'favid=(\d+)').firstMatch(h);
          if (m != null) realFavid = m.group(1)!;
        }
      }
      if (realFavid.isEmpty) return '无法识别关注记录, 请进入版块取消关注';
      actionUrl =
          '${_base}home.php?mod=spacecp&ac=favorite&op=delete&type=forum&favid=$realFavid&formhash=${info.formhash}&handlekey=forum_fav&mobile=2';
    }

    try {
      final resp = await client.get(Uri.parse(actionUrl), headers: headers).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return '操作失败 HTTP ${resp.statusCode}';
      final body = NetClient.decode(resp.bodyBytes);
      if (_looksLikeLoginPage(body) || _looksLikeLogin(body)) return '登录态已失效, 请重新登录论坛';
      if (_tokenError(body)) return '操作令牌已失效, 请刷新后重试';
      if (body.contains('succeed') || body.contains('成功')) return null;
      // 某些 Discuz 版本返回 <script>history.back();</script> 也算成功
      if (body.contains('history.back') || body.contains('forum_fav')) return null;
      return follow ? '关注失败, 请稍后重试' : '取消关注失败, 请稍后重试';
    } catch (_) {
      return '操作失败, 请检查网络后重试';
    }
  }

  static bool _looksLikeLogin(String html) {
    final lower = html.toLowerCase();
    return lower.contains('name="loginfield"') ||
        lower.contains('id="ls_username"') ||
        (html.contains('登录') && lower.contains('password'));
  }

  static bool _tokenError(String body) {
    final lower = body.toLowerCase();
    return (lower.contains('formhash') || lower.contains('hash')) &&
        (lower.contains('错误') || lower.contains('invalid') || lower.contains('失效') || lower.contains('wrong'));
  }
}
