import 'package:flutter/material.dart';

import '../services/attachment_download_service.dart';
import '../services/auth_service.dart';
import '../services/site_config.dart';

/// 打开全屏图片预览页。
///
/// 这里虽然由帖子正文的链接统一入口调用，但必须严格区分：
/// - 图片：进入图片预览
/// - 非图片附件：进入附件下载卡片
/// - ycoo=all：进入本帖全部附件页面
Future<void> openImageViewer(
  BuildContext context, {
  required String url,
  List<String>? gallery,
}) {
  final images = _collectImages(url, gallery);
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => NativeImageViewer(
        images: images,
        initialIndex: _indexOfImage(images, url),
      ),
    ),
  );
}

/// gallery 是同一组图片（同一帖正文 / 同一张卡片的预览图）的顺序列表。
///
/// 被点击的那张必须能在其中命中，命中不了就退回单图，避免左右滑动时
/// 滑出一组和当前帖子无关的图。
List<String> _collectImages(String url, List<String>? gallery) {
  final images = <String>[];
  for (final raw in gallery ?? const <String>[]) {
    final value = raw.trim();
    if (value.isEmpty || images.contains(value)) continue;
    images.add(value);
  }

  final current = url.trim();
  // 命中不了说明这组图和当前图片不是一套，退回单图，避免左右滑动时
  // 滑出与当前帖子无关的图片。
  if (_indexOfImage(images, current) < 0) return <String>[current];
  return images;
}

/// 先精确匹配，再按 Uri 规范化后比较，兼容 `Uri.toString()` 的轻微重写
/// （百分号编码、主机名大小写等）。找不到返回 -1。
int _indexOfImage(List<String> images, String target) {
  final value = target.trim();
  final exact = images.indexOf(value);
  if (exact >= 0) return exact;

  final normalized = _normalizeUrl(value);
  for (var i = 0; i < images.length; i++) {
    if (_normalizeUrl(images[i]) == normalized) return i;
  }
  return -1;
}

String _normalizeUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri == null ? value.trim() : uri.toString();
}

class NativeImageViewer extends StatefulWidget {
  /// 全部待预览的图片，顺序与来源（正文 / 列表预览图）一致。
  final List<String> images;

  /// 打开时展示第几张。
  final int initialIndex;

  const NativeImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<NativeImageViewer> createState() => _NativeImageViewerState();
}

class _NativeImageViewerState extends State<NativeImageViewer> {
  static const _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'svg',
    'heic',
    'heif',
    'avif',
  };

  late final PageController _pager =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _transform = TransformationController();
  bool _zoomed = false;

  /// 当前展示的图片。附件判定和下载都以它为准。
  String get url => widget.images[_index];

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// 放大后水平拖动交给 InteractiveViewer；只有回到原始比例才允许翻页，
  /// 否则两者会抢同一个水平手势。
  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _zoomed = false;
    });
    // 换页后重置缩放, 否则上一张的放大状态会带到下一张。
    _transform.value = Matrix4.identity();
  }

  Uri? get _uri => Uri.tryParse(url);

  bool get _isAllAttachmentRequest {
    final uri = _uri;
    return uri?.queryParameters['ycoo']?.toLowerCase() == 'all' &&
        int.tryParse(uri?.queryParameters['tid'] ?? '') != null;
  }

  bool get _isAttachmentRequest {
    if (_isAllAttachmentRequest) return false;
    return AttachmentDownloadService.instance.isAttachmentUrl(url);
  }

  /// Discuz 的附件链接通常会通过 `_f=.mp4`、`_f=.jpg` 等参数携带真实
  /// 文件类型。只有明确知道是图片时才允许进入图片预览，不能因为
  /// `attachment.php` / `aid=` 就把 mp4、zip、apk 等当成图片。
  String? get _attachmentExtension {
    final uri = _uri;
    if (uri == null) return null;

    final candidates = <String?>[
      uri.queryParameters['_f'],
      uri.queryParameters['filename'],
      uri.queryParameters['file'],
      uri.queryParameters['name'],
      uri.path,
    ];

    for (final raw in candidates) {
      if (raw == null || raw.trim().isEmpty) continue;
      var value = raw.trim().toLowerCase();
      if (value.startsWith('.')) value = value.substring(1);
      final dot = value.lastIndexOf('.');
      if (dot >= 0 && dot < value.length - 1) {
        final ext = value.substring(dot + 1).split('?').first.split('#').first;
        if (ext.isNotEmpty) return ext;
      }
    }
    return null;
  }

  bool get _isImageAttachment {
    if (!_isAttachmentRequest) return false;
    final ext = _attachmentExtension;
    return ext != null && _imageExtensions.contains(ext);
  }

  bool get _shouldShowAttachmentPage =>
      _isAttachmentRequest && !_isImageAttachment;

  String get _attachmentLabel {
    final ext = _attachmentExtension;
    if (ext == null || ext.isEmpty) return '文件附件';
    return '${ext.toUpperCase()} 附件';
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
                : _shouldShowAttachmentPage
                    ? (ok ? '已开始下载附件' : '当前平台暂不支持原生附件下载')
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

    // 非图片附件绝不能交给 Image.network，否则会出现“图片加载失败”。
    // 即使上游帖子链接分类器误把 attachment.php 交到了这里，也在最后
    // 一层再次兜底，保证附件仍然以附件的方式展示和下载。
    if (_shouldShowAttachmentPage) {
      return _AttachmentPage(
        url: url,
        label: _attachmentLabel,
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
        title: widget.images.length > 1
            ? Text(
                '${_index + 1} / ${widget.images.length}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              )
            : null,
        actions: [
          IconButton(
            onPressed: () => _download(context),
            icon: const Icon(Icons.download_rounded),
            tooltip: '保存图片',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PageView.builder(
        controller: _pager,
        // 放大后禁用翻页, 让水平拖动用于平移图片本身。
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: widget.images.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) {
          final imageUrl = widget.images[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: InteractiveViewer(
                maxScale: 6,
                minScale: 0.8,
                transformationController: _transform,
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  headers: headers,
                  filterQuality: FilterQuality.high,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      '图片加载失败\n$imageUrl',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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

class _AttachmentPage extends StatelessWidget {
  final String url;
  final String label;
  final VoidCallback onDownload;

  const _AttachmentPage({
    required this.url,
    required this.label,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('附件'),
        actions: [
          IconButton(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded),
            tooltip: '下载附件',
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
                    color: c.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.insert_drive_file_rounded,
                    size: 34,
                    color: c.secondary,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '帖子附件',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(color: c.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('点击下载附件'),
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
