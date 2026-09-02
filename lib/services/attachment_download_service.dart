import 'dart:io';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'net_client.dart';

/// 原生附件下载桥接。
class AttachmentDownloadService {
  AttachmentDownloadService._();
  static final instance = AttachmentDownloadService._();
  static const _channel = MethodChannel('ycoo/attachment_download');

  bool isAttachmentUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    final value = url.toLowerCase();
    final path = u.path.toLowerCase();
    final query = u.query.toLowerCase();
    return path.contains('attachment.php') ||
        query.contains('mod=attachment') ||
        query.contains('aid=') ||
        query.contains('request=yes') ||
        path.contains('/attachment/') ||
        path.contains('/download/') ||
        value.contains('[attach]');
  }

  Future<bool> download({required String url, String? cookie, String? referer}) async {
    if (!Platform.isAndroid) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    if (uri.queryParameters['ycoo'] == 'all') {
      final tid = int.tryParse(uri.queryParameters['tid'] ?? '') ?? 0;
      if (tid <= 0) return false;
      return downloadAllFromThread(tid: tid, cookie: cookie, referer: referer);
    }

    return _enqueue(url: url, cookie: cookie, referer: referer);
  }

  Future<bool> downloadAllFromThread({
    required int tid,
    String? cookie,
    String? referer,
  }) async {
    if (!Platform.isAndroid || tid <= 0) return false;
    final client = await NetClient.instance.client;
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': referer ?? SiteConfig.base,
      if ((cookie ?? '').isNotEmpty) 'Cookie': cookie!,
    };

    final candidates = <Uri>[
      Uri.parse('${SiteConfig.base}forum.php').replace(queryParameters: {
        'mod': 'viewthread',
        'tid': '$tid',
        'page': '1',
        '_ycoo_attachment_list': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
      Uri.parse('${SiteConfig.base}thread-$tid-1-1.html').replace(queryParameters: {
        '_ycoo_attachment_list': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
    ];

    try {
      final links = <String>{};
      for (final pageUrl in candidates) {
        try {
          final response = await NetClient.retry(
            () => client.get(pageUrl, headers: headers).timeout(NetClient.timeout),
          );
          if (response.statusCode != 200) continue;
          final html = NetClient.decode(response.bodyBytes);
          links.addAll(_extractAttachmentUrls(html));
          if (links.isNotEmpty) break;
        } catch (_) {}
      }

      if (links.isEmpty) return false;
      var started = false;
      for (final url in links) {
        try {
          final ok = await _enqueue(
            url: url,
            cookie: cookie,
            referer: referer ?? SiteConfig.base,
          );
          started = started || ok;
        } catch (_) {}
      }
      return started;
    } catch (_) {
      return false;
    }
  }

  Set<String> _extractAttachmentUrls(String html) {
    final result = <String>{};
    if (html.trim().isEmpty) return result;

    final source = html
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('\\/', '/');

    final doc = parser.parse(source);
    final elements = doc.querySelectorAll(
      'a[href], [href], [data-url], [data-href], [data-src], '
      '[onclick], [comiis_loadimages], [src]',
    );
    for (final e in elements) {
      for (final key in const [
        'href',
        'data-url',
        'data-href',
        'data-src',
        'src',
        'onclick',
        'comiis_loadimages',
      ]) {
        final value = e.attributes[key];
        if (value == null || value.trim().isEmpty) continue;
        _addCandidate(result, value);
      }
    }

    // 兼容 [attach]URL[/attach]、绝对 URL 和 Discuz 附件 URL。
    final absolutePattern = RegExp(r'(?:https?:)?//[^\s<>]+', caseSensitive: false);
    for (final match in absolutePattern.allMatches(source)) {
      _addCandidate(result, match.group(0) ?? '');
    }

    final attachmentPattern = RegExp(
      r'(?:forum\.php|attachment\.php)\?[^\s<>]+',
      caseSensitive: false,
    );
    for (final match in attachmentPattern.allMatches(source)) {
      _addCandidate(result, match.group(0) ?? '');
    }

    return result;
  }

  void _addCandidate(Set<String> out, String raw) {
    var value = raw.trim();
    if (value.isEmpty) return;

    // onclick 常见形式会把 URL 放在单/双引号中；先从属性值中抽取 URL。
    final absolutePattern = RegExp(r'(?:https?:)?//[^\s<>]+', caseSensitive: false);
    final attachmentPattern = RegExp(
      r'(?:forum\.php|attachment\.php)\?[^\s<>]+',
      caseSensitive: false,
    );
    final matches = <String>{};
    for (final match in absolutePattern.allMatches(value)) {
      matches.add(match.group(0) ?? '');
    }
    for (final match in attachmentPattern.allMatches(value)) {
      matches.add(match.group(0) ?? '');
    }

    if (matches.isEmpty) {
      _addNormalized(out, value);
      return;
    }
    for (final match in matches) {
      _addNormalized(out, match);
    }
  }

  void _addNormalized(Set<String> out, String raw) {
    var value = raw.trim();
    if (value.isEmpty) return;

    value = value
        .replaceAll('&amp;', '&')
        .replaceAll('\\/', '/')
        .replaceFirst(RegExp(r'^javascript:\s*', caseSensitive: false), '');

    // URL 被 onclick 包裹时，去掉尾部引号、括号和分号。
    value = value.replaceAll(RegExp(r'[\"\'\)\];,]+$'), '');
    try {
      value = Uri.decodeFull(value);
    } catch (_) {}

    if (value.startsWith('//')) value = 'https:$value';
    if (!(value.startsWith('http://') || value.startsWith('https://'))) {
      if (value.startsWith('/')) {
        value = SiteConfig.base + value.substring(1);
      } else {
        value = SiteConfig.resolve(value);
      }
    }

    final uri = Uri.tryParse(value);
    if (uri == null) return;
    final path = uri.path.toLowerCase();
    final query = uri.query.toLowerCase();
    if (path.contains('attachment.php') ||
        query.contains('mod=attachment') ||
        query.contains('aid=') ||
        query.contains('request=yes') ||
        path.contains('/attachment/') ||
        path.contains('/download/')) {
      out.add(value);
    }
  }

  Future<bool> _enqueue({
    required String url,
    String? cookie,
    String? referer,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('download', {
        'url': url,
        'cookie': cookie ?? '',
        'referer': referer ?? SiteConfig.base,
      });
      return result == true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
