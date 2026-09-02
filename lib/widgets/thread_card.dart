import 'package:flutter/material.dart';

import '../models/thread_item.dart';

/// 原生帖子卡片：圆角、留白、缩略图和轻量元信息。
class ThreadCard extends StatelessWidget {
  final ThreadItem item;
  final VoidCallback onTap;

  const ThreadCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: .42)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _titleBlock(context, theme)),
              if (item.cover.isNotEmpty) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.cover,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.image_not_supported_outlined, color: theme.hintColor),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.28),
        ),
        if (item.subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, height: 1.35, color: theme.hintColor),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (item.boardName.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(item.boardName, style: TextStyle(fontSize: 10.5, color: scheme.primary, fontWeight: FontWeight.w600)),
              ),
            _meta(context, item.author, Icons.person_outline),
            if (item.time.isNotEmpty) _meta(context, item.time, Icons.schedule_outlined),
            _meta(context, item.replyCount.toString(), Icons.chat_bubble_outline_rounded),
          ],
        ),
      ],
    );
  }

  Widget _meta(BuildContext context, String text, IconData icon) {
    final hint = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: hint),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: hint)),
      ],
    );
  }
}
