import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../utils/forum_text.dart';
import 'login_page.dart';

/// 发圈子: 选择一个圈子(群组)并发布主题。
class CreateGroupThreadPage extends StatefulWidget {
  const CreateGroupThreadPage({super.key});

  @override
  State<CreateGroupThreadPage> createState() => _CreateGroupThreadPageState();
}

class _CreateGroupThreadPageState extends State<CreateGroupThreadPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  List<CircleGroup> _groups = const [];
  bool _loadingGroups = true;
  CircleGroup? _selected;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) {
      if (!mounted) return;
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (ok != true) { if (mounted) Navigator.of(context).pop(); return; }
    }
    await _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;
    setState(() { _loadingGroups = true; _error = null; });
    final groups = await GroupService.instance.fetchGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loadingGroups = false;
      if (_selected == null && groups.isNotEmpty) _selected = groups.first;
      if (groups.isEmpty) _error = '暂无可用圈子，请稍后重试';
    });
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
    if (_selected == null) { setState(() => _error = '请选择一个圈子'); return; }
    if (_title.text.trim().isEmpty) { setState(() => _error = '请输入标题'); return; }
    if (_body.text.trim().isEmpty) { setState(() => _error = '请输入内容'); return; }
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await GroupService.instance.createGroupThread(
      fid: _selected!.fid,
      gid: _selected!.groupId,
      subject: _title.text,
      message: _body.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('圈子主题发布成功'), behavior: SnackBarBehavior.floating));
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
        title: const Text('发圈子', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(onPressed: _submitting ? null : _submit, child: Text(_submitting ? '发布中' : '发布', style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]), borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.surface.withOpacity(.72), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.groups_rounded, color: scheme.primary)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('发布到圈子', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('选择一个圈子并发表你的主题', style: TextStyle(fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            Text('选择圈子', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
            const SizedBox(height: 8),
            if (_loadingGroups)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()))
            else if (_selected != null)
              _groupPicker(scheme),
            const SizedBox(height: 14),
            Text('标题', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              enabled: !_submitting,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: '圈子主题标题',
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
                  height: 150,
                  child: TextField(
                    controller: _body,
                    focusNode: _bodyFocus,
                    enabled: !_submitting,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(hintText: '分享想法、问题或资源……\n\n支持网页端常用 BBCode 格式。', border: InputBorder.none, contentPadding: EdgeInsets.all(16)),
                  ),
                ),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer, size: 20), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _groupPicker(ColorScheme scheme) {
    return DropdownButtonFormField<int>(
      value: _selected!.fid,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.groups_rounded),
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.6))),
      ),
      items: _groups.map((g) => DropdownMenuItem(value: g.fid, child: Text(g.name, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: _submitting
          ? null
          : (v) => setState(() {
                CircleGroup? next;
                if (v != null) {
                  for (final g in _groups) {
                    if (g.fid == v) { next = g; break; }
                  }
                }
                if (next != null) _selected = next;
              }),
    );
  }
}