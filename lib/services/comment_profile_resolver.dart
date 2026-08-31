import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'net_client.dart';

/// Resolves a Discuz author UID when normalized comment HTML no longer
/// contains the original author link.
class CommentProfileResolver {
  CommentProfileResolver._();
  static final instance = CommentProfileResolver._();
  static String get _base => SiteConfig.base;
  final Map<String, int?> _cache = <String, int?>{};

  Future<int?> resolveUid(String username) async {
    final name = username.trim();
    if (name.isEmpty) return null;
    final key = name.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];

    final client = await NetClient.instance.client;
    final urls = <Uri>[
      Uri.parse('${_base}home.php').replace(queryParameters: {
        'mod': 'space',
        'username': name,
        'do': 'profile',
        'mobile': '2',
      }),
      Uri.parse('${_base}home.php').replace(queryParameters: {
        'mod': 'space',
        'username': name,
        'mobile': '2',
      }),
    ];
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
    };

    for (final url in urls) {
      try {
        final response = await NetClient.retry(
          () => client.get(url, headers: headers).timeout(const Duration(seconds: 15)),
          times: 2,
        );
        if (response.statusCode != 200) continue;
        final html = NetClient.decode(response.bodyBytes);
        final uid = _uidFromUrl(response.request?.url.toString() ?? '');
        if (uid != null) {
          _cache[key] = uid;
          return uid;
        }
        final doc = parser.parse(html);
        for (final a in doc.querySelectorAll('a[href]')) {
          final href = a.attributes['href'] ?? '';
          final candidate = _uidFromUrl(href);
          if (candidate != null) {
            final text = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (text.isEmpty || text == name || _looksLikeProfileLink(href)) {
              _cache[key] = candidate;
              return candidate;
            }
          }
        }
        final canonical = doc.querySelector('link[rel="canonical"]')?.attributes['href'] ?? '';
        final canonicalUid = _uidFromUrl(canonical);
        if (canonicalUid != null) {
          _cache[key] = canonicalUid;
          return canonicalUid;
        }
        final meta = doc.querySelector('meta[property="og:url"], meta[name="og:url"]')?.attributes['content'] ?? '';
        final metaUid = _uidFromUrl(meta);
        if (metaUid != null) {
          _cache[key] = metaUid;
          return metaUid;
        }
      } catch (_) {}
    }
    _cache[key] = null;
    return null;
  }

  int? _uidFromUrl(String value) {
    if (value.isEmpty) return null;
    final patterns = <RegExp>[
      RegExp(r'(?:[?&]|%3F|%26)uid(?:=|%3D)(\d+)', caseSensitive: false),
      RegExp(r'(?:^|[/?_-])space-uid-(\d+)', caseSensitive: false),
      RegExp(r'(?:^|[/?_-])space/uid/(\d+)', caseSensitive: false),
      RegExp(r'home\.php[^\s#]*[?&]uid=(\d+)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final uid = int.tryParse(match?.group(1) ?? '');
      if (uid != null && uid > 0) return uid;
    }
    return null;
  }

  bool _looksLikeProfileLink(String href) {
    final lower = href.toLowerCase();
    return lower.contains('home.php?mod=space') || lower.contains('space-uid-') || lower.contains('space/uid/');
  }
}
