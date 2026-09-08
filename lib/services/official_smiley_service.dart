import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// 源论坛自身的表情项。
/// code 是提交给 Discuz/Comiis 的原始 BBCode，imageUrl 是论坛实际表情资源地址。
class OfficialSmiley {
  const OfficialSmiley({required this.code, required this.imageUrl});

  final String code;
  final String imageUrl;
}

/// 从源论坛发帖页面读取当前站点实际启用的表情。
///
/// 不内置 Unicode Emoji，也不硬编码第三方表情包；每个版块打开表情面板时，
/// 直接解析论坛自己的 newthread 页面，因此表情图片、代码和站点配置保持一致。
class OfficialSmileyService {
  OfficialSmileyService._();
  static final OfficialSmileyService instance = OfficialSmileyService._();

  final Map<int, List<OfficialSmiley>> _cache = <int, List<OfficialSmiley>>{};

  Future<List<OfficialSmiley>> fetch(int fid, {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.containsKey(fid)) return _cache[fid]!;
    final client = await NetClient.instance.client;
    final uri = Uri.parse(SiteConfig.resolve('forum.php')).replace(
      queryParameters: <String, String>{
        'mod': 'post',
        'action': 'newthread',
        'fid': '$fid',
        'mobile': '2',
        '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': SiteConfig.resolve('forum-$fid-1.html'),
    };
    final cookie = AuthService.instance.authCookie;
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;

    final response = await NetClient.retry(
      () => client.get(uri, headers: headers).timeout(NetClient.timeout),
    );
    if (response.statusCode != 200) {
      throw Exception('表情加载失败 HTTP ${response.statusCode}');
    }

    final html = NetClient.decode(response.bodyBytes);
    final doc = parser.parse(html);
    final result = <OfficialSmiley>[];
    final seen = <String>{};

    for (final anchor in doc.querySelectorAll('a[onclick]')) {
      final onclick = anchor.attributes['onclick'] ?? '';
      if (!RegExp(r'(?:smilies|smilie|smiley)', caseSensitive: false).hasMatch(onclick)) continue;
      final code = _extractCode(onclick);
      if (code == null || code.isEmpty || !seen.add(code)) continue;
      final image = anchor.querySelector('img');
      final source = image?.attributes['data-src'] ?? image?.attributes['src'] ?? '';
      final imageUrl = SiteConfig.resolve(source);
      if (imageUrl.isEmpty) continue;
      result.add(OfficialSmiley(code: code, imageUrl: imageUrl));
    }

    // 某些 Comiis 版本把 onclick 放在图片的父级之外，补一次基于源码的兜底解析。
    if (result.isEmpty) {
      final matches = RegExp(
        r'''(?is)<a\b[^>]*onclick\s*=\s*(["'])(.*?)(?:\1)[^>]*>\s*<img\b[^>]*(?:data-src|src)\s*=\s*(["'])(.*?)\3[^>]*>''',
      ).allMatches(html);
      for (final match in matches) {
        final onclick = match.group(2) ?? '';
        if (!RegExp(r'(?:smilies|smilie|smiley)', caseSensitive: false).hasMatch(onclick)) continue;
        final code = _extractCode(onclick);
        final source = match.group(4) ?? '';
        if (code == null || code.isEmpty || source.isEmpty || !seen.add(code)) continue;
        result.add(OfficialSmiley(code: code, imageUrl: SiteConfig.resolve(source)));
      }
    }

    if (result.isEmpty) throw Exception('论坛未返回可用表情');
    _cache[fid] = List.unmodifiable(result);
    return _cache[fid]!;
  }

  String? _extractCode(String onclick) {
    final patterns = <RegExp>[
      RegExp(r'''(?:comiis_addsmilies|insertSmilie|insertSmiley|addsmilies)\s*\(\s*["']((?:\\.|[^"'])+)["']''', caseSensitive: false),
      RegExp(r'''(?:smilie|smiley|smilies)[^\(]*\(\s*["']((?:\\.|[^"'])+)["']''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final value = pattern.firstMatch(onclick)?.group(1);
      if (value != null && value.isNotEmpty) return value.replaceAll(r"\'", "'").replaceAll(r'\"', '"');
    }
    return null;
  }

  void clear(int fid) => _cache.remove(fid);
  void clearAll() => _cache.clear();
}
