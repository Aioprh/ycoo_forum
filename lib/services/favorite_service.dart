import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// 版块详情（名称 / 图标 / 今日数 / 主题数 / 收藏数 / 是否已收藏 / 收藏接口）。
class FavoriteBoardInfo {
  final int fid;
  final String name;
  final String icon;
  final String today;
  final String threads;
  final String favorites;
  final bool favorited;
  final String toggleAction; // 收藏/取消收藏的完整 URL, 带 handlekey + formhash
  const FavoriteBoardInfo({
    required this.fid,
    required this.name,
    required this.icon,
    this.today = '',
    this.threads = '',
    this.favorites = '',
    this.favorited = false,
    this.toggleAction = '',
  });

  FavoriteBoardInfo copyWith({
    int? fid, String? name, String? icon, String? today, String? threads,
    String? favorites, bool? favorited, String? toggleAction,
  }) => FavoriteBoardInfo(
    fid: fid ?? this.fid,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    today: today ?? this.today,
    threads: threads ?? this.threads,
    favorites: favorites ?? this.favorites,
    favorited: favorited ?? this.favorited,
    toggleAction: toggleAction ?? this.toggleAction,
  );
}

/// 版块收藏（Discuz favorite forum, handlekey=favoriteforum）。
class FavoriteBoardService {
  FavoriteBoardService._();
  static final instance = FavoriteBoardService._();

  static String get _base => SiteConfig.base;

  Future<FavoriteBoardInfo?> fetchBoardInfo(int fid) async {
    if (fid <= 0) return null;
    final url = '${_base}forum-$fid-1.html';
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': _base,
      final cookie = AuthService.instance.authCookie: if (cookie.isNotEmpty) cookie,
    };
    try {
      final resp = await NetClient.retry(() async {
        final client = await NetClient.instance.client;
        return client.get(Uri.parse(url), headers: headers);
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

    String icon = '';
    String name = '';
    String desc = '';
    String today = '';
    String threads = '';
    String favorites = '';
    bool favorited = false;
    String toggleAction = '';

    // 版块标题区 (Comiis N7 模板)
    final tinfo = doc.querySelector('.comiis_lhd_tinfo');
    if (tinfo != null) {
      icon = tinfo.querySelector('.km_img img')?.attributes['src']?.trim() ?? '';
      name = tinfo.querySelector('.km_tit a.km_name')?.text.trim() ?? '';

      // 收藏数
      favorites = tinfo.querySelector('#number_favorite_num')?.text.trim() ??
          tinfo.querySelector('.number_favorite_num')?.text.trim() ??
          '';

      // 版块简介 + 统计（今日 / 主题 / 排名）在两个 .km_txt 里
      final txts = tinfo.querySelectorAll('.km_txt');
      if (txts.isNotEmpty) {
        desc = txts.first.text.trim();
        if (txts.length > 1) {
          final stats = txts.last.text.trim();
          final tRe = RegExp(r'今日\s*[:：]\s*(\d+)');
          final thRe = RegExp(r'(?:主题|帖数)\s*[:：]\s*(\d+)');
          final tMatch = tRe.firstMatch(stats);
          final thMatch = thRe.firstMatch(stats);
          if (tMatch != null) today = tMatch.group(1)!;
          if (thMatch != null) threads = thMatch.group(1)!;
        }
      }

      // 收藏按钮
      final favBtn = tinfo.querySelector('#a_favorite, a.favoriteforum, a[handlekey="favoriteforum"]');
      if (favBtn != null) {
        toggleAction = _absolute(favBtn.attributes['href']?.replaceAll('&amp;', '&') ?? '');
        final btnText = favBtn.text.trim();
        // "+ 收藏" / "立即收藏" → 未收藏; "已收藏" / "取消收藏" → 已收藏
        favorited = RegExp(r'(已收藏|取消收藏|收藏过|favorited)', caseSensitive: true).hasMatch(btnText);
      }
    }

    // 兜底: 没找到 comiis_lhd_tinfo 时用标准 Discuz 头
    if (name.isEmpty) {
      final boardLink = doc.querySelector('a[href*="forum-$fid"], a[href*="fid=$fid"], .forumname a, .xs2 a');
      name = boardLink?.text.trim() ?? '';
    }
    if (favorites.isEmpty) {
      favorites = doc.querySelector('#number_favorite_num, .number_favorite_num')?.text.trim() ?? '';
    }
    if (toggleAction.isEmpty) {
      // 没有 fid 特定按钮时, 尝试找任意 handlekey=favoriteforum 的链接
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (href.contains('type=forum') && href.contains('handlekey=favoriteforum')) {
          toggleAction = _absolute(href);
          favorited = RegExp(r'(已收藏|取消收藏)', caseSensitive: true).hasMatch(a.text.trim());
          break;
        }
      }
    }

    // 解析没拿到 action 但有 formhash 时自己拼一个
    if (toggleAction.isEmpty) {
      final formhash = _globalHash(doc, html);
      if (formhash.isNotEmpty) {
        toggleAction = '${_base}home.php?mod=spacecp&ac=favorite&type=forum&id=$fid&handlekey=favoriteforum&formhash=$formhash&mobile=2';
      }
    }

    return FavoriteBoardInfo(
      fid: fid,
      name: name.isEmpty ? '版块 $fid' : name,
      icon: icon,
      today: today,
      threads: threads,
      favorites: favorites,
      favorited: favorited,
      toggleAction: toggleAction,
    );
  }

  Future<String?> toggle({required int fid, required bool favorite}) async {
    if (fid <= 0) return '版块无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie.isEmpty) return '请先登录论坛';

    // 先抓一次版块页, 同时拿到 formhash / 当前状态 / 真实 toggle URL
    final info = await fetchBoardInfo(fid);
    if (info == null || info.toggleAction.isEmpty) {
      return '无法获取版块收藏接口, 请稍后重试';
    }

    // 如果当前状态和请求一致(已经是目标状态), 就没必要再调, 直接返回
    if (info.favorited == favorite) return null;

    final client = await NetClient.instance.client;
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': '*/*',
      'Referer': '${_base}forum-$fid-1.html',
      'Cookie': cookie,
      'X-Requested-With': 'XMLHttpRequest',
    };

    try {
      final resp = await NetClient.retry(() async {
        try {
          return await client.get(Uri.parse(info.toggleAction), headers: headers);
        } catch (_) {
          return await client.post(Uri.parse(info.toggleAction), headers: headers);
        }
      }).timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return '操作失败 HTTP ${resp.statusCode}';
      final body = NetClient.decode(resp.bodyBytes);
      if (_looksLikeLogin(body)) return '登录态已失效, 请重新登录论坛';
      if (_tokenError(body)) return '操作令牌已失效, 请刷新后重试';
      // Discuz favorite 接口返回 "操作成功" 或 "favorite_succeed"
      if (body.contains('succeed') || body.contains('成功') || body.contains('favorite')) return null;
      return favorite ? '收藏失败, 请稍后重试' : '取消收藏失败, 请稍后重试';
    } catch (_) {
      return '操作失败, 请检查网络后重试';
    }
  }

  static String _globalHash(dom.Document doc, String html) {
    for (final input in doc.querySelectorAll('input[name="formhash"], input[name="hash"]')) {
      final v = input.attributes['value']?.trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final m = RegExp(r'(?:formhash|hash)\s*[=:]\s*["\']([a-zA-Z0-9]{6,})["\']', caseSensitive: false).firstMatch(html);
    return m?.group(1) ?? '';
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
