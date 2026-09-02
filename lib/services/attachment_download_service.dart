import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'net_client.dart';

class ForumAttachmentInfo {
  final String url;
  final String name;
  final String size;
  final String downloads;

  const ForumAttachmentInfo({
    required this.url,
    required this.name,
    this.size = '',
    this.downloads = '',
  });
}

class _AttachMeta {
  final String aid;
  final String title;
  final String size;
  final String downloads;
  const _AttachMeta({required this.aid, this.title = '', this.size = '', this.downloads = ''});
}

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

  Future<bool> download({required String url, String? cookie, String? referer, String? filename}) async {
    if (!Platform.isAndroid) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (uri.queryParameters['ycoo'] == 'all') {
      final tid = int.tryParse(uri.queryParameters['tid'] ?? '') ?? 0;
      if (tid <= 0) return false;
      return downloadAllFromThread(tid: tid, cookie: cookie, referer: referer);
    }
    if (!_isRealFileAttachment(uri)) return false;
    return _enqueue(url: uri.toString(), cookie: cookie, referer: referer, filename: filename);
  }

  Future<List<ForumAttachmentInfo>> fetchAttachments({required int tid, String? cookie, String? referer}) async {
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
      Uri.parse('${SiteConfig.base}forum.php').replace(queryParameters: {'mobile': '2', 'mod': 'viewthread', 'tid': '$tid', 'page': '1', '_ycoo_attachment_list': DateTime.now().millisecondsSinceEpoch.toString()}),
      Uri.parse('${SiteConfig.base}thread-$tid-1-1.html').replace(queryParameters: {'mobile': '2', '_ycoo_attachment_list': DateTime.now().millisecondsSinceEpoch.toString()}),
    ];
    for (final pageUrl in candidates) {
      try {
        final response = await NetClient.retry(() => client.get(pageUrl, headers: headers).timeout(NetClient.timeout));
        if (response.statusCode != 200) continue;
        final result = _extractAttachmentInfos(NetClient.decode(response.bodyBytes));
        if (result.isNotEmpty) return result;
      } catch (_) {}
    }
    return const [];
  }

  Future<bool> downloadAllFromThread({required int tid, String? cookie, String? referer}) async {
    if (!Platform.isAndroid || tid <= 0) return false;
    try {
      final attachments = await fetchAttachments(tid: tid, cookie: cookie, referer: referer);
      if (attachments.isEmpty) return false;
      var started = false;
      for (final attachment in attachments) {
        final ok = await _enqueue(url: attachment.url, cookie: cookie, referer: referer ?? SiteConfig.base, filename: attachment.name);
        started = started || ok;
      }
      return started;
    } catch (_) {
      return false;
    }
  }

  List<ForumAttachmentInfo> _extractAttachmentInfos(String html) {
    final result = <ForumAttachmentInfo>[];
    final seen = <String>{};
    if (html.trim().isEmpty) return result;
    final source = html.replaceAll('&amp;', '&').replaceAll('\\/', '/').replaceAll('&#x2F;', '/');
    final doc = parser.parse(source);

    final tipInfo = <String, _AttachMeta>{};
    for (final element in doc.querySelectorAll('[id]')) {
      final id = element.id ?? '';
      if (!RegExp(r'^(?:aid|aimg)_?\d+_menu$').hasMatch(id)) continue;
      final aux = _parseTipMeta(element);
      if (aux != null) tipInfo[aux.aid] = aux;
    }

    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = (anchor.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;
      final url = _normalizeUrl(href);
      final uri = Uri.tryParse(url);
      if (uri == null || !_isRealFileAttachment(uri)) continue;
      final name = _bestFileName(_cleanFileName(anchor.text), uri);
      if (_looksLikeImageFile(name, uri)) continue;
      final key = uri.queryParameters['aid']?.trim() ?? url;
      if (!seen.add(key)) continue;
      final numAid = _anchorNumericAid(anchor, uri);
      final meta = numAid.isEmpty ? null : tipInfo[numAid];
      final resolvedName = meta?.title.isNotEmpty == true ? meta!.title : name;
      result.add(ForumAttachmentInfo(
        url: url,
        name: _ensureFilenameExtension(resolvedName, uri),
        size: meta?.size ?? _findAttachmentSize(anchor),
        downloads: meta?.downloads ?? '',
      ));
    }

    final attachRe = RegExp(r'\[attach(?:ment)?\]\s*(https?://[^\s\[\]<>]+)\s*\[/attach(?:ment)?\]', caseSensitive: false);
    for (final m in attachRe.allMatches(source)) {
      final url = _normalizeUrl(m.group(1)!);
      final uri = Uri.tryParse(url);
      if (uri == null || !_isRealFileAttachment(uri)) continue;
      final name = _bestFileName('', uri);
      if (_looksLikeImageFile(name, uri)) continue;
      final key = uri.queryParameters['aid']?.trim() ?? url;
      if (!seen.add(key)) continue;
      result.add(ForumAttachmentInfo(url: url, name: _ensureFilenameExtension(name, uri)));
    }
    return result;
  }

  bool _isRealFileAttachment(Uri uri) {
    final path = uri.path.toLowerCase();
    final query = uri.queryParameters;
    final mod = (query['mod'] ?? '').toLowerCase();
    final aid = query['aid']?.trim() ?? '';
    final isAttachmentPath = path.endsWith('attachment.php') || mod == 'attachment' || path.contains('/attachment/');
    final isDownloadPath = path.contains('/download/');
    if (!isAttachmentPath && !isDownloadPath) return false;
    if (aid.isEmpty && !(path.contains('/attachment/') || isDownloadPath)) return false;
    if ((query['request'] ?? '').toLowerCase() == 'yes') return true;
    final f = query['_f']?.trim() ?? '';
    if (f.isNotEmpty) return true;
    if (query.containsKey('filename') || query.containsKey('file') || query.containsKey('name')) return true;
    if (aid.isNotEmpty) return true;
    return _hasKnownFileExtension(path);
  }

  bool _hasKnownFileExtension(String path) => RegExp(r'\.(?:txt|json|xml|csv|md|log|zip|rar|7z|tar|gz|bz2|xz|apk|xapk|apks|ipa|pdf|epub|mobi|azw|azw3|doc|docx|xls|xlsx|ppt|pptx|rtf|mp3|wav|flac|m4a|ogg|mp4|m4v|mkv|avi|mov|webm)(?:$|[?#])', caseSensitive: false).hasMatch(path);

  String _normalizeUrl(String raw) {
    var value = raw.trim().replaceAll('&amp;', '&').replaceAll('\\/', '/');
    value = value.replaceFirst(RegExp(r'^javascript:\s*', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'[\)\];,]+$'), '');
    if (value.startsWith('//')) value = 'https:$value';
    if (!(value.startsWith('http://') || value.startsWith('https://'))) value = value.startsWith('/') ? '${SiteConfig.base}${value.substring(1)}' : SiteConfig.resolve(value);
    try { return Uri.decodeFull(value); } catch (_) { return value; }
  }

  String _cleanFileName(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _bestFileName(String anchorText, Uri uri) {
    if (anchorText.isNotEmpty && !anchorText.contains('下载') && !anchorText.contains('附件') && !anchorText.contains('保存到相册')) return anchorText;
    for (final key in const ['filename', 'file', 'name']) {
      final value = uri.queryParameters[key]?.trim() ?? '';
      if (value.isNotEmpty) return _cleanFileName(value);
    }
    final f = _cleanFileName(uri.queryParameters['_f']?.trim() ?? '');
    if (f.isNotEmpty) {
      // Discuz 不同版本可能传“json”、“.json”或直接传完整文件名。
      if (_hasKnownFileExtension(f) || f.startsWith('.')) {
        return f.startsWith('.') ? '论坛附件$f' : f;
      }
      if (RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(f)) return '论坛附件.$f';
    }
    final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
    if (segments.isNotEmpty) {
      final last = _cleanFileName(Uri.decodeComponent(segments.last));
      if (_hasKnownFileExtension(last) && !{'attachment','download','attachment.php'}.contains(last.toLowerCase())) return last;
    }
    return '论坛附件';
  }

  String _ensureFilenameExtension(String name, Uri uri) {
    var value = _cleanFileName(name);
    if (value.isEmpty) value = '论坛附件';
    if (_hasKnownFileExtension(value)) return value;
    final f = _cleanFileName(uri.queryParameters['_f']?.trim() ?? '');
    if (f.isNotEmpty) {
      if (_hasKnownFileExtension(f) && !f.startsWith('.')) {
        if (value == '论坛附件') return f;
        if (!value.toLowerCase().endsWith(f.toLowerCase())) return '$value.${f.split('.').last}';
      }
      if (f.startsWith('.') && f.length <= 12 && RegExp(r'^\.[A-Za-z0-9]+$').hasMatch(f)) return '$value$f';
      if (RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(f)) return '$value.$f';
    }
    return value;
  }

  String _findAttachmentSize(dynamic anchor) {
    try {
      var e = anchor;
      for (var i = 0; i < 4 && e != null; i++, e = e.parent) {
        final match = RegExp(r'(\d+(?:\.\d+)?\s*(?:B|KB|MB|GB))', caseSensitive: false).firstMatch(_cleanFileName(e.text ?? ''));
        if (match != null) return match.group(1)!;
      }
    } catch (_) {}
    return '';
  }

  _AttachMeta? _parseTipMeta(dom.Element tip) {
    final id = tip.id ?? '';
    final idMatch = RegExp(r'(?:aid|aimg)_?(\d+)_menu').firstMatch(id);
    if (idMatch == null) return null;
    final aid = idMatch.group(1)!;
    String title = '';

    final candidates = <String>[
      tip.querySelector('strong')?.text ?? '',
      tip.querySelector('[title]')?.attributes['title'] ?? '',
      tip.querySelector('a')?.text ?? '',
    ];
    for (final candidate in candidates) {
      final cleaned = _cleanFileName(candidate);
      if (_isUsableAttachmentTitle(cleaned)) {
        title = cleaned;
        break;
      }
    }

    String size = '';
    String downloads = '';
    final text = _cleanFileName(tip.text);
    final sizeMatch = RegExp(r'(\d+(?:\.\d+)?\s*(?:B|KB|MB|GB))', caseSensitive: false).firstMatch(text);
    if (sizeMatch != null) size = sizeMatch.group(1)!;
    final dlMatch = RegExp(r'下载次数[:：]?\s*(\d+)').firstMatch(text);
    if (dlMatch != null) downloads = '下载 ${dlMatch.group(1)!} 次';

    if (title.isEmpty && text.isNotEmpty) {
      var candidate = text
          .replaceFirst(RegExp(r'\s*\(?\s*\d+(?:\.\d+)?\s*(?:B|KB|MB|GB).*$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*下载次数[:：]?\s*\d+.*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[\(（].*?[\)）]'), '')
          .trim();
      if (_isUsableAttachmentTitle(candidate)) title = candidate;
    }

    return _AttachMeta(aid: aid, title: title, size: size, downloads: downloads);
  }

  bool _isUsableAttachmentTitle(String value) {
    if (value.isEmpty) return false;
    if (value == '论坛附件' || value == '附件' || value == '下载' || value == '点击下载') return false;
    if (RegExp(r'^\d+(?:\.\d+)?\s*(?:B|KB|MB|GB)$', caseSensitive: false).hasMatch(value)) return false;
    return !value.contains('下载次数');
  }

  String _anchorNumericAid(dom.Element anchor, Uri uri) {
    final idMatch = RegExp(r'(?:aid_?|aimg_?)(\d+)').firstMatch(anchor.id ?? '');
    if (idMatch != null) return idMatch.group(1)!;
    final raw = uri.queryParameters['aid'] ?? '';
    if (raw.isEmpty) return '';
    String padded = raw;
    while (padded.length % 4 != 0) padded += '=';
    try {
      final bytes = base64.decode(padded);
      final text = utf8.decode(bytes);
      final seg = text.split('|').first;
      if (int.tryParse(seg) != null) return seg;
    } catch (_) {}
    return '';
  }

  bool _looksLikeImageFile(String name, Uri uri) => RegExp(r'\.(?:jpe?g|png|gif|webp|bmp|svg|heic|heif|avif)(?:\b|$)').hasMatch('$name ${uri.queryParameters['_f'] ?? ''}'.toLowerCase());

  Future<bool> _enqueue({required String url, String? cookie, String? referer, String? filename}) async {
    try {
      final result = await _channel.invokeMethod<bool>('download', {'url': url, 'cookie': cookie ?? '', 'referer': referer ?? SiteConfig.base, 'filename': filename ?? ''});
      return result == true;
    } on PlatformException { return false; } catch (_) { return false; }
  }
}
