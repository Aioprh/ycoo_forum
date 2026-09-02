import 'package:flutter/material.dart';

import '../services/attachment_download_service.dart';
import '../services/auth_service.dart';
import '../services/site_config.dart';

/// 打开全屏图片预览页：支持双指缩放、点击右上角下载保存。
/// ycoo=all 是正文注入的“全部附件”内部入口，不应当作为图片预览。
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

  bool get _isAllAttachmentRequest {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['ycoo']?.toLowerCase() == 'all' &&
        int.tryParse(uri?.queryParameters['tid'] ?? '') != null;
  }

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await AttachmentDownloadService.instance.download(
        url: url,
        cookie: AuthService.instance.authCookie,
        referer: SiteConfig.base,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isAllAttachmentRequest
                ? (ok ? '已开始下载本帖全部附件' : '未找到可下载的附件')
                : (ok ? '已开始下载图片' : '当前平台暂不支持原生图片保存'),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('下载失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAllAttachmentRequest) {
      return _AllAttachmentsPage(
        url: url,
        onDownload: () => _download(context),
      );
    }

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

class _AllAttachmentsPage extends StatelessWidget {
  final String url;
  final VoidCallback onDownload;

  const _AllAttachmentsPage({
    required this.url,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(url);
    final tid = uri?.queryParameters['tid'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('本帖附件'),
        actions: [
          IconButton(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded),
            tooltip: '下载全部附件',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            decoration: BoxDecoration(
              color: c.surfaceContainerHighest.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.outlineVariant.withValues(alpha: .55)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: c.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.folder_zip_rounded,
                    size: 34,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '本帖有附件',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text(
                  '主题 $tid · 将自动查找并下载本帖中的全部附件',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('点击下载全部附件'),
                  ),
                ),
                const SizedBox(height: 9),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回帖子'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
