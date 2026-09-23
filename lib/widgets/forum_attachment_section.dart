import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/attachment_download_service.dart';
import '../services/site_config.dart';

class ForumAttachmentSection extends StatefulWidget {
  final List<ForumAttachmentInfo> attachments;
  final String? cookie;
  final String? referer;

  const ForumAttachmentSection({
    super.key,
    required this.attachments,
    this.cookie,
    this.referer,
  });

  @override
  State<ForumAttachmentSection> createState() => _ForumAttachmentSectionState();
}

class _ForumAttachmentSectionState extends State<ForumAttachmentSection> {
  late List<ForumAttachmentInfo> _items;

  @override
  void initState() {
    super.initState();
    _items = List.unmodifiable(widget.attachments);
    _fillRealNames();
  }

  Future<void> _fillRealNames() async {
    final targets = _items.where((e) {
      final n = e.name.trim();
      return n.isEmpty || n.startsWith('论坛附件');
    }).toList();
    if (targets.isEmpty) return;

    const timeout = Duration(seconds: 4);
    List<ForumAttachmentInfo>? filled;
    try {
      filled = await AttachmentDownloadService.instance
          .fillRealNames(
            _items,
            cookie: widget.cookie,
            referer: widget.referer,
          )
          .timeout(timeout, onTimeout: () => const []);
    } catch (_) {
      return;
    }

    if (!mounted || filled.isEmpty) return;

    final realNames = <String, String>{};
    for (final f in filled) {
      if (!_isGenericName(f.name)) realNames[f.url] = f.name;
    }
    if (realNames.isEmpty) return;

    setState(() {
      _items = _items.map((e) {
        final newName = realNames[e.url] ?? e.name;
        return ForumAttachmentInfo(
          url: e.url,
          name: newName,
          size: e.size,
          downloads: e.downloads,
        );
      }).toList();
    });
  }

  bool _isGenericName(String name) {
    final n = name.trim();
    if (n.isEmpty) return true;
    return n == '论坛附件' || n.startsWith('论坛附件.');
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
          child: Text(
            '本帖附件 · ${_items.length}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (final item in _items)
          _Tile(item: item, cookie: widget.cookie, referer: widget.referer),
      ],
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已开始下载：${item.name}' : '附件下载失败')),
    );
  }

  Future<void> _copyUrl(BuildContext context) async {
    final url = item.url.trim();
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('附件下载链接已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final meta = [
      if (item.size.isNotEmpty) item.size,
      if (item.downloads.isNotEmpty) item.downloads,
      if (item.name.contains('.')) item.name.split('.').last.toUpperCase(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: c.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _download(context),
          onLongPress: () => _copyUrl(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(11)),
                child: Icon(_icon(item.name), color: c.primary),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          meta,
                          style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.cloud_download_outlined, color: c.primary),
            ]),
          ),
        ),
      ),
    );
  }
}
