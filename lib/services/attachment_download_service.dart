import 'dart:io';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 原生附件下载桥接。
/// WebView/正文只负责识别点击，实际下载交给 Android DownloadManager。
/// 对帖子附件列表额外支持“全部下载”：先用当前登录 Cookie 抓取帖子中的真实附件地址，
/// 再逐个交给系统下载器，避免直接把伪造/不完整的附件地址交给 DownloadManager。
class AttachmentDownloadService {
  AttachmentDownloadService._();
  static final instance = AttachmentDownloadService._();
  static const _channel = MethodChannel('ycoo/attachment_download');

  bool isAttachmentUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    final path = u.path.toLowerCase();
    final query = u.query.toLowerCase();
    return path.contains('attachment.php') ||
        query.contains('mod=attachment') ||
        query.contains('aid=') ||
        path.contains('/attachment/') ||
        path.contains('/download/');
  }

  Future<bool> download({required String url, String? cookie, String? referer}) async {
    if (!Platform.isAndroid) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // NativePostContent 使用这个内部标记展示“下载全部附件”卡片。
    if (uri.queryParameters['ycoo'] == 'all') {
      final tid = int.tryParse(uri.queryParameters['tid'] ?? '') ?? 0;
      if (tid <= 0) return false;
      return downloadAllFromThread(
        tid: tid,
        cookie: cookie,
        referer: referer,
      );
    }

    return _enqueue(
      url: url,
      cookie: cookie,
      referer: referer,
    );
  }

  Future<bool> downloadAllFromThread({
    required int tid,
    String? cookie,
    String? referer,
  }) async {
    if (!Platform.isAndroid || tid <= 0) return false;
    final client = await NetClient.instance.client;
    final threadUrl = '${SiteConfig.base}thread-$tid-1-1.html';
    final headers = <String, String>{
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Referer': referer ?? SiteConfig.base,
      if ((cookie ?? '').isNotEmpty) 'Cookie': cookie!,
    };

    try {
      final response = await NetClient.retry(
        () => client.get(
          Uri.parse(threadUrl).replace(queryParameters: {
            'mobile': '2',
            '_ycoo_attachment_list': DateTime.now().millisecondsSinceEpoch.toString(),
          }),
          headers: headers,
        ).timeout(NetClient.timeout),
      );
      if (response.statusCode != 200) return false;

      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      final links = <String>{};
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim().replaceAll('&amp;', '&');
        if (href.isEmpty || href.startsWith('javascript:')) continue;
        final uri = Uri.tryParse(href);
        if (uri == null) continue;
        final path = uri.path.toLowerCase();
        final query = uri.query.toLowerCase();
        final isAttachment = path.contains('attachment.php') ||
            query.contains('mod=attachment') ||
            query.contains('aid=') ||
            path.contains('/attachment/') ||
            path.contains('/download/');
        if (!isAttachment) continue;
        final absolute = href.startsWith('http://') || href.startsWith('https://')
            ? href
            : SiteConfig.resolve(href);
        if (absolute.isNotEmpty) links.add(absolute);
      }

      if (links.isEmpty) return false;
      var started = false;
      for (final url in links) {
        try {
          final ok = await _enqueue(url: url, cookie: cookie, referer: threadUrl);
          started = started || ok;
        } catch (_) {}
      }
      return started;
    } catch (_) {
      return false;
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
      // Android 11+ 首次下载可能需要打开“允许管理所有文件”设置页。
      // 不把平台异常冒泡到帖子页面，避免点击附件后出现 Flutter 红色错误。
      return false;
    } catch (_) {
      return false;
    }
  }
}
