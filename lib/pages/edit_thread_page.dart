import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import '../services/thread_edit_service.dart';

/// 编辑自己已发布的主题：预填原标题与正文，提交后返回近况。
class EditThreadPage extends StatefulWidget {
  final int tid;
  final int fid;
  final int pid;
  final String title;
  final String body;

  const EditThreadPage({
    super.key,
    required this.tid,
    required this.fid,
    required this.pid,
    required this.title,
    required this.body,
  });

  @override
  State<EditThreadPage> createState() => _EditThreadPageState();
}

class _EditThreadPageState extends State<EditThreadPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _title.text = widget.title;
    _body.text = widget.body;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final err = await ThreadEditService.instance.editThread(
      tid: widget.tid,
      fid: widget.fid,
      pid: widget.pid,
      subject: _title.text,
      message: _body.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('编辑成功'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('编辑主题'),
        backgroundColor: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          TextField(
            controller: _title,
            maxLength: 100,
            maxLines: 1,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '标题',
              filled: true,
              fillColor: colors.surface,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            focusNode: _bodyFocus,
            maxLines: null,
            minLines: 10,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 15, height: 1.5),
            decoration: InputDecoration(
              hintText: '正文（支持 BBCode：\n[b]加粗[/b]  [url=链接]文字[/url]  [img]图片地址[/img]）',
              hintStyle: TextStyle(fontSize: 13, height: 1.5, color: colors.onSurfaceVariant),
              filled: true,
              fillColor: colors.surface,
              alignLabelWithHint: true,
              contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '保存后将重新加载帖子，改动立即生效。',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('保存修改', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// 从帖子正文 HTML 中提取可编辑的纯文本（去掉标签与公式字体占位符）。
String threadBodyToPlainText(String html) {
  if (html.trim().isEmpty) return '';
  final text = (html_parser.parse(html).body?.text ?? '')
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text;
}
