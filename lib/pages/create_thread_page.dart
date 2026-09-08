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
import '../services/smiley_service.dart';
import '../services/thread_publish_service.dart';

/// Modern Material 3 native post composer.
/// 对齐 Discuz 网页端的主要发帖能力，同时保持原生 Flutter 交互。
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
  int _reward = 0;
  bool _usesig = true;
  bool _allownoticeauthor = true;
  bool _hiddenreplies = false;
  bool _descviewdefault = false;
  bool _addfeed = true;
  DateTime? _scheduledAt;
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

  void _markDirty() {
    _dirty = true;
    if (mounted) setState(() {});
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
      reward: _reward,
      usesig: _usesig,
      allownoticeauthor: _allownoticeauthor,
      hiddenreplies: _hiddenreplies,
      descviewdefault: _descviewdefault,
      addfeed: _addfeed,
      scheduledAt: _scheduledAt,
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
      _reward = draft.reward;
      _usesig = draft.usesig;
      _allownoticeauthor = draft.allownoticeauthor;
      _hiddenreplies = draft.hiddenreplies;
      _descviewdefault = draft.descviewdefault;
      _addfeed = draft.addfeed;
      _scheduledAt = draft.scheduledAt;
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
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: imagesOnly ? FileType.image : FileType.any,
      );
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
    _insert(_isImage(a) ? '[attachimg]${a.aid}[/attachimg]' : '[attach]${a.aid}[/attach]');
  }

  Future<void> _submit() async {
    if (_submitting || _uploading || !_formKey.currentState!.validate() || _fid == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await ThreadPublishService.instance.createThread(
      fid: _fid!,
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
      scheduledAt: _scheduledAt,
      reward: _reward,
      attachments: List.unmodifiable(_attachments),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      await PostDraftService.instance.clear();
      _dirty = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_scheduledAt == null ? '帖子发布成功' : '帖子已提交，按定时发布时间发布')),
      );
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
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
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

  Future<void> _insertTag() async {
    final value = await _ask('添加标签', hint: '例如：Android, Flutter');
    if (value != null && value.isNotEmpty) _insert('#$value ');
  }

  Future<void> _insertMention() async {
    final value = await _ask('@好友', hint: '输入用户名');
    if (value != null && value.isNotEmpty) _insert('@$value ');
  }

  Future<void> _chooseColor() async {
    const colors = ['red', 'orange', 'green', 'blue', 'purple', 'gray', 'black'];
    final color = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('文字颜色', style: TextStyle(fontWeight: FontWeight.w800))),
          Wrap(spacing: 8, runSpacing: 8, children: colors.map((c) => ActionChip(label: Text(c), onPressed: () => Navigator.pop(context, c))).toList()),
          const SizedBox(height: 20),
        ]),
      ),
    );
    if (color != null) _insert('[color=$color]{text}[/color]');
  }

  Widget _tool(IconData icon, String label, VoidCallback action) => IconButton(
        tooltip: label,
        onPressed: _submitting || _uploading ? null : action,
        icon: Icon(icon),
      );

  Widget _buildAttachments(ColorScheme scheme) {
    if (_attachments.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: ReorderableWrap(
        onReorder: _reorderAttachment,
        children: [
          for (final a in _attachments)
            Container(
              key: ValueKey(a.aid),
              width: 96,
              margin: const EdgeInsets.only(right: 8, bottom: 8),
              child: Column(children: [
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _isImage(a)
                        ? Image.file(File(a.localPath!), width: 96, height: 76, fit: BoxFit.cover)
                        : Container(width: 96, height: 76, alignment: Alignment.center, color: scheme.surface, child: Icon(Icons.insert_drive_file_outlined, color: scheme.primary)),
                  ),
                  Positioned(right: 2, top: 2, child: Material(color: Colors.black54, shape: const CircleBorder(), child: InkWell(onTap: _submitting ? null : () => _removeAttachment(a.aid), child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close_rounded, color: Colors.white, size: 15))))),
                ]),
                const SizedBox(height: 4),
                Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                TextButton(onPressed: _submitting ? null : () => _insertAttachment(a), child: const Text('插入')),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _scheduleCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = _scheduledAt == null ? '立即发布' : '${_scheduledAt!.year}-${_scheduledAt!.month.toString().padLeft(2, '0')}-${_scheduledAt!.day.toString().padLeft(2, '0')} ${_scheduledAt!.hour.toString().padLeft(2, '0')}:${_scheduledAt!.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.schedule_rounded, color: scheme.primary),
      title: const Text('定时发布'),
      subtitle: Text(text),
      trailing: Switch(value: _scheduledAt != null, onChanged: _submitting ? null : (value) async {
        if (!value) {
          setState(() => _scheduledAt = null);
          _markDirty();
          return;
        }
        final now = DateTime.now();
        final picked = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: now);
        if (!mounted || picked == null) return;
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
        if (!mounted || time == null) return;
        setState(() => _scheduledAt = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute));
        _markDirty();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) async {
        if (await _confirmLeave() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('发布主题', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            TextButton(onPressed: _submitting ? null : _submit, child: Text(_submitting ? '发布中' : '发布', style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (_loadingBoards)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()))
                else
                  DropdownButtonFormField<int>(
                    value: _fid,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '选择版块', prefixIcon: Icon(Icons.forum_outlined)),
                    items: _boards.map((b) => DropdownMenuItem(value: b.fid, child: Text(b.name, overflow: TextOverflow.ellipsis))).toList(),
                    validator: (v) => v == null ? '请选择版块' : null,
                    onChanged: _submitting ? null : (v) {
                      if (v == null) return;
                      setState(() { _fid = v; _typeid = null; });
                      _loadTypes(v);
                      _markDirty();
                    },
                  ),
                const SizedBox(height: 12),
                if (_types.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: _typeid,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '主题分类', prefixIcon: Icon(Icons.category_outlined)),
                    items: _types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                    onChanged: _submitting ? null : (v) { setState(() => _typeid = v); _markDirty(); },
                  ),
                if (_types.isNotEmpty) const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  enabled: !_submitting,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '标题', hintText: '请输入主题标题', prefixIcon: Icon(Icons.title_rounded)),
                  validator: (v) => v == null || v.trim().isEmpty ? '请输入标题' : null,
                ),
                const SizedBox(height: 8),
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
                        _tool(Icons.format_underlined_rounded, '下划线', () => _insert('[u]{text}[/u]')),
                        _tool(Icons.format_quote_rounded, '引用', () => _insert('[quote]{text}[/quote]')),
                        _tool(Icons.format_color_text_rounded, '颜色', _chooseColor),
                        _tool(Icons.image_outlined, '图片', _insertImage),
                        _tool(Icons.link_rounded, '链接', _insertLink),
                        _tool(Icons.video_library_outlined, '视频', _insertVideo),
                        _tool(Icons.tag_rounded, '标签', _insertTag),
                        _tool(Icons.alternate_email_rounded, '@好友', _insertMention),
                        const SizedBox(width: 4),
                      ]),
                    ),
                    SizedBox(
                      height: 180,
                      child: TextFormField(
                        controller: _body,
                        focusNode: _bodyFocus,
                        enabled: !_submitting,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(hintText: '分享想法、问题或资源……\n\n支持网页端常用 BBCode 格式。', border: InputBorder.none, contentPadding: EdgeInsets.all(16)),
                        validator: (v) => v == null || v.trim().isEmpty ? '请输入内容' : null,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton.icon(onPressed: _submitting || _uploading ? null : () => _pickAttachments(), icon: const Icon(Icons.attach_file_rounded), label: const Text('附件')),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(onPressed: _submitting || _uploading ? null : () => _pickAttachments(imagesOnly: true), icon: const Icon(Icons.photo_library_outlined), label: const Text('图片')),
                  if (_uploading) ...[
                    const SizedBox(width: 12),
                    Expanded(child: Text(_uploadStatus, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                  ],
                ]),
                if (_attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildAttachments(scheme),
                ],
                const SizedBox(height: 12),
                if (_advanced)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(children: [
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(value: _price, isExpanded: true, decoration: const InputDecoration(labelText: '主题售价', prefixIcon: Icon(Icons.monetization_on_outlined)), items: [0,1,2,3,5,10,20].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '免费' : '$v 星币'))).toList(), onChanged: _reward > 0 ? null : (v) { setState(() { _price = v ?? 0; _reward = 0; }); _markDirty(); }),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(value: _reward, isExpanded: true, decoration: InputDecoration(labelText: '悬赏奖励', helperText: _reward > 0 ? '将奖励给最佳回复' : null, prefixIcon: const Icon(Icons.card_giftcard_rounded)), items: [0,2,3,5,8,10,15,20,30,50].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不悬赏' : '悬赏 $v 星币'))).toList(), onChanged: _price > 0 ? null : (v) { setState(() { _reward = v ?? 0; if (_reward > 0) _price = 0; }); _markDirty(); }),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(value: _readperm, decoration: const InputDecoration(labelText: '阅读权限', prefixIcon: Icon(Icons.lock_outline_rounded)), items: [0,10,20,30,50,80,100,255].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不限' : '$v 级'))).toList(), onChanged: (v) { setState(() => _readperm = v ?? 0); _markDirty(); }),
                      const SizedBox(height: 10),
                      _scheduleCard(context),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      option('回帖仅作者可见', '其他用户的回复仅主题作者可见', _hiddenreplies, (v) => setState(() => _hiddenreplies = v), Icons.visibility_off_outlined),
                      option('默认倒序浏览', '打开主题时默认显示最新回复', _descviewdefault, (v) => setState(() => _descviewdefault = v), Icons.swap_vert_rounded),
                      option('添加到动态', '发布后同步到你的动态', _addfeed, (v) => setState(() => _addfeed = v), Icons.dynamic_feed_outlined),
                      option('使用个人签名', '在帖子末尾附加论坛签名', _usesig, (v) => setState(() => _usesig = v), Icons.draw_outlined),
                      option('通知作者', '允许作者收到你的回复提醒', _allownoticeauthor, (v) => setState(() => _allownoticeauthor = v), Icons.notifications_none_rounded),
                    ]),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: () => setState(() => _advanced = !_advanced), icon: Icon(_advanced ? Icons.expand_less : Icons.tune_rounded), label: Text(_advanced ? '收起高级设置' : '高级设置')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer, size: 20), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))])),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: _submitting ? null : _submit, icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded), label: Text(_submitting ? '发布中' : '发布主题'), style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget option(String title, String subtitle, bool value, ValueChanged<bool> onChanged, IconData icon) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _submitting ? null : onChanged,
    );
  }
}

class ReorderableWrap extends StatelessWidget {
  const ReorderableWrap({super.key, required this.children, required this.onReorder});

  final List<Widget> children;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return Wrap(children: children);
  }
}
