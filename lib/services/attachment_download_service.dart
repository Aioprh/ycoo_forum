import 'dart:io';

import 'package:flutter/services.dart';
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'net_client.dart';

class ForumAttachmentInfo {
  final String url;
  final String name;
  final String size;

  const ForumAttachmentInfo({
    required this.url,
    required this.name,
    this.size = '',
  });
}

/// 原生附件下载桥接。
class AttachmentDownloadService {
  AttachmentDownloadService._();
  static final instance = AttachmentDownloadService._();
  static const _channel = MethodChannel('ycoo/attachment_download');

  bool isAttachmentUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (uri.queryParameters['ycoo'] == 'all') return true;
    return _isRealFileAttachment(uri);
  }

  Future<bool> download({
    required String url,
    String? cookie,
    String? referer,
    String? filename,
  }) async {
    if (!Platform.isAndroid) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (uri.queryParameters['ycoo'] == 'all') {
      final tid = int.tryParse(uri.queryParameters['tid'] ?? '') ?? 0;
      if (tid <= 0) return false;
      return downloadAllFromThread(
        tid: tid,
        cookie: cookie,
        referer: referer,
      );
    }
    if (!_isRealFileAttachment(uri)) return false;
    return _enqueue(
      url: uri.toString(),
      cookie: cookie,
      referer: referer,
      filename: filename,
    );
  }

  Future<List<ForumAttachmentInfo>> fetchAttachments({
    required int tid,
    String? cookie,
    String? referer,
  }) async {
    if (tid <= 0) return const [];
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

    for (final pageUrl in candidates) {
      try {
        final response = await NetClient.retry(
          () => client.get(pageUrl, headers: headers).timeout(NetClient.timeout),
        );
        if (response.statusCode != 200) continue;
        final html = NetClient.decode(response.bodyBytes);
        final result = _extractAttachmentInfos(html);
        if (result.isNotEmpty) return result;
      } catch (_) {}
    }
    return const [];
  }

  Future<bool> downloadAllFromThread({
    required int tid,
    String? cookie,
    String? referer,
  }) async {
    if (!Platform.isAndroid || tid <= 0) return false;
    try {
      final attachments = await fetchAttachments(
        tid: tid,
        cookie: cookie,
        referer: referer,
      );
      if (attachments.isEmpty) return false;
      var started = false;
      for (final attachment in attachments) {
        final ok = await _enqueue(
          url: attachment.url,
          cookie: cookie,
          referer: referer ?? SiteConfig.base,
          filename: attachment.name,
        );
        started = started || ok;
      }
      return started;
    } catch (_) {
      return false;
    }
  }

  Set<String> _extractAttachmentUrls(String html) =>
      _extractAttachmentInfos(html).map((e) => e.url).toSet();

  List<ForumAttachmentInfo> _extractAttachmentInfos(String html) {
    final result = <ForumAttachmentInfo>[];
    final seen = <String>{};
    if (html.trim().isEmpty) return result;

    final source = html
        .replaceAll('&amp;', '&')
        .replaceAll('\\/', '/')
        .replaceAll('&#x2F;', '/');
    final doc = parser.parse(source);

    // 关键修复：只读取真正的 <a href="...attachment..."> 附件链接。
    // 绝不能扫描页面所有 http(s) URL，否则正文图片、头像、脚本等也会被误当成附件下载。
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = (anchor.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;
      final url = _normalizeUrl(href);
      final uri = Uri.tryParse(url);
      if (uri == null || !_isRealFileAttachment(uri)) continue;

      final anchorText = _cleanFileName(anchor.text);
      final name = _bestFileName(anchorText, uri);
      if (_looksLikeImageFile(name, uri)) continue;

      // Discuz 页面中同一个附件可能出现下载链接和附件卡片两个入口，按 aid 去重。
      final key = uri.queryParameters['aid']?.trim() ?? url;
      if (!seen.add(key)) continue;

      final size = _findAttachmentSize(anchor);
      result.add(ForumAttachmentInfo(url: url, name: name, size: size));
    }
    // ycoo/Discuz 还有一类真实附件不会被渲染成 <a href>：
    // 正文或服务端源码可能保留 [attach]URL[/attach] 标记。
    // 这里补充解析它，但仍严格经过 _isRealFileAttachment，避免把图片/普通链接当附件。
    final attachRe = RegExp(r'\\[attach\\]\\s*(https?://[^\\s\\]<>]+)\\s*\\[/attach\\]', caseSensitive: false);
    for (final match in attachRe.allMatches(source)) {
      final raw = match.group(1) ?? '';
      final url = _normalizeUrl(raw);
      final uri = Uri.tryParse(url);
      if (uri == null || !_isRealFileAttachment(uri)) continue;
      if (_looksLikeImageFile('', uri)) continue;
      final key = uri.queryParameters['aid']?.trim() ?? url;
      if (!seen.add(key)) continue;
      result.add(ForumAttachmentInfo(
        url: url,
        name: _bestFileName('', uri),
        size: '',
      ));
    }

    return result;
  }

  bool _isRealFileAttachment(Uri uri) {
    final path = uri.path.toLowerCase();
    final query = uri.queryParameters;
    final mod = (query['mod'] ?? '').toLowerCase();
    final aid = query['aid']?.trim() ?? '';
    final isAttachmentPath =
        path.endsWith('attachment.php') ||
        mod == 'attachment' ||
        path.contains('/attachment/');
    final isDownloadPath = path.contains('/download/');
    if (!isAttachmentPath && !isDownloadPath) return false;

    // Discuz 的 attachment.php / mod=attachment 通常必须带 aid；
    // 但部分页面会直接给 /attachment/.../file.txt 这类真实文件地址，
    // 这时没有 aid 也应识别为附件。
    if (aid.isEmpty && !(path.contains('/attachment/') || isDownloadPath)) {
      return false;
    }

    if ((query['request'] ?? '').toLowerCase() == 'yes') return true;
    final f = query['_f']?.trim() ?? '';
    if (f.isNotEmpty) return true;
    if (query.containsKey('filename') ||
        query.containsKey('file') ||
        query.containsKey('name')) {
      return true;
    }

    // 兼容没有 _f/request 标记、但路径本身已经明确带有文件扩展名的附件。
    return _hasKnownFileExtension(path);
  }

  bool _hasKnownFileExtension(String path) {
    return RegExp(
      r'\.(?:txt|json|xml|csv|md|log|zip|rar|7z|tar|gz|bz2|xz|apk|xapk|apks|ipa|pdf|epub|mobi|azw|azw3|doc|docx|xls|xlsx|ppt|pptx|rtf|mp3|wav|flac|m4a|ogg|mp4|m4v|mkv|avi|mov|webm)(?:$|[?#])',
      caseSensitive: false,
    ).hasMatch(path);
  }

  String _normalizeUrl(String raw) {
    var value = raw.trim();
    value = value.replaceAll('&amp;', '&').replaceAll('\\/', '/');
    value = value.replaceFirst(RegExp(r'^javascript:\s*', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'[\)\];,]+$'), '');
    if (value.startsWith('//')) value = 'https:$value';
    if (!(value.startsWith('http://') || value.startsWith('https://'))) {
      value = value.startsWith('/')
          ? '${SiteConfig.base}${value.substring(1)}'
          : SiteConfig.resolve(value);
    }
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  String _cleanFileName(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _bestFileName(String anchorText, Uri uri) {
    if (anchorText.isNotEmpty &&
        !anchorText.contains('下载') &&
        !anchorText.contains('附件') &&
        !anchorText.contains('保存到相册')) {
      return anchorText;
    }
    for (final key in const ['filename', 'file', 'name']) {
      final value = uri.queryParameters[key]?.trim() ?? '';
      if (value.isNotEmpty) return _cleanFileName(value);
    }
    final f = uri.queryParameters['_f']?.trim() ?? '';
    if (f.startsWith('.') && f.length <= 12) return '论坛附件$f';

    // 直接 /attachment/.../小说目录.txt 形式没有查询参数时，
    // 从 URL 最后一段取得真实文件名，保留 .txt/.json/.zip 等扩展名。
    final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
    if (segments.isNotEmpty) {
      final last = _cleanFileName(Uri.decodeComponent(segments.last));
      if (_hasKnownFileExtension(last) && !_looksLikeGenericAttachmentName(last)) {
        return last;
      }
    }
    return '论坛附件';
  }

  bool _looksLikeGenericAttachmentName(String value) {
    final lower = value.toLowerCase();
    return lower == 'attachment' || lower == 'download' || lower == 'attachment.php';
  }

  String _findAttachmentSize(dynamic anchor) {
    try {
      var e = anchor;
      for (var i = 0; i < 4 && e != null; i++, e = e.parent) {
        final text = _cleanFileName(e.text ?? '');
        final match = RegExp(r'(\d+(?:\.\d+)?\s*(?:B|KB|MB|GB))', caseSensitive: false).firstMatch(text);
        if (match != null) return match.group(1)!;
      }
    } catch (_) {}
    return '';
  }

  bool _looksLikeImageFile(String name, Uri uri) {
    final f = uri.queryParameters['_f']?.toLowerCase() ?? '';
    final value = '$name $f'.toLowerCase();
    return RegExp(r'\.(?:jpe?g|png|gif|webp|bmp|svg|heic|heif|avif)(?:\b|$)').hasMatch(value);
  }

  Future<bool> _enqueue({
    required String url,
    String? cookie,
    String? referer,
    String? filename,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('download', {
        'url': url,
        'cookie': cookie ?? '',
        'referer': referer ?? SiteConfig.base,
        'filename': filename ?? '',
      });
      return result == true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}