import 'package:flutter/material.dart';

import '../models/thread_item.dart';

/// 帖子卡片:头像/作者/时间 + 标题 + 摘要 + 可选缩略图 + 版块/回复/浏览。
class ThreadCard extends StatelessWidget {
  final ThreadItem item;
  final VoidCallback onTap;

  const ThreadCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _titleBlock(context, theme)),
            if (item.cover.isNotEmpty) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  item.cover,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 84,
                    height: 84,
                    child: ColoredBox(color: Colors.black12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _titleBlock(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
        if (item.subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: theme.hintColor),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (item.boardName.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.boardName,
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.primary),
                ),
              ),
            _meta(item.author, Icons.person_outline),
            if (item.time.isNotEmpty) _meta(item.time, Icons.schedule),
            _meta(item.replyCount.toString(), Icons.chat_bubble_outline),
          ],
        ),
      ],
    );
  }

  Widget _meta(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 2),
        Text(text, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
      ],
    );
  }
}