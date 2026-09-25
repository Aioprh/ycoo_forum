import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import 'native_image_viewer.dart';

/// 原生帖子卡片：圆角、留白、缩略图和轻量元信息。
class ThreadCard extends StatelessWidget {
  final ThreadItem item;
  final VoidCallback onTap;

  const ThreadCard({super.key, required this.item, required this.onTap});

  /// 单图时的缩略图边长。
  static const double _singleCoverSize = 112;

  /// 多图并排时的缩略图高度。
  static const double _stripCoverHeight = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: .42)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _titleBlock(context, theme)),
                  // 只有一张图时放右侧大图; 多图走下面的并排预览, 否则右侧放不下。
                  if (item.covers.length == 1) ...[
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _image(context, theme, item.covers.first, _singleCoverSize, _singleCoverSize),
                    ),
                  ],
                ],
              ),
              if (item.covers.length > 1) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < item.covers.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _image(context, theme, item.covers[i], double.infinity, _stripCoverHeight),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 预览图点击后直接进全屏大图。
  ///
  /// 这层 GestureDetector 比外层卡片的 InkWell 更深, 点击图片时手势
  /// 由它胜出, 不会连带把帖子详情页也打开。
  Widget _image(BuildContext context, ThemeData theme, String url, double width, double height) {
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: () => openImageViewer(context, url: url),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: width,
          height: height,
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.image_not_supported_outlined, color: theme.hintColor),
        ),
      ),
    );
  }

  Widget _titleBlock(BuildContext context, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.3),
        ),
        if (item.subtitle.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: theme.hintColor),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 9,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (item.boardName.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(item.boardName, style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600)),
              ),
            _meta(context, item.author, Icons.person_outline),
            if (item.time.isNotEmpty) _meta(context, item.time, Icons.schedule_outlined),
            _meta(context, _formatCount(item.replyCount), Icons.chat_bubble_outline_rounded),
            _meta(context, _formatCount(item.viewCount), Icons.visibility_outlined),
          ],
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count < 0) return '0';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(count % 10000 == 0 ? 0 : 1)}万';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 1)}k';
    return count.toString();
  }

  Widget _meta(BuildContext context, String text, IconData icon) {
    final hint = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: hint),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11.5, color: hint)),
      ],
    );
  }
}