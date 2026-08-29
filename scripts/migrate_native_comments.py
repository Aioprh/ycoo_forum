from pathlib import Path

p = Path('lib/pages/detail_page.dart')
s = p.read_text()

needle = "import '../services/thread_interaction_service.dart';"
if "../widgets/native_comment_list.dart" not in s:
    s = s.replace(needle, needle + "\nimport '../widgets/native_comment_list.dart';")

s = s.replace(
    "      _commentsController = d.commentsHtml.trim().isEmpty ? null : _web(d.commentsHtml, true);\n",
    "      _commentsController = null;\n",
)

start = s.index('  Widget _commentsSection(BuildContext context) {')
end = s.index('\n  Widget _webCard(', start)

replacement = '''  Widget _commentsSection(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          onTap: () => setState(() => _commentsExpanded = !_commentsExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              Container(width: 4, height: 25, decoration: BoxDecoration(color: s.secondary, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('评论 / 回复', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('原生楼层 · ${_detail?.commentsHtml.trim().isEmpty == false ? '按楼层浏览' : '暂无回复'}', style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant)),
              ])),
              Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: s.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(_commentsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20)),
            ]),
          ),
        ),
        if (_commentsExpanded) ...[
          Divider(height: 1, color: s.outlineVariant.withValues(alpha: .4)),
          NativeCommentList(html: _detail?.commentsHtml ?? ''),
        ],
      ]),
    );
  }
'''

s = s[:start] + replacement + s[end:]
p.write_text(s)
