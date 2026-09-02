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

  const ForumAttachmentInfo({required this.url, required this.name, this.size = '', this.downloads = ''});
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
      Uri.parse('${SiteConfig.base}forum.php').replace(queryParameters: {
        'mobile': '2', 'mod': 'viewthread', 'tid': '$tid', 'page': '1',
        '_ycoo_attachment_list': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
      Uri.parse('${SiteConfig.base}thread-$tid-1-1.html').replace(queryParameters: {
        'mobile': '2', '_ycoo_attachment_list': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
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
    final attachments = await fetchAttachments(tid: tid, cookie: cookie, referer: referer);
    if (attachments.isEmpty) return false;
    var started = false;
    for (final attachment in attachments) {
      final ok = await _enqueue(url: attachment.url, cookie: cookie, referer: referer ?? SiteConfig.base, filename: attachment.name);
      started = started || ok;
    }
    return started;
  }

  List<ForumAttachmentInfo> _extractAttachmentInfos(String html) {
    final result = <ForumAttachmentInfo>[];
    final seen = <String>{};
    if (html.trim().isEmpty) return result;
    final source = html.replaceAll('&amp;', '&').replaceAll('\\/', '/').replaceAll('&#x2F;', '/');
    final doc = parser.parse(source);

    final tipInfo = <String, _AttachMeta>{};
    for (final element in doc.querySelectorAll('[id]')) {
      final id = element.id;
      if (!RegExp(r'^(?:aid|aimg)_?\d+_menu$').hasMatch(id)) continue;
      final meta = _parseTipMeta(element);
      if (meta != null) tipInfo[meta.aid] = meta;
    }

    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = (anchor.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;
      final url = _normalizeUrl(href);
      final uri = Uri.tryParse(url);
      if (uri == null || !_isRealFileAttachment(uri)) continue;
      if (_looksLikeImageFile('', uri) && !_hasNonImageName(anchor.text)) continue;

      final aid = _anchorNumericAid(anchor, uri);
      _AttachMeta? meta = aid.isEmpty ? null : tipInfo[aid];
      meta ??= _nearestTipMeta(anchor, tipInfo);
      if (meta == null && tipInfo.length == 1) meta = tipInfo.values.first;

      var name = _bestFileName(_cleanFileName(anchor.text), anchor, uri);
      if (meta?.title.isNotEmpty == true) name = meta!.title;
      name = _ensureFilenameExtension(name, uri);
      if (_looksLikeImageFile(name, uri)) continue;

      final key = uri.queryParameters['aid']?.trim() ?? url;
      if (!seen.add(key)) continue;
      result.add(ForumAttachmentInfo(
        url: url,
        name: name,
        size: meta?.size ?? _findAttachmentSize(anchor),
        downloads: meta?.downloads ?? '',
      ));
    }

    final attachRe = RegExp(r'\[attach(?:ment)?\]\s*(https?://[^\s\[\]<>]+)\s*\[/attach(?:ment)?\]', caseSensitive: false);
    for (final m in attachRe.allMatches(source)) {
      final url = _normalizeUrl(m.group(1)!);
      final uri = Uri.tryParse(url);
      if (uri == null || !_isRealFileAttachment(uri)) continue;
      final name = _ensureFilenameExtension(_bestFileName('', null, uri), uri);
      if (_looksLikeImageFile(name, uri)) continue;
      final key = uri.queryParameters['aid']?.trim() ?? url;
      if (!seen.add(key)) continue;
      result.add(ForumAttachmentInfo(url: url, name: name));
    }
    return result;
  }

  bool _isRealFileAttachment(Uri uri) {
    final path = uri.path.toLowerCase();
    final q = uri.queryParameters;
    final mod = (q['mod'] ?? '').toLowerCase();
    final aid = q['aid']?.trim() ?? '';
    final attachmentPath = path.endsWith('attachment.php') || mod == 'attachment' || path.contains('/attachment/');
    final downloadPath = path.contains('/download/');
    if (!attachmentPath && !downloadPath) return false;
    if (aid.isEmpty && !path.contains('/attachment/') && !downloadPath) return false;
    return (q['request'] ?? '').toLowerCase() == 'yes' || (q['_f'] ?? '').isNotEmpty ||
        q.containsKey('filename') || q.containsKey('file') || q.containsKey('name') || aid.isNotEmpty || _hasKnownFileExtension(path);
  }

  bool _hasKnownFileExtension(String value) => RegExp(r'\.(?:txt|json|xml|csv|md|log|zip|rar|7z|tar|gz|bz2|xz|apk|xapk|apks|ipa|pdf|epub|mobi|azw|azw3|doc|docx|xls|xlsx|ppt|pptx|rtf|mp3|wav|flac|m4a|ogg|mp4|m4v|mkv|avi|mov|webm)(?:$|[?#])', caseSensitive: false).hasMatch(value);

  String _normalizeUrl(String raw) {
    var value = raw.trim().replaceAll('&amp;', '&').replaceAll('\\/', '/');
    value = value.replaceFirst(RegExp(r'^javascript:\s*', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'[\)\];,]+$'), '');
    if (value.startsWith('//')) value = 'https:$value';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = value.startsWith('/') ? '${SiteConfig.base}${value.substring(1)}' : SiteConfig.resolve(value);
    }
    try { return Uri.decodeFull(value); } catch (_) { return value; }
  }

  String _cleanFileName(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _bestFileName(String anchorText, dom.Element? anchor, Uri uri) {
    final candidates = <String>[
      anchorText,
      if (anchor != null) ...[
        anchor.attributes['data-filename'] ?? '',
        anchor.attributes['data-name'] ?? '',
        anchor.attributes['data-title'] ?? '',
        anchor.attributes['filename'] ?? '',
        anchor.attributes['title'] ?? '',
      ],
    ];
    for (final candidate in candidates) {
      final value = _cleanFileName(candidate);
      if (_isUsableAttachmentTitle(value)) return value;
    }
    for (final key in const ['filename', 'file', 'name']) {
      final value = _cleanFileName(uri.queryParameters[key] ?? '');
      if (_isUsableAttachmentTitle(value)) return value;
    }
    final f = _cleanFileName(uri.queryParameters['_f'] ?? '');
    if (_hasKnownFileExtension(f)) return f;
    if (f.startsWith('.') && f.length <= 12) return '论坛附件$f';
    if (RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(f)) return '论坛附件.$f';
    final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
    if (segments.isNotEmpty) {
      final last = _cleanFileName(Uri.decodeComponent(segments.last));
      if (_hasKnownFileExtension(last)) return last;
    }
    return '论坛附件';
  }

  _AttachMeta? _nearestTipMeta(dom.Element anchor, Map<String, _AttachMeta> tipInfo) {
    dom.Element? node = anchor;
    for (var depth = 0; depth < 6 && node != null; depth++, node = node.parent) {
      final id = node.id;
      final m = RegExp(r'^(?:aid|aimg)_?(\d+)_menu$').firstMatch(id);
      if (m != null && tipInfo.containsKey(m.group(1))) return tipInfo[m.group(1)];
      for (final child in node.querySelectorAll('[id]')) {
        final cm = RegExp(r'^(?:aid|aimg)_?(\d+)_menu$').firstMatch(child.id);
        if (cm != null && tipInfo.containsKey(cm.group(1))) return tipInfo[cm.group(1)];
      }
    }
    return null;
  }

  _AttachMeta? _parseTipMeta(dom.Element tip) {
    final idMatch = RegExp(r'(?:aid|aimg)_?(\d+)_menu$').firstMatch(tip.id);
    if (idMatch == null) return null;
    final aid = idMatch.group(1)!;
    String title = '';
    final attrs = <String?>[
      tip.attributes['data-filename'], tip.attributes['data-name'], tip.attributes['data-title'],
      tip.attributes['filename'], tip.attributes['name'], tip.attributes['title'], tip.attributes['value'], tip.attributes['alt'],
      tip.querySelector('[data-filename]')?.attributes['data-filename'],
      tip.querySelector('[data-name]')?.attributes['data-name'],
      tip.querySelector('[title]')?.attributes['title'],
      tip.querySelector('strong')?.text,
      tip.querySelector('a')?.text,
    ];
    for (final candidate in attrs) {
      final value = _cleanFileName(candidate ?? '');
      if (_isUsableAttachmentTitle(value)) { title = value; break; }
    }
    final text = _cleanFileName(tip.text);
    final size = RegExp(r'(\d+(?:\.\d+)?\s*(?:B|KB|MB|GB))', caseSensitive: false).firstMatch(text)?.group(1) ?? '';
    final downloads = RegExp(r'下载次数[:：]?\s*(\d+)').firstMatch(text)?.group(1);
    return _AttachMeta(aid: aid, title: title, size: size, downloads: downloads == null ? '' : '下载 $downloads 次');
  }

  bool _isUsableAttachmentTitle(String value) {
    if (value.isEmpty || value == '论坛附件' || value == '附件' || value == '下载' || value == '点击下载') return false;
    if (RegExp(r'^\d+(?:\.\d+)?\s*(?:B|KB|MB|GB)$', caseSensitive: false).hasMatch(value)) return false;
    return !value.contains('下载次数') && value.length <= 220;
  }

  bool _hasNonImageName(String value) => RegExp(r'\.(?:txt|json|xml|csv|md|log|zip|rar|7z|tar|gz|apk|pdf|epub|mobi|docx?|xlsx?|pptx?|mp3|wav|flac|m4a|ogg|mp4|mkv|avi|mov|webm)$', caseSensitive: false).hasMatch(value.trim());

  String _anchorNumericAid(dom.Element anchor, Uri uri) {
    final raw = uri.queryParameters['aid']?.trim() ?? '';
    final direct = int.tryParse(raw);
    if (direct != null && direct > 0) return '$direct';
    final idMatch = RegExp(r'(?:aid_?|aimg_?)(\d+)', caseSensitive: false).firstMatch(anchor.id);
    if (idMatch != null) return idMatch.group(1)!;
    if (raw.isEmpty) return '';
    var padded = raw;
    while (padded.length % 4 != 0) padded += '=';
    try {
      final text = utf8.decode(base64.decode(padded));
      final first = text.split('|').first;
      if (int.tryParse(first) != null) return first;
    } catch (_) {}
    return '';
  }

  String _ensureFilenameExtension(String name, Uri uri) {
    var value = _cleanFileName(name);
    if (value.isEmpty) value = '论坛附件';
    if (_hasKnownFileExtension(value)) return value;
    final f = _cleanFileName(uri.queryParameters['_f'] ?? '');
    if (f.startsWith('.') && f.length <= 12 && RegExp(r'^\.[A-Za-z0-9]+$').hasMatch(f)) return '$value$f';
    if (RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(f)) return '$value.$f';
    if (_hasKnownFileExtension(f) && value == '论坛附件') return f;
    return value;
  }

  String _findAttachmentSize(dynamic anchor) {
    try {
      var e = anchor;
      for (var i = 0; i < 6 && e != null; i++, e = e.parent) {
        final m = RegExp(r'(\d+(?:\.\d+)?\s*(?:B|KB|MB|GB))', caseSensitive: false).firstMatch(_cleanFileName(e.text ?? ''));
        if (m != null) return m.group(1)!;
      }
    } catch (_) {}
    return '';
  }

  bool _looksLikeImageFile(String name, Uri uri) => RegExp(r'\.(?:jpe?g|png|gif|webp|bmp|svg|heic|heif|avif)(?:\b|$)').hasMatch('$name ${uri.queryParameters['_f'] ?? ''}'.toLowerCase());

  Future<bool> _enqueue({required String url, String? cookie, String? referer, String? filename}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('download', {
        'url': url, 'cookie': cookie ?? '', 'referer': referer ?? SiteConfig.base, 'filename': filename ?? '',
      });
      return ok == true;
    } on PlatformException { return false; } catch (_) { return false; }
  }
}
