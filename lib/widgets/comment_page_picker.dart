import 'package:flutter/material.dart';

/// 评论分页选择器：使用独立弹窗替代长列表 DropdownButton。
/// 视觉上与原生“选择页码”弹窗一致，适合评论页数较多的帖子。
class CommentPagePicker extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final bool loading;
  final ValueChanged<int> onSelected;

  const CommentPagePicker({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onSelected,
    this.loading = false,
  });

  Future<void> _showPicker(BuildContext context) async {
    if (loading || totalPages <= 1) return;
    final selected = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _CommentPageDialog(
        currentPage: currentPage,
        totalPages: totalPages,
      ),
    );
    if (selected != null && selected != currentPage) {
      onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final safePage = currentPage.clamp(1, totalPages);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: loading || safePage <= 1
                  ? null
                  : () => onSelected(safePage - 1),
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('上一页'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: loading ? null : () => _showPicker(context),
              borderRadius: BorderRadius.circular(15),
              child: Container(
                constraints: const BoxConstraints(minWidth: 104),
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: .45),
                  ),
                ),
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$safePage / $totalPages 页',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: loading || safePage >= totalPages
                  ? null
                  : () => onSelected(safePage + 1),
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('下一页'),
              iconAlignment: IconAlignment.end,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentPageDialog extends StatelessWidget {
  final int currentPage;
  final int totalPages;

  const _CommentPageDialog({
    required this.currentPage,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择页码',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                '当前第 $currentPage 页 / 共 $totalPages 页',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final columns = width >= 350 ? 4 : 3;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.65,
                        ),
                        itemCount: totalPages,
                        itemBuilder: (context, index) {
                          final page = index + 1;
                          final selected = page == currentPage;
                          return Material(
                            color: selected
                                ? colors.primary
                                : colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(13),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(13),
                              onTap: () => Navigator.of(context).pop(page),
                              child: Center(
                                child: Text(
                                  '$page',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? colors.onPrimary
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    '关闭',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
