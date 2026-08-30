import 'dart:io';
import 'package:flutter/services.dart';

/// 原生附件下载桥接。
/// WebView 只负责识别点击，实际下载交给 Android DownloadManager。
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
        (query.contains('mod=attachment')) ||
        query.contains('aid=') ||
        path.contains('/attachment/') ||
        path.contains('/download/');
  }

  Future<bool> download({required String url, String? cookie, String? referer}) async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<bool>('download', {
      'url': url,
      'cookie': cookie ?? '',
      'referer': referer ?? 'https://www.ycoo.net/',
    });
    return result == true;
  }
}
