import 'package:flutter/material.dart';

import '../services/attachment_download_service.dart';
import '../services/auth_service.dart';
import '../services/site_config.dart';

/// 帖子正文之外的真实附件列表。
/// 图片附件不在这里显示；txt/json/zip/apk/mp4 等文件会以独立卡片展示。
class ForumAttachmentList extends StatefulWidget {
  final int tid;
  final String? cookie;
  final String? referer;

  const ForumAttachmentList({
    super.key,
    required this.tid,
    this.cookie,
    this.referer,
  });

  @override
  State<ForumAttachmentList> createState() => _ForumAttachmentListState();
}

class _ForumAttachmentListState extends State<ForumAttachmentList> {
  late Future<List<ForumAttachmentInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ForumAttachmentInfo>> _load() {
    return AttachmentDownloadService.instance.fetchAttachments(
      tid: widget.tid,
      cookie: widget.cookie,
      referer: widget.referer ?? SiteConfig.base,
    );
  }

  Future<void> _download(ForumAttachmentInfo item) async {
    final ok = await AttachmentDownloadService.instance.download(
      url: item.url,
      cookie: widget.cookie,
      referer: widget.referer ?? SiteConfig.base,
      filename: item.name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已开始下载：${item.name}' : '附件下载失败，请稍后重试')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ForumAttachmentInfo>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final items = snapshot.data ?? const <ForumAttachmentInfo>[];
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 9),
                child: Row(
                  children: [
                    Icon(Icons.attach_file_rounded,
                        size: 19,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '本帖附件 · ${items.length}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              for (final item in items) _AttachmentTile(item: item, onTap: () => _download(item)),
            ],
          ),
        );
      },
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final ForumAttachmentInfo item;
  final VoidCallback onTap;

  const _AttachmentTile({required this.item, required this.onTap});

  String get _extension {
    final name = item.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : '';
  }

  IconData get _icon {
    switch (_extension) {
      case 'txt':
      case 'md':
      case 'log':
        return Icons.description_outlined;
      case 'json':
      case 'xml':
      case 'csv':
        return Icons.data_object_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_outlined;
      case 'apk':
      case 'xapk':
      case 'apks':
        return Icons.android_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'm4a':
      case 'ogg':
        return Icons.audio_file_outlined;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'webm':
        return Icons.video_file_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (item.size.isNotEmpty) item.size,
      if (_extension.isNotEmpty) _extension.toUpperCase(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(_icon, color: scheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name.isEmpty ? '论坛附件' : item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.cloud_download_outlined, color: scheme.primary, size: 23),
              ],
            ),
          ),
        ),
      ),
    );
  }
}