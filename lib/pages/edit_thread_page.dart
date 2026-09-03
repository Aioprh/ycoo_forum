import 'package:flutter/material.dart';

import '../services/thread_edit_service.dart';
import '../services/thread_publish_service.dart';
import '../services/attachment_upload_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

/// 编辑自己已发布的主题。编辑页能力与发布页保持一致：标题、正文 BBCode、
/// 分类、售价、阅读权限、签名、通知、隐藏回复、排序、动态以及附件。
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
  final List<UploadedAttachment> _attachments = [];
  List<ThreadType> _types = const [];
  int? _typeid;
  int _price = 0;
  int _readperm = 0;
  bool _usesig = true;
  bool _allownoticeauthor = true;
  bool _hiddenreplies = false;
  bool _descviewdefault = false;
  bool _addfeed = true;
  bool _advanced = false;
  bool _loading = true;
  bool _uploading = false;
  bool _submitting = false;
  String? _error;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _title.text = widget.title;
    _body.text = widget.body;
    _loadEditForm();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadEditForm() async {
    try {
      final data = await ThreadEditService.instance.loadEditData(
        tid: widget.tid,
        fid: widget.fid,
        pid: widget.pid,
      );
      final types = await ThreadPublishService.instance.fetchThreadTypes(widget.fid);
      if (!mounted) return;
      setState(() {
        if (data.subject.isNotEmpty) _title.text = data.subject;
        if (data.message.isNotEmpty) _body.text = data.message;
        _types = types;
        _typeid = data.typeid ?? (types.isNotEmpty ? types.first.id : null);
        _price = data.price;
        _readperm = data.readperm;
        _usesig = data.usesig;
        _allownoticeauthor = data.allownoticeauthor;
        _hiddenreplies = data.hiddenreplies;
        _descviewdefault = data.descviewdefault;
        _addfeed = data.addfeed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _insert(String value) {
    final text = _body.text;
    final selection = _body.selection;
    final start = selection.isValid ? selection.start.clamp(0, text.length) : text.length;
    final end = selection.isValid ? selection.end.clamp(start, text.length) : text.length;
    final selected = text.substring(start, end);
    final replacement = value.replaceAll('{text}', selected.isEmpty ? '文字' : selected);
    final next = text.replaceRange(start, end, replacement);
    _body.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: (start + replacement.length).clamp(0, next.length)),
    );
    _bodyFocus.requestFocus();
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
          decoration: InputDecoration(hintText: hint),
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
    final url = await _ask('插入图片', hint: '图片 URL');
    if (url != null && url.isNotEmpty) _insert('[img]$url[/img]');
  }

  Future<void> _insertLink() async {
    final url = await _ask('插入链接', hint: 'https://example.com');
    if (url != null && url.isNotEmpty) _insert('[url=$url]{text}[/url]');
  }

  Future<void> _insertVideo() async {
    final url = await _ask('插入视频', hint: '视频 URL');
    if (url != null && url.isNotEmpty) _insert('[media=video,0,0]$url[/media]');
  }

  Future<void> _chooseColor() async {
    const values = ['red', 'orange', 'green', 'blue', 'purple', 'gray', 'black'];
    final color = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text('文字颜色', style: TextStyle(fontWeight: FontWeight.w800))),
            ...values.map((v) => ListTile(title: Text(v), onTap: () => Navigator.pop(context, v))),
          ],
        ),
      ),
    );
    if (color != null) _insert('[color=$color]{text}[/color]');
  }

  Future<void> _chooseEmoji() async {
    const emojis = ['😀','😂','😎','👍','❤️','🎉','😅','🤔','🔥','👏','🥳','🙏','✨','💡','🌟','🤣','😭','😇'];
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: emojis.map((e) => IconButton(iconSize: 30, icon: Text(e), onPressed: () => Navigator.pop(context, e))).toList(),
        ),
      ),
    );
    if (emoji != null) _insert(emoji);
  }

  Widget _tool(IconData icon, String label, VoidCallback action) => IconButton(
        tooltip: label,
        onPressed: _submitting || _uploading ? null : action,
        icon: Icon(icon, size: 20),
      );

  Future<void> _pickAttachments({bool imagesOnly = false}) async {
    if (_uploading || _submitting) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: imagesOnly ? FileType.image : FileType.any,
      );
      if (picked == null || picked.files.isEmpty) return;
      setState(() {
        _uploading = true;
        _error = null;
        _uploadStatus = '准备上传 0/${picked.files.length}';
      });
      for (var i = 0; i < picked.files.length; i++) {
        final file = picked.files[i];
        if (file.path == null || file.path!.isEmpty) continue;
        if (file.size > AttachmentUploadService.maxBytes) {
          if (mounted) setState(() => _error = '${file.name} 超过 10 MB，已跳过');
          continue;
        }
        if (mounted) setState(() => _uploadStatus = '正在上传 ${i + 1}/${picked.files.length}：${file.name}');
        try {
          final uploaded = await AttachmentUploadService.instance.upload(fid: widget.fid, file: file);
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

  bool _isImage(UploadedAttachment a) {
    final ext = a.name.toLowerCase().split('.').last;
    return const {'jpg','jpeg','png','gif','webp','bmp','heic','heif'}.contains(ext) && a.localPath != null;
  }

  void _insertAttachment(UploadedAttachment a) {
    _insert(_isImage(a) ? '[attachimg]${a.aid}[/attachimg]' : '[attach]${a.aid}[/attach]');
  }

  Widget _attachmentCard(ColorScheme scheme) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.photo_library_outlined, color: scheme.primary),
            const SizedBox(width: 9),
            const Expanded(child: Text('图片与附件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            PopupMenuButton<String>(
              enabled: !_uploading && !_submitting,
              onSelected: (v) => _pickAttachments(imagesOnly: v == 'image'),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'image', child: Text('从图库选择图片')),
                PopupMenuItem(value: 'file', child: Text('选择文件')),
              ],
              child: const Icon(Icons.add_circle_outline_rounded),
            ),
          ]),
          const SizedBox(height: 5),
          Text('新增附件可直接插入正文；原帖子已有附件不会被自动删除。', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          if (_uploading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 5),
            Text(_uploadStatus, style: const TextStyle(fontSize: 11)),
          ],
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final a = _attachments[i];
                  return GestureDetector(
                    onTap: () => _insertAttachment(a),
                    child: Stack(children: [
                      SizedBox(width: 104, height: 104, child: _isImage(a) ? Image.file(File(a.localPath!), fit: BoxFit.cover) : Card(child: Center(child: Text(a.name, maxLines: 2, textAlign: TextAlign.center)))),
                      Positioned(right: 2, top: 2, child: IconButton(onPressed: () => setState(() => _attachments.removeAt(i)), icon: const Icon(Icons.close, size: 18))),
                    ]),
                  );
                },
              ),
            ),
          ],
        ]),
      );

  Widget _editor(ColorScheme scheme) => Container(
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            child: Row(children: [
              const Icon(Icons.edit_note_rounded),
              const SizedBox(width: 8),
              const Expanded(child: Text('正文编辑器', style: TextStyle(fontWeight: FontWeight.w800))),
              ValueListenableBuilder<TextEditingValue>(valueListenable: _body, builder: (_, v, __) => Text('${v.text.length}/10000', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))),
            ]),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _tool(Icons.format_bold_rounded, '粗体', () => _insert('[b]{text}[/b]')),
              _tool(Icons.format_italic_rounded, '斜体', () => _insert('[i]{text}[/i]')),
              _tool(Icons.palette_outlined, '颜色', _chooseColor),
              _tool(Icons.image_outlined, '图片 URL', _insertImage),
              _tool(Icons.video_library_outlined, '视频', _insertVideo),
              _tool(Icons.link_rounded, '链接', _insertLink),
              _tool(Icons.format_quote_rounded, '引用', () => _insert('[quote]{text}[/quote]')),
              _tool(Icons.code_rounded, '代码', () => _insert('[code]{text}[/code]')),
              _tool(Icons.emoji_emotions_outlined, '表情', _chooseEmoji),
            ]),
          ),
          const Divider(height: 1),
          TextField(
            controller: _body,
            focusNode: _bodyFocus,
            enabled: !_submitting && !_uploading,
            minLines: 10,
            maxLines: 22,
            maxLength: 10000,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
            decoration: const InputDecoration(hintText: '编辑正文……\n支持网页端常用 BBCode。', border: InputBorder.none, contentPadding: EdgeInsets.fromLTRB(16, 12, 16, 18)),
          ),
        ]),
      );

  Widget _advanced(ColorScheme scheme) => Container(
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant)),
        child: Column(children: [
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.tune_rounded),
            title: const Text('高级设置', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('主题分类、售价、阅读权限、签名、通知等网页端选项'),
            value: _advanced,
            onChanged: _submitting || _uploading ? null : (v) => setState(() => _advanced = v),
          ),
          if (_advanced) Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              if (_types.isNotEmpty) DropdownButtonFormField<int>(value: _typeid, decoration: const InputDecoration(labelText: '主题分类', prefixIcon: Icon(Icons.label_outline)), items: _types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(), onChanged: (v) => setState(() => _typeid = v)),
              if (_types.isNotEmpty) const SizedBox(height: 10),
              DropdownButtonFormField<int>(value: _price, decoration: const InputDecoration(labelText: '主题售价', prefixIcon: Icon(Icons.monetization_on_outlined)), items: [0,1,2,3,5,10,20].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '免费' : '$v 星币'))).toList(), onChanged: (v) => setState(() => _price = v ?? 0)),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(value: _readperm, decoration: const InputDecoration(labelText: '阅读权限', prefixIcon: Icon(Icons.lock_outline)), items: [0,10,20,30,50,80,100,255].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不限' : '$v 级'))).toList(), onChanged: (v) => setState(() => _readperm = v ?? 0)),
              SwitchListTile.adaptive(title: const Text('使用个人签名'), value: _usesig, onChanged: (v) => setState(() => _usesig = v)),
              SwitchListTile.adaptive(title: const Text('接收回复通知'), value: _allownoticeauthor, onChanged: (v) => setState(() => _allownoticeauthor = v)),
              SwitchListTile.adaptive(title: const Text('回帖仅作者可见'), value: _hiddenreplies, onChanged: (v) => setState(() => _hiddenreplies = v)),
              SwitchListTile.adaptive(title: const Text('回帖倒序排列'), value: _descviewdefault, onChanged: (v) => setState(() => _descviewdefault = v)),
              SwitchListTile.adaptive(title: const Text('发送动态'), value: _addfeed, onChanged: (v) => setState(() => _addfeed = v)),
            ]),
          ),
        ]),
      );

  Future<void> _submit() async {
    if (_submitting) return;
    if (_title.text.trim().isEmpty) { setState(() => _error = '请输入标题'); return; }
    if (_body.text.trim().isEmpty && _attachments.isEmpty) { setState(() => _error = '请输入正文或添加附件'); return; }
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final err = await ThreadEditService.instance.editThread(
      tid: widget.tid,
      fid: widget.fid,
      pid: widget.pid,
      subject: _title.text,
      message: _body.text,
      typeid: _typeid,
      price: _price,
      readperm: _readperm,
      usesig: _usesig,
      allownoticeauthor: _allownoticeauthor,
      hiddenreplies: _hiddenreplies,
      descviewdefault: _descviewdefault,
      addfeed: _addfeed,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err != null) { setState(() => _error = err); return; }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('编辑成功')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('编辑主题', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: _advanced ? '收起高级设置' : '显示高级设置', onPressed: () => setState(() => _advanced = !_advanced), icon: Icon(_advanced ? Icons.edit_note : Icons.tune_rounded))],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: FilledButton.icon(
            onPressed: _submitting || _uploading || _loading ? null : _submit,
            icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
            label: Text(_submitting ? '保存中…' : '保存修改'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            enabled: !_submitting && !_uploading,
            maxLength: 100,
            decoration: InputDecoration(labelText: '标题', prefixIcon: const Icon(Icons.title_rounded), filled: true, fillColor: scheme.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 2),
          _editor(scheme),
          const SizedBox(height: 12),
          _attachmentCard(scheme),
          const SizedBox(height: 12),
          _advanced(scheme),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(17)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline, color: scheme.onErrorContainer), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))])),
          ],
        ],
      ),
    );
  }
}

/// 保留旧调用方兼容：正文若传入 HTML 时仅作最基本的纯文本回退。
String threadBodyToPlainText(String html) {
  if (html.trim().isEmpty) return '';
  return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim();
}
