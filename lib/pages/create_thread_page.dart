import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/api_service.dart';
import '../services/attachment_upload_service.dart';
import '../services/auth_service.dart';
import '../services/post_draft_service.dart';
import '../services/site_fallback_service.dart';
import '../services/thread_publish_service.dart';

/// Modern Material 3 native post composer.
class CreateThreadPage extends StatefulWidget {
  const CreateThreadPage({super.key});

  @override
  State<CreateThreadPage> createState() => _CreateThreadPageState();
}

class _CreateThreadPageState extends State<CreateThreadPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  final List<UploadedAttachment> _attachments = [];

  List<ForumBoard> _boards = const [];
  List<ThreadType> _types = const [];
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
  bool _restoringDraft = true;
  bool _dirty = false;
  String? _error;
  String _uploadStatus = '';
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _title.addListener(_scheduleDraftSave);
    _body.addListener(_scheduleDraftSave);
    _loadBoards();
    _restoreDraft();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _title.removeListener(_scheduleDraftSave);
    _body.removeListener(_scheduleDraftSave);
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _scheduleDraftSave() {
    if (_restoringDraft || _submitting) return;
    _dirty = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), _saveDraft);
    if (mounted) setState(() {});
  }

  Future<void> _saveDraft() async {
    if (_restoringDraft || _submitting) return;
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) return;
    await PostDraftService.instance.save(PostDraft(
      title: _title.text,
      body: _body.text,
      fid: _fid,
      typeid: _typeid,
      price: _price,
      readperm: _readperm,
      usesig: _usesig,
      allownoticeauthor: _allownoticeauthor,
    ));
    if (mounted) setState(() {});
  }

  Future<void> _restoreDraft() async {
    final draft = await PostDraftService.instance.load();
    if (!mounted) return;
    if (draft == null || (draft.title.trim().isEmpty && draft.body.trim().isEmpty)) {
      setState(() => _restoringDraft = false);
      return;
    }
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现未完成的草稿'),
        content: const Text('上次编辑的帖子还没有发布，要继续编辑吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('丢弃')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续编辑')),
        ],
      ),
    );
    if (!mounted) return;
    if (restore == true) {
      _title.text = draft.title;
      _body.text = draft.body;
      _price = draft.price;
      _readperm = draft.readperm;
      _usesig = draft.usesig;
      _allownoticeauthor = draft.allownoticeauthor;
      _fid = draft.fid;
      _typeid = draft.typeid;
      _dirty = true;
    } else {
      await PostDraftService.instance.clear();
    }
    if (mounted) setState(() => _restoringDraft = false);
  }

  Future<bool> _confirmLeave() async {
    if (_submitting || _uploading || !_dirty || (_title.text.trim().isEmpty && _body.text.trim().isEmpty)) return true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            leading: Icon(Icons.edit_note_rounded),
            title: Text('帖子尚未发布', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('可以保存草稿后离开，稍后继续编辑。'),
          ),
          ListTile(leading: const Icon(Icons.save_outlined), title: const Text('保存草稿并离开'), onTap: () => Navigator.pop(context, 'save')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('直接离开'), onTap: () => Navigator.pop(context, 'leave')),
          ListTile(leading: const Icon(Icons.close_rounded), title: const Text('继续编辑'), onTap: () => Navigator.pop(context, 'cancel')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == 'save') {
      await _saveDraft();
      return true;
    }
    return action == 'leave';
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
        if (_fid == null || !boards.any((b) => b.fid == _fid)) _fid = boards.isNotEmpty ? boards.first.fid : null;
        _loadingBoards = false;
        _error = boards.isEmpty ? '暂时没有可发帖的版块' : null;
      });
      if (_fid != null) _loadTypes(_fid!);
    } catch (_) {
      if (mounted) setState(() { _loadingBoards = false; _error = '版块加载失败，请稍后重试'; });
    }
  }

  Future<void> _loadTypes(int fid) async {
    if (!mounted) return;
    setState(() { _loadingTypes = true; _types = const []; });
    final types = await ThreadPublishService.instance.fetchThreadTypes(fid);
    if (!mounted) return;
    setState(() {
      _types = types;
      _loadingTypes = false;
      if (_typeid == null || !types.any((t) => t.id == _typeid)) _typeid = types.isNotEmpty ? types.first.id : null;
    });
  }

  Future<void> _pickAttachments({bool imagesOnly = false}) async {
    if (_uploading || _submitting || _fid == null) return;
    try {
      final picked = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false, type: imagesOnly ? FileType.image : FileType.any);
      if (picked == null || picked.files.isEmpty) return;
      setState(() { _uploading = true; _error = null; _uploadStatus = '准备上传 0/${picked.files.length}'; });
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
          final uploaded = await AttachmentUploadService.instance.upload(fid: _fid!, file: file);
          if (mounted) {
            setState(() {
              _attachments.add(uploaded);
              _dirty = true;
            });
          }
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

  void _removeAttachment(int aid) => setState(() { _attachments.removeWhere((e) => e.aid == aid); _dirty = true; });

  void _reorderAttachment(int oldIndex, int newIndex) {
    if (_uploading || _submitting || oldIndex == newIndex) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _attachments.removeAt(oldIndex);
      _attachments.insert(newIndex, item);
      _dirty = true;
    });
  }

  bool _isImage(UploadedAttachment a) {
    final ext = a.name.toLowerCase().split('.').last;
    return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'}.contains(ext) && a.localPath != null;
  }

  void _insertAttachment(UploadedAttachment a) {
    if (_isImage(a)) {
      _insert('[attachimg]${a.aid}[/attachimg]');
    } else {
      _insert('[attach]${a.aid}[/attach]');
    }
  }

  Future<void> _submit() async {
    if (_submitting || _uploading || !_formKey.currentState!.validate() || _fid == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await ThreadPublishService.instance.createThread(
      fid: _fid!, subject: _title.text, message: _body.text, typeid: _typeid,
      price: _price, readperm: _readperm, usesig: _usesig,
      allownoticeauthor: _allownoticeauthor, attachments: List.unmodifiable(_attachments),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      await PostDraftService.instance.clear();
      _dirty = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('帖子发布成功')));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = result);
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

  Future<String?> _ask(String title, {String hint = ''}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: hint, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim())),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('插入'))],
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

  Future<void> _chooseColor() async {
    const colors = ['red', 'orange', 'green', 'blue', 'purple', 'gray', 'black'];
    final color = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('文字颜色', style: TextStyle(fontWeight: FontWeight.w800))),
        Wrap(spacing: 8, runSpacing: 8, children: colors.map((c) => ActionChip(label: Text(c), onPressed: () => Navigator.pop(context, c))).toList()),
        const SizedBox(height: 20),
      ])));
    if (color != null) _insert('[color=$color]{text}[/color]');
  }

  Future<void> _chooseEmoji() async {
    const emojis = ['😀','😂','😎','👍','❤️','🎉','😅','🤔','🔥','👏','🥳','🙏','✨','💡','🌟','🤣','😭','😇'];
    final emoji = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4,
        children: emojis.map((e) => IconButton(iconSize: 30, onPressed: () => Navigator.pop(context, e), icon: Text(e))).toList()))));
    if (emoji != null) _insert(emoji);
  }

  Widget _tool(IconData icon, String label, VoidCallback action) => IconButton(
    tooltip: label, onPressed: _submitting || _uploading ? null : action,
    style: IconButton.styleFrom(minimumSize: const Size(40, 40)), icon: Icon(icon, size: 20));

  Widget _editor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: scheme.outlineVariant.withOpacity(.65))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 16, 12, 8), child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.edit_note_rounded, size: 19, color: scheme.onPrimaryContainer)),
          const SizedBox(width: 10),
          const Expanded(child: Text('正文', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ValueListenableBuilder<TextEditingValue>(valueListenable: _body, builder: (_, v, __) => Text('${v.text.length}/10000', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
        ])),
        Container(height: 1, color: scheme.outlineVariant.withOpacity(.45)),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          const SizedBox(width: 6), _tool(Icons.format_bold_rounded, '粗体', () => _insert('[b]{text}[/b]')),
          _tool(Icons.format_italic_rounded, '斜体', () => _insert('[i]{text}[/i]')),
          _tool(Icons.palette_outlined, '颜色', _chooseColor), _tool(Icons.image_outlined, '图片 URL', _insertImage),
          _tool(Icons.link_rounded, '链接', _insertLink), _tool(Icons.format_quote_rounded, '引用', () => _insert('[quote]{text}[/quote]')),
          _tool(Icons.code_rounded, '代码', () => _insert('[code]{text}[/code]')), _tool(Icons.emoji_emotions_outlined, '表情', _chooseEmoji),
          const SizedBox(width: 6),
        ])),
        Container(height: 1, color: scheme.outlineVariant.withOpacity(.45)),
        TextFormField(controller: _body, focusNode: _bodyFocus, enabled: !_submitting && !_uploading,
          minLines: 10, maxLines: 22, maxLength: 10000, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: '写下你的想法、经验或资源分享……\n\n支持网页端常用 BBCode 格式。', border: InputBorder.none, contentPadding: EdgeInsets.fromLTRB(18, 14, 18, 18)),
          validator: (v) => v == null || v.trim().isEmpty ? (_attachments.isEmpty ? '请输入正文或添加附件' : null) : null),
      ]),
    );
  }

  Widget _attachmentTile(BuildContext context, UploadedAttachment a, int index) {
    final scheme = Theme.of(context).colorScheme;
    final image = _isImage(a);
    return GestureDetector(
      onTap: _submitting || _uploading ? null : () => _insertAttachment(a),
      child: Container(
        key: ValueKey(a.aid), width: 116, margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant.withOpacity(.55))),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          SizedBox(height: 126, width: 116, child: image ? Image.file(File(a.localPath!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _filePreview(scheme)) : _filePreview(scheme)),
          Positioned(left: 7, top: 7, child: Container(width: 25, height: 25, decoration: BoxDecoration(color: scheme.scrim.withOpacity(.55), shape: BoxShape.circle), child: Icon(Icons.drag_indicator_rounded, color: scheme.onInverseSurface, size: 17))),
          Positioned(right: 5, top: 5, child: Material(color: scheme.scrim.withOpacity(.58), shape: const CircleBorder(), child: InkWell(onTap: _submitting || _uploading ? null : () => _removeAttachment(a.aid), child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, color: scheme.onInverseSurface, size: 17))))),
          Positioned(left: 7, right: 7, bottom: 7, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5), decoration: BoxDecoration(color: scheme.scrim.withOpacity(.62), borderRadius: BorderRadius.circular(9)), child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onInverseSurface, fontSize: 10, fontWeight: FontWeight.w600)))),
        ]),
      ),
    );
  }

  Widget _filePreview(ColorScheme scheme) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.insert_drive_file_rounded, size: 38, color: scheme.primary),
    const SizedBox(height: 6), Text('点按插入附件', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
  ]);

  Widget _attachmentCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withOpacity(.65))),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.photo_library_outlined, size: 19, color: scheme.onSecondaryContainer)),
          const SizedBox(width: 10), const Expanded(child: Text('图片与附件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          PopupMenuButton<String>(enabled: !_submitting && !_uploading, tooltip: '添加', icon: const Icon(Icons.add_circle_outline_rounded), onSelected: (value) { if (value == 'image') _pickAttachments(imagesOnly: true); else _pickAttachments(); }, itemBuilder: (_) => const [
            PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('从图库选择'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.attach_file_rounded), title: Text('选择文件'), contentPadding: EdgeInsets.zero)),
          ]),
        ]),
        const SizedBox(height: 5), Text('点按缩略图插入正文 · 长按拖动可调整顺序 · 单个文件最大 10 MB', style: TextStyle(fontSize: 12)),
        if (_uploading) ...[const SizedBox(height: 12), const LinearProgressIndicator(minHeight: 3), const SizedBox(height: 6), Text(_uploadStatus, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))],
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(height: 126, child: ReorderableListView.builder(scrollDirection: Axis.horizontal, buildDefaultDragHandles: false, itemCount: _attachments.length, onReorder: _reorderAttachment,
            itemBuilder: (context, index) => ReorderableDragStartListener(index: index, enabled: !_uploading && !_submitting, child: _attachmentTile(context, _attachments[index], index))),
        ] else if (!_uploading) ...[
          const SizedBox(height: 12),
          InkWell(onTap: _submitting ? null : () => _pickAttachments(imagesOnly: true), borderRadius: BorderRadius.circular(17), child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(.35), borderRadius: BorderRadius.circular(17), border: Border.all(color: scheme.outlineVariant)), child: Column(children: [
            Icon(Icons.add_photo_alternate_outlined, size: 28, color: scheme.primary), const SizedBox(height: 7), const Text('添加图片', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text('点击从图库选择图片', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ]))),
        ],
      ]),
    );
  }

  Widget _advancedCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withOpacity(.65))),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(contentPadding: const EdgeInsets.fromLTRB(16, 4, 10, 4), leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(11)), child: Icon(Icons.tune_rounded, color: scheme.onTertiaryContainer)),
          title: const Text('高级设置', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('售价、阅读权限、签名与回复提醒'), trailing: Switch(value: _advanced, onChanged: _submitting || _uploading ? null : (v) => setState(() { _advanced = v; _dirty = true; }))),
        if (_advanced) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Column(children: [
          const Divider(height: 1), const SizedBox(height: 14),
          DropdownButtonFormField<int>(value: _price, decoration: const InputDecoration(labelText: '主题售价', prefixIcon: Icon(Icons.monetization_on_outlined)), items: [0,1,2,3,5,10,20].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '免费' : '$v 星币'))).toList(), onChanged: (v) => setState(() { _price = v ?? 0; _dirty = true; })),
          const SizedBox(height: 12), DropdownButtonFormField<int>(value: _readperm, decoration: const InputDecoration(labelText: '阅读权限', prefixIcon: Icon(Icons.lock_outline_rounded)), items: [0,10,20,30,50,80,100].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不限' : '$v 级'))).toList(), onChanged: (v) => setState(() { _readperm = v ?? 0; _dirty = true; })),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('使用个人签名'), value: _usesig, onChanged: (v) => setState(() { _usesig = v; _dirty = true; })),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('允许回复提醒作者'), value: _allownoticeauthor, onChanged: (v) => setState(() { _allownoticeauthor = v; _dirty = true; })),
        ])),
      ]),
    );
  }

  InputDecoration _field(String label, String hint, IconData icon, ColorScheme scheme) => InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon), filled: true, fillColor: scheme.surfaceContainerHighest.withOpacity(.48), border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide(color: scheme.primary, width: 1.4)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: AppBar(titleSpacing: 4, title: const Text('发布帖子', style: TextStyle(fontWeight: FontWeight.w800)), actions: [
          if (_dirty) const Center(child: Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.cloud_done_outlined, size: 18))),
          IconButton(tooltip: _advanced ? '快速模式' : '高级模式', onPressed: _submitting || _uploading ? null : () => setState(() => _advanced = !_advanced), icon: Icon(_advanced ? Icons.edit_note_rounded : Icons.tune_rounded)), const SizedBox(width: 4),
        ]),
        bottomNavigationBar: SafeArea(child: Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), decoration: BoxDecoration(color: scheme.surface.withOpacity(.96), boxShadow: [BoxShadow(blurRadius: 18, color: Colors.black.withOpacity(.06))]), child: Row(children: [
          Expanded(child: Text(_submitting ? '正在发布…' : (_dirty ? '草稿已自动保存' : '准备好后就可以发布了'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
          FilledButton.icon(onPressed: _submitting || _uploading || _loadingBoards ? null : _submit, icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 19), label: Text(_submitting ? '发布中' : '发布帖子'), style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 20))),
        ])),
        body: SafeArea(child: Form(key: _formKey, child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
          Container(padding: const EdgeInsets.fromLTRB(18, 16, 18, 14), decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]), borderRadius: BorderRadius.circular(24)), child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: scheme.surface.withOpacity(.72), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.forum_rounded, color: scheme.primary)), const SizedBox(width: 13),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('分享点什么吧', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), SizedBox(height: 3), Text('原生编辑 · 网页端 BBCode · 图片与附件', style: TextStyle(fontSize: 12))])),
          ])),
          const SizedBox(height: 14),
          if (_loadingBoards) const LinearProgressIndicator(minHeight: 2),
          if (_boards.isNotEmpty) ...[
            DropdownButtonFormField<int>(value: _fid, decoration: _field('发布到版块', '选择一个版块', Icons.forum_outlined, scheme), items: _boards.map((b) => DropdownMenuItem(value: b.fid, child: Text(b.name))).toList(), onChanged: _submitting || _uploading ? null : (v) { setState(() { _fid = v; _dirty = true; }); if (v != null) _loadTypes(v); }),
            const SizedBox(height: 11),
          ],
          if (_types.isNotEmpty) ...[
            DropdownButtonFormField<int>(value: _typeid, decoration: _field('主题分类', '选择分类', Icons.label_outline_rounded, scheme), items: _types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(), onChanged: _submitting || _uploading ? null : (v) => setState(() { _typeid = v; _dirty = true; })), const SizedBox(height: 11),
          ],
          if (_loadingTypes) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 2)),
          TextFormField(controller: _title, enabled: !_submitting && !_uploading, maxLength: 100, textInputAction: TextInputAction.next, decoration: _field('标题', '一句话概括你的帖子', Icons.title_rounded, scheme), validator: (v) => v == null || v.trim().isEmpty ? '请输入标题' : null),
          const SizedBox(height: 2), _editor(context), const SizedBox(height: 12), _attachmentCard(context), const SizedBox(height: 12), _advancedCard(context),
          if (_error != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(17)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer), const SizedBox(width: 9), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))]))],
          const SizedBox(height: 12), Center(child: Text('草稿仅保存在本机；附件仍通过论坛原生上传。', style: TextStyle(fontSize: 11))),
        ]))),
      ),
    );
  }
}
