import 'package:flutter/material.dart';

import '../services/attachment_download_service.dart';
import '../services/auth_service.dart';
import '../services/site_config.dart';

/// 打开全屏图片预览页：支持双指缩放、点击右上角下载保存。
Future<void> openImageViewer(
  BuildContext context, {
  required String url,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => NativeImageViewer(url: url),
    ),
  );
}

class NativeImageViewer extends StatelessWidget {
  final String url;
  const NativeImageViewer({super.key, required this.url});

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await AttachmentDownloadService.instance.download(
        url: url,
        cookie: AuthService.instance.authCookie,
        referer: SiteConfig.base,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '已开始下载图片' : '当前平台暂不支持原生图片保存')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cookie = AuthService.instance.authCookie;
    final headers = <String, String>{'Referer': SiteConfig.base};
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _download(context),
            icon: const Icon(Icons.download_rounded),
            tooltip: '保存图片',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: GestureDetector(
        // 点空白处/单点返回, 双指缩放交给 InteractiveViewer
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            maxScale: 6,
            minScale: 0.8,
            child: Image.network(
              url,
              width: double.infinity,
              fit: BoxFit.contain,
              headers: headers,
              filterQuality: FilterQuality.high,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
              errorBuilder: (_, __, ___) => Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  '图片加载失败\n$url',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
          child: FilledButton.icon(
            onPressed: () => _download(context),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
            icon: const Icon(Icons.download_rounded),
            label: const Text('点击下载图片', style: TextStyle(fontSize: 15)),
          ),
        ),
      ),
    );
  }
}