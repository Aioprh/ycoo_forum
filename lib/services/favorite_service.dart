import 'package:html/dom.dart' as dom;
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
  final String followers; // "2919人关注" 里的数字
  final bool followed; // 是否已关注
  final String favid; // 关注记录 ID, 取消关注时需要
  final String followAction; // 关注/取消关注的完整 URL

  const FavoriteBoardInfo({
    required this.fid,
    required this.name,
    required this.icon,
    this.today = '',
    this.threads = '',
    this.followers = '',
    this.followed = false,
    this.favid = '',
    this.followAction = '',
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
    String? followAction,
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
        followAction: followAction ?? this.followAction,
      );
}

/// 版块关注（Discuz mobile 模板 forum_fav）。
class FavoriteBoardService {
  FavoriteBoardService._();
  static final instance = FavoriteBoardService._();

  static String get _base => SiteConfig.base;

  /// 跟 ApiService.forumUrl 用同一个 URL, 保证模板一致。
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

  /// 从移动版 forumdisplay 页面解析版块头。
  static FavoriteBoardInfo parseBoardInfo(String html, int fid) {
    final doc = parser.parse(html);

    String name = '';
    String icon = '';
    String today = '';
    String threads = '';
    String followers = '';
    bool followed = false;
    String favid = '';
    String followAction = '';

    // Comiis mobile: .comiis_forumlist_head
    final head = doc.querySelector('.comiis_forumlist_head');
    if (head != null) {
      // 版块名 .top_left h2
      name = head.querySelector('.top_left h2')?.text.trim() ?? '';
      // 图标 .top_ico img
      icon = head.querySelector('.top_ico img')?.attributes['src']?.trim() ?? '';

      // 统计: "主题: 3711 | 今日: 459"
      final stats = head.querySelectorAll('.comiis_tm7').map((e) => e.text).join(' ');
      final tRe = RegExp(r'今日\s*[:：]\s*(\d+)');
      final thRe = RegExp(r'(?:主题|帖数)\s*[:：]\s*(\d+)');
      final fRe = RegExp(r'(\d+)\s*人关注');
      final tMatch = tRe.firstMatch(stats);
      final thMatch = thRe.firstMatch(stats);
      final fMatch = fRe.firstMatch(stats);
      if (tMatch != null) today = tMatch.group(1)!;
      if (thMatch != null) threads = thMatch.group(1)!;
      if (fMatch != null) followers = fMatch.group(1)!;

      // 关注按钮 .comiis_forum_fav
      final favBtn = head.querySelector('.comiis_forum_fav');
      if (favBtn != null) {
        final btnText = favBtn.text.trim();
        final href = (favBtn.attributes['href'] ?? '').replaceAll('&amp;', '&');
        // 登录时 href 应该是 home.php?mod=spacecp&ac=favorite&op=delete... (取消关注)
        // 未登录时 href 是 javascript:popup.open(...)
        if (href.startsWith('home.php')) {
          followAction = _absolute(href);
          // 提取 favid
          final favidMatch = RegExp(r'favid=(\d+)').firstMatch(href);
          if (favidMatch != null) favid = favidMatch.group(1)!;
          // 按钮上有"已关注"文字 → 当前已关注
          followed = RegExp(r'已关注|取消关注', caseSensitive: true).hasMatch(btnText) ||
              href.contains('op=delete');
        } else if (href.startsWith('javascript:')) {
          // 未登录, 构造关注 URL
          followed = false;
        }
      }
    }

    // 兜底选择器: PC 版 comiis_lhd_tinfo
    if (name.isEmpty) {
      final tinfo = doc.querySelector('.comiis_lhd_tinfo');
      if (tinfo != null) {
        name = tinfo.querySelector('.km_name')?.text.trim() ?? '';
        icon = tinfo.querySelector('.km_img img')?.attributes['src']?.trim() ?? '';
        final txts = tinfo.querySelectorAll('.km_txt');
        if (txts.length > 1) {
          final stats = txts.last.text.trim();
          final t = RegExp(r'今日\s*[:：]\s*(\d+)').firstMatch(stats);
          final th = RegExp(r'(?:主题|帖数)\s*[:：]\s*(\d+)').firstMatch(stats);
          if (t != null) today = t.group(1)!;
          if (th != null) threads = th.group(1)!;
        }
        followers = tinfo.querySelector('#number_favorite_num')?.text.trim() ?? '';
      }
    }

    // 最终兜底: 面包屑里的版块名
    if (name.isEmpty) {
      // forumdisplay 面包屑里第一个 forum-$fid-N.html 的链接
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('forum-$fid-') || href.contains('fid=$fid')) {
          name = a.text.trim();
          if (name.isNotEmpty && name.length < 30) break;
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
      followAction: followAction,
    );
  }

  /// 关注 / 取消关注。先抓一次版块页拿到 formhash + 当前状态 + favid。
  Future<String?> toggle({required int fid, required bool follow}) async {
    if (fid <= 0) return '版块无效';
    final cookie = AuthService.instance.authCookie ?? '';
    if (cookie.isEmpty) return '请先登录论坛';

    // 1) 先抓一次版块页拿到 formhash / 当前状态 / favid
    final info = await fetchBoardInfo(fid);
    if (info == null) return '无法获取版块信息, 请稍后重试';

    // 如果当前状态已经是目标状态, 直接返回成功(或 null 表示无操作)
    if (info.followed == follow) return null;

    final html = await NetClient.retry(() async {
      final client = await NetClient.instance.client;
      final resp = await client.get(Uri.parse(boardUrl(fid)), headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': _base,
        'Cookie': cookie,
      });
      return NetClient.decode(resp.bodyBytes);
    }).timeout(const Duration(seconds: 20));

    final formhash = _extractFormhash(html);
    if (formhash.isEmpty) return '操作令牌获取失败, 请刷新后重试';

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
      // 关注: ac=favorite&type=forum&id=fid (handlekey=forum_fav)
      actionUrl =
          '${_base}home.php?mod=spacecp&ac=favorite&type=forum&id=$fid&formhash=$formhash&handlekey=forum_fav&mobile=2';
    } else {
      // 取消关注: 需要 favid (收藏记录 ID)
      // 优先用 info.favid, 否则从已解析的 followAction 里取, 否则从页面里解析
      String realFavid = info.favid;
      if (realFavid.isEmpty) {
        realFavid = RegExp(r'favid=(\d+)').firstMatch(info.followAction)?.group(1) ?? '';
      }
      if (realFavid.isEmpty) {
        final btn = parser.parse(html).querySelector('.comiis_forum_fav');
        if (btn != null) {
          final h = (btn.attributes['href'] ?? '').replaceAll('&amp;', '&');
          realFavid = RegExp(r'favid=(\d+)').firstMatch(h)?.group(1) ?? '';
        }
      }
      if (realFavid.isEmpty) {
        return '无法识别关注记录 ID, 请进入版块取消关注';
      }
      actionUrl =
          '${_base}home.php?mod=spacecp&ac=favorite&op=delete&type=forum&favid=$realFavid&formhash=$formhash&handlekey=forum_fav&mobile=2';
    }

    try {
      final resp = await client.get(Uri.parse(actionUrl), headers: headers).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return '操作失败 HTTP ${resp.statusCode}';
      final body = NetClient.decode(resp.bodyBytes);
      if (_looksLikeLogin(body)) return '登录态已失效, 请重新登录论坛';
      if (_tokenError(body)) return '操作令牌已失效, 请刷新后重试';
      if (body.contains('succeed') || body.contains('成功') || body.contains('forum_fav')) return null;
      return follow ? '关注失败, 请稍后重试' : '取消关注失败, 请稍后重试';
    } catch (_) {
      return '操作失败, 请检查网络后重试';
    }
  }

  static String _extractFormhash(String html) {
    // Comiis: <script>var formhash = 'xxx'</script>
    final m = RegExp("var\\s+formhash\\s*=\\s*['\"]([a-zA-Z0-9]{6,})['\"]", caseSensitive: false).firstMatch(html);
    if (m != null) return m.group(1)!;
    // Discuz standard
    for (final input in parser.parse(html).querySelectorAll('input[name="formhash"]')) {
      final v = input.attributes['value']?.trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final m2 = RegExp("(?:formhash|hash)\\s*[=:]\\s*['\"]([a-zA-Z0-9]{6,})['\"]", caseSensitive: false).firstMatch(html);
    return m2?.group(1) ?? '';
  }

  static bool _looksLikeLogin(String html) {
    final lower = html.toLowerCase();
    return lower.contains('name="loginfield"') ||
        lower.contains('id="ls_username"') ||
        (html.contains('登录') && lower.contains('password'));
  }

  static bool _tokenError(String body) {
    final lower = body.toLowerCase();
    return lower.contains('formhash') ||
        (lower.contains('hash') && (lower.contains('错误') || lower.contains('invalid') || lower.contains('失效')));
  }

  static String _absolute(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return _base + value.substring(1);
    return _base + value;
  }
}
