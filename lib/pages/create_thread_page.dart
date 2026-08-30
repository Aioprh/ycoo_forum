import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/api_service.dart';
import '../services/attachment_upload_service.dart';
import '../services/auth_service.dart';
import '../services/site_fallback_service.dart';
import '../services/thread_publish_service.dart';

/// 原生发帖页：对齐源论坛网页端的快速发帖/高级模式，并保留原生附件上传能力。
class CreateThreadPage extends StatefulWidget {
  const CreateThreadPage({super.key});

  @override
  State<CreateThreadPage> createState() => _CreateThreadPageState();
}

class _CreateThreadPageState extends State<CreateThreadPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  List<ForumBoard> _boards = const [];
  List<ThreadType> _types = const [];
  final List<UploadedAttachment> _attachments = [];
  int? _fid;
  int? _typeid;
  int _price = 0;
  int _readperm = 0;
  bool _usesig = true;
  bool _allownoticeauthor = true;
  bool _advanced = false;
  bool _loadingBoards = true;
  bool _loadingTypes = false;
  bool _uploading = false;
  bool _submitting = false;
  String? _error;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _loadBoards();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadBoards() async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) {
      if (mounted) setState(() { _loadingBoards = false; _error = '请先登录论坛'; });
      return;
    }
    try {
      List<ForumCategory> groups;
      try {
        groups = await ApiService.instance.fetchBoards();
      } catch (_) {
        groups = await SiteFallbackService.instance.fetchBoards();
      }
      final boards = groups.expand((g) => g.boards).where((b) => b.fid > 0).toList();
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _fid = boards.isNotEmpty ? boards.first.fid : null;
        _loadingBoards = false;
        _error = boards.isEmpty ? '暂时没有可发帖的版块' : null;
      });
      final fid = _fid;
      if (fid != null) _loadTypes(fid);
    } catch (_) {
      if (mounted) setState(() { _loadingBoards = false; _error = '版块加载失败，请稍后重试'; });
    }
  }

  Future<void> _loadTypes(int fid) async {
    if (!mounted) return;
    setState(() { _loadingTypes = true; _types = const []; _typeid = null; });
    final types = await ThreadPublishService.instance.fetchThreadTypes(fid);
    if (!mounted) return;
    setState(() {
      _types = types;
      _loadingTypes = false;
      _typeid = types.isNotEmpty ? types.first.id : null;
    });
  }

  Future<void> _pickAttachments() async {
    if (_uploading || _submitting) return;
    final fid = _fid;
    if (fid == null || fid <= 0) {
      setState(() => _error = '请先选择发布版块');
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: FileType.any,
      );
      if (picked == null || picked.files.isEmpty) return;
      setState(() {
        _uploading = true;
        _error = null;
        _uploadStatus = '准备上传 0/${picked.files.length}';
      });
      for (var i = 0; i < picked.files.length; i++) {
        final file = picked.files[i];
        if (file.path == null || file.path!.isEmpty) {
          if (mounted) setState(() => _error = '${file.name} 无法读取');
          continue;
        }
        if (file.size > AttachmentUploadService.maxBytes) {
          if (mounted) setState(() => _error = '${file.name} 超过 10 MB，已跳过');
          continue;
        }
        if (mounted) setState(() => _uploadStatus = '正在上传 ${i + 1}/${picked.files.length}：${file.name}');
        try {
          final uploaded = await AttachmentUploadService.instance.upload(fid: fid, file: file);
          if (mounted) setState(() => _attachments.add(uploaded));
        } catch (e) {
          if (mounted) setState(() => _error = '${file.name}：${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '选择附件失败：${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() { _uploading = false; _uploadStatus = ''; });
    }
  }

  void _removeAttachment(int aid) {
    if (_uploading || _submitting) return;
    setState(() => _attachments.removeWhere((e) => e.aid == aid));
  }

  Future<void> _submit() async {
    if (_submitting || _uploading || !_formKey.currentState!.validate()) return;
    final fid = _fid;
    if (fid == null || fid <= 0) {
      setState(() => _error = '请选择发帖版块');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await ThreadPublishService.instance.createThread(
      fid: fid,
      subject: _title.text,
      message: _body.text,
      typeid: _typeid,
      price: _price,
      readperm: _readperm,
      usesig: _usesig,
      allownoticeauthor: _allownoticeauthor,
      attachments: List.unmodifiable(_attachments),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('发帖成功')));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = result);
    }
  }

  void _insert(String value, {int? selectionOffset}) {
    final text = _body.text;
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = text.substring(start.clamp(0, text.length), end.clamp(0, text.length));
    final replacement = value.replaceAll('{text}', selected.isEmpty ? '文字' : selected);
    final newText = text.replaceRange(start, end, replacement);
    _body.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: (start + (selectionOffset ?? replacement.length)).clamp(0, newText.length)),
    );
    setState(() {});
  }

  Future<String?> _ask(String title, {String hint = ''}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('插入')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _insertImage() async {
    final url = await _ask('插入图片', hint: 'https://example.com/image.jpg');
    if (url != null && url.isNotEmpty) _insert('[img]$url[/img]');
  }

  Future<void> _insertLink() async {
    final url = await _ask('插入链接', hint: 'https://example.com');
    if (url != null && url.isNotEmpty) _insert('[url=$url]{text}[/url]');
  }

  Future<void> _chooseColor() async {
    final colors = <String>['red', 'orange', 'green', 'blue', 'purple', 'gray', 'black'];
    final color = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: colors.map((color) => ListTile(
            leading: CircleAvatar(child: Text('色', style: TextStyle(fontSize: 12, color: color == 'black' ? Colors.white : Colors.black))),
            title: Text(color),
            onTap: () => Navigator.pop(context, color),
          )).toList(),
        ),
      ),
    );
    if (color != null) _insert('[color=$color]{text}[/color]');
  }

  Widget _toolbarButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(tooltip: tooltip, onPressed: _submitting || _uploading ? null : onPressed, icon: Icon(icon, size: 20));
  }

  Widget _editorToolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(.45),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withOpacity(.5))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _toolbarButton(Icons.format_bold_rounded, '粗体', () => _insert('[b]{text}[/b]')),
          _toolbarButton(Icons.format_italic_rounded, '斜体', () => _insert('[i]{text}[/i]')),
          _toolbarButton(Icons.palette_outlined, '颜色', _chooseColor),
          _toolbarButton(Icons.image_outlined, '图片', _insertImage),
          _toolbarButton(Icons.link_rounded, '链接', _insertLink),
          _toolbarButton(Icons.format_quote_rounded, '引用', () => _insert('[quote]{text}[/quote]')),
          _toolbarButton(Icons.code_rounded, '代码', () => _insert('[code]{text}[/code]')),
          _toolbarButton(Icons.emoji_emotions_outlined, '表情', () async {
            final emoji = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(child: Wrap(alignment: WrapAlignment.center, children: ['😀','😂','😎','👍','❤️','🎉','😅','🤔','🔥','👏','🥳','🙏'].map((e) => IconButton(iconSize: 30, onPressed: () => Navigator.pop(context, e), icon: Text(e))).toList())),
            );
            if (emoji != null) _insert(emoji);
          }),
        ]),
      ),
    );
  }

  Widget _attachmentCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.attach_file_rounded, color: scheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('附件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            TextButton.icon(onPressed: _uploading || _submitting ? null : _pickAttachments, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('添加')),
          ]),
          Text('单个附件最大 10 MB，直接使用论坛原生上传接口。', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          if (_uploading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 5),
            Text(_uploadStatus, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._attachments.map((attachment) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.insert_drive_file_outlined, size: 20)),
              title: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${(attachment.size / 1024 / 1024).toStringAsFixed(2)} MB · AID ${attachment.aid}'),
              trailing: IconButton(tooltip: '移除', onPressed: _uploading || _submitting ? null : () => _removeAttachment(attachment.aid), icon: const Icon(Icons.close_rounded)),
            )),
          ],
        ]),
      ),
    );
  }

  Widget _advancedCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(children: [
        ListTile(
          leading: Icon(Icons.tune_rounded, color: scheme.primary),
          title: const Text('高级设置', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('与网页端发帖页一致，按版块权限提交'),
          trailing: Switch(value: _advanced, onChanged: _submitting || _uploading ? null : (v) => setState(() => _advanced = v)),
        ),
        if (_advanced) Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(children: [
            const Divider(),
            DropdownButtonFormField<int>(
              value: _price,
              decoration: const InputDecoration(labelText: '主题售价（星币）', prefixIcon: Icon(Icons.monetization_on_outlined)),
              items: [0, 1, 2, 3, 4, 5, 10, 20].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '免费' : '$v 星币'))).toList(),
              onChanged: (v) => setState(() => _price = v ?? 0),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _readperm,
              decoration: const InputDecoration(labelText: '阅读权限', prefixIcon: Icon(Icons.lock_outline_rounded)),
              items: [0, 10, 20, 30, 50, 80, 100].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不限' : '$v 级'))).toList(),
              onChanged: (v) => setState(() => _readperm = v ?? 0),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('使用个人签名'), value: _usesig, onChanged: (v) => setState(() => _usesig = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('允许回复提醒作者'), value: _allownoticeauthor, onChanged: (v) => setState(() => _allownoticeauthor = v)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布帖子'),
        actions: [
          TextButton.icon(onPressed: _submitting || _uploading ? null : () => setState(() => _advanced = !_advanced), icon: Icon(_advanced ? Icons.edit_note_rounded : Icons.tune_rounded, size: 19), label: Text(_advanced ? '快速模式' : '高级模式')),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _submitting || _uploading || _loadingBoards ? null : _submit, child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('发布')),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (_loadingBoards) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 10),
              if (_boards.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  value: _fid,
                  decoration: InputDecoration(labelText: '发布到版块', prefixIcon: const Icon(Icons.forum_outlined), filled: true, fillColor: scheme.surfaceContainerHighest.withOpacity(.45), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                  items: _boards.map((b) => DropdownMenuItem<int>(value: b.fid, child: Text(b.name))).toList(),
                  onChanged: _submitting || _uploading ? null : (v) { setState(() => _fid = v); if (v != null) _loadTypes(v); },
                ),
                const SizedBox(height: 12),
              ],
              if (_types.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  value: _typeid,
                  decoration: InputDecoration(labelText: '主题分类', prefixIcon: const Icon(Icons.label_outline), filled: true, fillColor: scheme.surfaceContainerHighest.withOpacity(.45), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                  items: _types.map((t) => DropdownMenuItem<int>(value: t.id, child: Text(t.name))).toList(),
                  onChanged: _submitting || _uploading ? null : (v) => setState(() => _typeid = v),
                ),
                const SizedBox(height: 12),
              ],
              if (_loadingTypes) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2)),
              TextFormField(
                controller: _title,
                enabled: !_submitting && !_uploading,
                maxLength: 100,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: '标题', hintText: '请输入帖子标题', prefixIcon: const Icon(Icons.title_rounded), filled: true, fillColor: scheme.surfaceContainerHighest.withOpacity(.45), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                validator: (v) => v == null || v.trim().isEmpty ? '请输入标题' : null,
              ),
              const SizedBox(height: 2),
              Container(
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(.35), borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant.withOpacity(.6))),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  Row(children: [
                    const SizedBox(width: 14),
                    const Expanded(child: Text('正文', style: TextStyle(fontWeight: FontWeight.w700))),
                    ValueListenableBuilder<TextEditingValue>(valueListenable: _body, builder: (_, value, __) => Padding(padding: const EdgeInsets.only(right: 12), child: Text('${value.text.length}/10000', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)))),
                  ]),
                  _editorToolbar(context),
                  TextFormField(
                    controller: _body,
                    enabled: !_submitting && !_uploading,
                    minLines: 10,
                    maxLines: 22,
                    maxLength: 10000,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(hintText: '分享你的内容……支持网页端常用的 BBCode：粗体、颜色、图片、链接、引用、代码和表情。', alignLabelWithHint: true, border: InputBorder.none, contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 12)),
                    validator: (v) => v == null || v.trim().isEmpty ? (_attachments.isEmpty ? '请输入正文或添加附件' : null) : null,
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              _attachmentCard(context),
              const SizedBox(height: 12),
              _advancedCard(context),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(14)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: scheme.onErrorContainer), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))])),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _submitting || _uploading || _loadingBoards ? null : _submit, icon: const Icon(Icons.send_rounded), label: Text(_submitting ? '正在发布…' : '发布帖子'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
              const SizedBox(height: 10),
              Text('网页端提供快速发帖、主题分类、BBCode 工具栏、附件及高级发帖选项；移动端现在按同一套发帖能力组织。', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
