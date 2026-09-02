import 'package:flutter/material.dart';

import '../services/attachment_download_service.dart';
import '../services/site_config.dart';

class ForumAttachmentSection extends StatelessWidget {
  final int tid;
  final String? cookie;
  final String? referer;

  const ForumAttachmentSection({
    super.key,
    required this.tid,
    this.cookie,
    this.referer,
  });

  @override
  Widget build(BuildContext context) {
    if (tid <= 0) return const SizedBox.shrink();
    return FutureBuilder<List<ForumAttachmentInfo>>(
      future: AttachmentDownloadService.instance.fetchAttachments(
        tid: tid,
        cookie: cookie,
        referer: referer ?? SiteConfig.base,
      ),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <ForumAttachmentInfo>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
              child: Text('本帖附件 · ${items.length}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final item in items)
              _Tile(item: item, cookie: cookie, referer: referer),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final ForumAttachmentInfo item;
  final String? cookie;
  final String? referer;
  const _Tile({required this.item, this.cookie, this.referer});

  IconData _icon(String name) {
    final e = name.toLowerCase().split('.').last;
    if (e == 'txt' || e == 'md' || e == 'log') return Icons.description_outlined;
    if (e == 'json' || e == 'xml' || e == 'csv') return Icons.data_object_rounded;
    if (e == 'zip' || e == 'rar' || e == '7z' || e == 'tar' || e == 'gz') return Icons.folder_zip_outlined;
    if (e == 'apk' || e == 'xapk' || e == 'apks') return Icons.android_rounded;
    if (e == 'pdf') return Icons.picture_as_pdf_outlined;
    if (['mp3','wav','flac','m4a','ogg'].contains(e)) return Icons.audio_file_outlined;
    if (['mp4','mkv','avi','mov','webm'].contains(e)) return Icons.video_file_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _download(BuildContext context) async {
    final ok = await AttachmentDownloadService.instance.download(
      url: item.url,
      cookie: cookie,
      referer: referer ?? SiteConfig.base,
      filename: item.name,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已开始下载：${item.name}' : '附件下载失败')));
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final meta = [if (item.size.isNotEmpty) item.size, if (item.name.contains('.')) item.name.split('.').last.toUpperCase()].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: c.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _download(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(11)), child: Icon(_icon(item.name), color: c.primary)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name.isEmpty ? '论坛附件' : item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (meta.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(meta, style: TextStyle(fontSize: 12, color: c.onSurfaceVariant))),
              ])),
              Icon(Icons.cloud_download_outlined, color: c.primary),
            ]),
          ),
        ),
      ),
    );
  }
}