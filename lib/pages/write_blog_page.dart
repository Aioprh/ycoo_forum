import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/space_write_service.dart';
import '../utils/forum_text.dart';
import 'login_page.dart';

/// 写日志: 在空间发布一篇日志(blog)。
class WriteBlogPage extends StatefulWidget {
  const WriteBlogPage({super.key});

  @override
  State<WriteBlogPage> createState() => _WriteBlogPageState();
}

class _WriteBlogPageState extends State<WriteBlogPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ensureLogin();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _ensureLogin() async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn && mounted) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (ok == true && mounted) setState(() {});
    }
  }

  void _insert(String value) {
    final text = _body.text;
    final selection = _body.selection;
    final start = selection.isValid ? selection.start.clamp(0, text.length) : text.length;
    final end = selection.isValid ? selection.end.clamp(start, text.length) : text.length;
    final selected = text.substring(start, end);
    final replacement = value.replaceAll('{text}', selected.isEmpty ? '文字' : selected);
    final newText = text.replaceRange(start, end, replacement);
    _body.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: (start + replacement.length).clamp(0, newText.length)));
    _bodyFocus.requestFocus();
  }

  Widget _tool(IconData icon, String label, VoidCallback action) => IconButton(
        tooltip: label,
        onPressed: _submitting ? null : action,
        style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
        icon: Icon(icon, size: 20),
      );

  Future<void> _submit() async {
    if (_submitting) return;
    if (_title.text.trim().isEmpty) { setState(() => _error = '请输入日志标题'); return; }
    if (_body.text.trim().isEmpty) { setState(() => _error = '请输入日志内容'); return; }
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await SpaceWriteService.instance.createBlog(title: _title.text, content: _body.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志发布成功'), behavior: SnackBarBehavior.floating));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = forumText(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('写日志', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(onPressed: _submitting ? null : _submit, child: Text(_submitting ? '发布中' : '发布', style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Form(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              TextField(
                controller: _title,
                enabled: !_submitting,
                maxLength: 100,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: '日志标题',
                  filled: true,
                  fillColor: scheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.6))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant.withOpacity(.6))),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      const SizedBox(width: 4),
                      _tool(Icons.format_bold_rounded, '粗体', () => _insert('[b]{text}[/b]')),
                      _tool(Icons.format_italic_rounded, '斜体', () => _insert('[i]{text}[/i]')),
                      _tool(Icons.image_outlined, '图片', () => _insert('[img]{text}[/img]')),
                      _tool(Icons.link_rounded, '链接', () => _insert('[url={text}]{text}[/url]')),
                      _tool(Icons.format_quote_rounded, '引用', () => _insert('[quote]{text}[/quote]')),
                      const SizedBox(width: 4),
                    ]),
                  ),
                  SizedBox(
                    height: 120,
                    child: TextField(
                      controller: _body,
                      focusNode: _bodyFocus,
                      enabled: !_submitting,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(hintText: '记录你的思考、见闻或经验……\n\n支持网页端常用 BBCode 格式。', border: InputBorder.none, contentPadding: EdgeInsets.all(16)),
                    ),
                  ),
                ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer, size: 20), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))])),
              ],
              const SizedBox(height: 12),
              Text('日志发布后会出现在你的空间里', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}