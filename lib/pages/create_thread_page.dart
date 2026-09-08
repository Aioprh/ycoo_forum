import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/api_service.dart';
import '../services/attachment_upload_service.dart';
import '../services/auth_service.dart';
import '../services/official_smiley_service.dart';
import '../services/post_draft_service.dart';
import '../services/site_fallback_service.dart';
import '../services/thread_publish_service.dart';

/// Material 3 原生发帖页。
/// 保留完整发帖能力：BBCode 工具栏、图片/附件上传、拖动排序、草稿、定时发布、
/// 售价/悬赏/阅读权限、回复与动态设置。
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
  Timer? _draftTimer;

  List<ForumBoard> _boards = const [];
  List<ThreadType> _types = const [];
  int? _fid;
  int? _typeid;
  int _price = 0;
  int _reward = 0;
  int _readperm = 0;
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

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTextChanged);
    _body.addListener(_onTextChanged);
    _loadBoards();
    _restoreDraft();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _title.removeListener(_onTextChanged);
    _body.removeListener(_onTextChanged);
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_restoringDraft || _submitting) return;
    _dirty = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), _saveDraft);
    if (mounted) setState(() {});
  }

  void _markDirty() {
    if (!_restoringDraft && mounted) setState(() => _dirty = true);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _submitting) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存当前草稿？'),
        content: const Text('当前帖子还有未发布的内容。离开后草稿仍会保存在本机。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('直接离开')),
          FilledButton(onPressed: () async { await _saveDraft(); if (context.mounted) Navigator.pop(context, true); }, child: const Text('保存并离开')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('继续编辑')),
        ],
      ),
    );
    return leave ?? false;
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
    if (draft != null && (draft.title.trim().isNotEmpty || draft.body.trim().isNotEmpty)) {
      final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发现未完成的草稿'),
          content: const Text('继续上次未发布的帖子吗？'),
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
        _fid = draft.fid;
        _typeid = draft.typeid;
        _price = draft.price;
        _reward = draft.reward;
        _readperm = draft.readperm;
        _usesig = draft.usesig;
        _allownoticeauthor = draft.allownoticeauthor;
        _hiddenreplies = draft.hiddenreplies;
        _descviewdefault = draft.descviewdefault;
        _addfeed = draft.addfeed;
        _scheduledAt = draft.scheduledAt;
        _dirty = true;
      } else {
        await PostDraftService.instance.clear();
      }
    }
    if (mounted) setState(() => _restoringDraft = false);
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
      final boards = groups.expand((e) => e.boards).where((e) => e.fid > 0).toList();
      if (!mounted) return;
      setState(() {
        _boards = boards;
        if (_fid == null || !boards.any((e) => e.fid == _fid)) {
          _fid = boards.isEmpty ? null : boards.first.fid;
        }
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
      if (_typeid == null || !types.any((e) => e.id == _typeid)) {
        _typeid = types.isEmpty ? null : types.first.id;
      }
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
          if (mounted) setState(() { _attachments.add(uploaded); _dirty = true; });
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

  void _insertAttachment(UploadedAttachment a) => _insert(_isImage(a) ? '[attachimg]${a.aid}[/attachimg]' : '[attach]${a.aid}[/attach]');

  int _offset(num value, int length) => value.clamp(0, length).toInt();

  void _insert(String value) {
    final text = _body.text;
    final selection = _body.selection;
    final start = selection.isValid ? _offset(selection.start, text.length) : text.length;
    final end = selection.isValid ? _offset(selection.end, text.length) : text.length;
    final selected = text.substring(start, end);
    final replacement = value.replaceAll('{text}', selected.isEmpty ? '文字' : selected);
    final newText = text.replaceRange(start, end, replacement);
    _body.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: _offset(start + replacement.length, newText.length)));
    _bodyFocus.requestFocus();
  }

  Future<String?> _ask(String title, {String hint = ''}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hint, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)), onSubmitted: (_) => Navigator.pop(context, controller.text.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('插入')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _insertImage() async { final url = await _ask('插入图片', hint: '图片 URL'); if (url != null && url.isNotEmpty) _insert('[img]$url[/img]'); }
  Future<void> _insertLink() async { final url = await _ask('插入链接', hint: 'https://example.com'); if (url != null && url.isNotEmpty) _insert('[url=$url]{text}[/url]'); }
  Future<void> _insertVideo() async { final url = await _ask('插入视频', hint: '视频 URL'); if (url != null && url.isNotEmpty) _insert('[media=video,0,0]$url[/media]'); }
  Future<void> _insertTag() async { final value = await _ask('添加标签', hint: '例如：Android, Flutter'); if (value != null && value.isNotEmpty) _insert('#$value '); }
  Future<void> _insertMention() async { final value = await _ask('@好友', hint: '输入用户名'); if (value != null && value.isNotEmpty) _insert('@$value '); }

  Future<void> _chooseColor() async {
    const colors = ['red', 'orange', 'green', 'blue', 'purple', 'gray', 'black'];
    final color = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const ListTile(title: Text('文字颜色', style: TextStyle(fontWeight: FontWeight.w800))), Wrap(spacing: 8, runSpacing: 8, children: colors.map((c) => ActionChip(label: Text(c), onPressed: () => Navigator.pop(context, c))).toList()), const SizedBox(height: 20)])));
    if (color != null) _insert('[color=$color]{text}[/color]');
  }

  Future<void> _chooseEmoji() async {
    final fid = _fid;
    if (fid == null) {
      if (mounted) setState(() => _error = '请先选择发布版块');
      return;
    }
    final future = OfficialSmileyService.instance.fetch(fid);
    final smileys = await showModalBottomSheet<List<OfficialSmiley>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FutureBuilder<List<OfficialSmiley>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
              return const SizedBox(height: 180, child: Center(child: Text('暂时无法加载论坛官方表情')));
            }
            final items = snapshot.data!;
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .55,
              child: Column(children: [
                const Padding(padding: EdgeInsets.fromLTRB(18, 4, 18, 10), child: Row(children: [Icon(Icons.emoji_emotions_outlined), SizedBox(width: 10), Text('论坛官方表情', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))])),
                Expanded(child: GridView.builder(padding: const EdgeInsets.fromLTRB(14, 4, 14, 18), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1), itemCount: items.length, itemBuilder: (context, index) {
                  final item = items[index];
                  return InkWell(borderRadius: BorderRadius.circular(12), onTap: () => Navigator.pop(context, [item]), child: Padding(padding: const EdgeInsets.all(5), child: Image.network(item.imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))));
                })),
              ]),
            );
          },
        ),
      ),
    );
    if (smileys != null && smileys.isNotEmpty) _insert(smileys.first.code);
  }

  Widget _tool(IconData icon, String label, VoidCallback action) => IconButton(tooltip: label, onPressed: _submitting || _uploading ? null : action, style: IconButton.styleFrom(minimumSize: const Size(40, 40)), icon: Icon(icon, size: 20));

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
          const SizedBox(width: 6),
          _tool(Icons.format_bold_rounded, '粗体', () => _insert('[b]{text}[/b]')),
          _tool(Icons.format_italic_rounded, '斜体', () => _insert('[i]{text}[/i]')),
          _tool(Icons.emoji_emotions_outlined, '论坛表情', _chooseEmoji),
          _tool(Icons.palette_outlined, '颜色', _chooseColor),
          _tool(Icons.image_outlined, '图片 URL', _insertImage),
          _tool(Icons.video_library_outlined, '视频', _insertVideo),
          _tool(Icons.link_rounded, '链接', _insertLink),
          _tool(Icons.local_offer_outlined, '标签', _insertTag),
          _tool(Icons.alternate_email_rounded, '@好友', _insertMention),
          _tool(Icons.format_quote_rounded, '引用', () => _insert('[quote]{text}[/quote]')),
          _tool(Icons.code_rounded, '代码', () => _insert('[code]{text}[/code]')),
          const SizedBox(width: 6),
        ])),
        Container(height: 1, color: scheme.outlineVariant.withOpacity(.45)),
        TextFormField(controller: _body, focusNode: _bodyFocus, enabled: !_submitting && !_uploading, minLines: 10, maxLines: 22, maxLength: 10000, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(), textInputAction: TextInputAction.newline, decoration: const InputDecoration(hintText: '写下你的想法、经验或资源分享……\n\n支持网页端常用 BBCode 格式。', border: InputBorder.none, contentPadding: EdgeInsets.fromLTRB(18, 14, 18, 18)), validator: (v) => v == null || v.trim().isEmpty ? (_attachments.isEmpty ? '请输入正文或添加附件' : null) : null),
      ]),
    );
  }

  Widget _filePreview(ColorScheme scheme) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.insert_drive_file_rounded, size: 38, color: scheme.primary), const SizedBox(height: 6), Text('点按插入附件', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600))]));

  Widget _attachmentTile(BuildContext context, UploadedAttachment a) {
    final scheme = Theme.of(context).colorScheme;
    final image = _isImage(a);
    return GestureDetector(
      onTap: _submitting || _uploading ? null : () => _insertAttachment(a),
      child: Container(
        key: ValueKey(a.aid),
        width: 116,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(.45), borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant.withOpacity(.55))),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          SizedBox(height: 126, width: 116, child: image ? Image.file(File(a.localPath!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _filePreview(scheme)) : _filePreview(scheme)),
          Positioned(right: 5, top: 5, child: Material(color: scheme.scrim.withOpacity(.58), shape: const CircleBorder(), child: InkWell(onTap: _submitting || _uploading ? null : () => _removeAttachment(a.aid), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, color: Colors.white, size: 17))))),
          Positioned(left: 7, right: 7, bottom: 7, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5), decoration: BoxDecoration(color: scheme.scrim.withOpacity(.62), borderRadius: BorderRadius.circular(9)), child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)))),
        ]),
      ),
    );
  }

  Widget _attachmentCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withOpacity(.65))),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.photo_library_outlined, size: 19, color: scheme.onSecondaryContainer)),
          const SizedBox(width: 10),
          const Expanded(child: Text('图片与附件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          PopupMenuButton<String>(
            enabled: !_submitting && !_uploading,
            tooltip: '添加',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onSelected: (value) => value == 'image' ? _pickAttachments(imagesOnly: true) : _pickAttachments(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('从图库选择'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.attach_file_rounded), title: Text('选择文件'), contentPadding: EdgeInsets.zero)),
            ],
          ),
        ]),
        const SizedBox(height: 5),
        const Text('点按缩略图插入正文 · 长按拖动可调整顺序 · 单个文件最大 10 MB', style: TextStyle(fontSize: 12)),
        if (_uploading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 6),
          Text(_uploadStatus, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
        ],
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(height: 126, child: ReorderableListView.builder(scrollDirection: Axis.horizontal, buildDefaultDragHandles: false, itemCount: _attachments.length, onReorder: _reorderAttachment, itemBuilder: (context, index) => ReorderableDragStartListener(index: index, enabled: !_uploading && !_submitting, child: _attachmentTile(context, _attachments[index])))),
        ] else if (!_uploading) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: _submitting ? null : () => _pickAttachments(imagesOnly: true),
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(.35), borderRadius: BorderRadius.circular(17), border: Border.all(color: scheme.outlineVariant)),
              child: Column(children: [Icon(Icons.add_photo_alternate_outlined, size: 28, color: scheme.primary), const SizedBox(height: 7), const Text('添加图片', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text('点击从图库选择图片', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))]),
            ),
          ),
        ],
      ]),
    );
  }

  String _scheduleLabel() {
    final value = _scheduledAt;
    if (value == null) return '立即发布';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} 发布';
  }

  String _scheduleRelativeLabel(DateTime value) {
    final minutes = value.difference(DateTime.now()).inMinutes;
    if (minutes < 60) return '约 $minutes 分钟后发布';
    final hours = minutes ~/ 60;
    final remain = minutes % 60;
    if (hours < 24) return remain == 0 ? '约 $hours 小时后发布' : '约 $hours 小时 $remain 分钟后发布';
    return '约 ${hours ~/ 24} 天后发布';
  }

  Future<DateTime?> _pickCustomSchedule(DateTime initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 1, now.month, now.day), initialDate: initial.isBefore(now) ? now : initial, helpText: '选择发布时间', cancelText: '取消', confirmText: '下一步');
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial), helpText: '选择发布时间', cancelText: '取消', confirmText: '完成');
    if (time == null || !mounted) return null;
    final value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!value.isAfter(DateTime.now())) { setState(() => _error = '定时发布时间必须晚于当前时间'); return null; }
    return value;
  }

  Future<void> _chooseSchedule() async {
    final now = DateTime.now();
    final current = _scheduledAt != null && _scheduledAt!.isAfter(now) ? _scheduledAt!.toLocal() : now.add(const Duration(minutes: 10));
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        var minutes = current.difference(now).inMinutes.clamp(5, 180).toDouble();
        DateTime custom = current;
        var customMode = false;
        return StatefulBuilder(builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          final preview = customMode ? custom : now.add(Duration(minutes: minutes.round()));
          return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 18), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('定时发布', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('选择发布时间，设置后会自动保存到草稿。', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Row(children: [Expanded(child: ChoiceChip(label: const Text('按时长定时'), selected: !customMode, onSelected: (_) => setSheetState(() => customMode = false))), const SizedBox(width: 8), Expanded(child: ChoiceChip(label: const Text('指定时间'), selected: customMode, onSelected: (_) => setSheetState(() => customMode = true)))]),
            const SizedBox(height: 14),
            if (!customMode) ...[
              Center(child: Text('${minutes.round()} 分钟', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: scheme.primary))),
              Center(child: Text(_scheduleRelativeLabel(preview), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
              Slider(value: minutes, min: 5, max: 180, divisions: 35, label: '${minutes.round()} 分钟', onChanged: (value) => setSheetState(() => minutes = value)),
              Row(children: [for (final value in const [10, 30, 60, 120]) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: OutlinedButton(onPressed: () => setSheetState(() => minutes = value.toDouble()), child: Text(value >= 60 ? '${value ~/ 60} 小时' : '$value 分钟'))))]),
            ] else ...[
              Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(.55), borderRadius: BorderRadius.circular(17)), child: Row(children: [Icon(Icons.event_available_rounded, color: scheme.primary), const SizedBox(width: 10), Expanded(child: Text(_scheduleLabelFor(custom), style: const TextStyle(fontWeight: FontWeight.w800))), IconButton(onPressed: () async { final picked = await _pickCustomSchedule(custom); if (picked != null) setSheetState(() => custom = picked); }, icon: const Icon(Icons.edit_calendar_rounded))])),
            ],
            const SizedBox(height: 16),
            Row(children: [if (_scheduledAt != null) ...[Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext, DateTime.fromMillisecondsSinceEpoch(0)), child: const Text('取消定时'))), const SizedBox(width: 10)], Expanded(flex: 2, child: FilledButton.icon(onPressed: () => Navigator.pop(sheetContext, preview), icon: const Icon(Icons.schedule_send_rounded), label: const Text('确认定时')))]),
          ])));
        });
      },
    );
    if (!mounted || selected == null) return;
    if (selected.millisecondsSinceEpoch == 0) { setState(() { _scheduledAt = null; _dirty = true; }); await _saveDraft(); return; }
    if (!selected.isAfter(DateTime.now())) { setState(() => _error = '定时发布时间必须晚于当前时间'); return; }
    setState(() { _scheduledAt = selected; _dirty = true; _error = null; });
    await _saveDraft();
  }

  String _scheduleLabelFor(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} · ${_scheduleRelativeLabel(value)}';
  }

  Widget _scheduleCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scheduled = _scheduledAt?.toLocal();
    return Container(
      decoration: BoxDecoration(color: scheduled == null ? scheme.surfaceContainerHighest.withOpacity(.35) : scheme.primaryContainer.withOpacity(.55), borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant.withOpacity(.55))),
      child: InkWell(onTap: _submitting || _uploading ? null : _chooseSchedule, borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 8, 12), child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.surface.withOpacity(.8), borderRadius: BorderRadius.circular(13)), child: Icon(scheduled == null ? Icons.schedule_rounded : Icons.event_available_rounded, color: scheduled == null ? scheme.onSurfaceVariant : scheme.primary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(scheduled == null ? '定时发布' : '已设置定时', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(scheduled == null ? '按时长或指定时间发布' : _scheduleLabelFor(scheduled), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: scheduled == null ? scheme.onSurfaceVariant : scheme.primary, fontWeight: scheduled == null ? FontWeight.normal : FontWeight.w700))])),
        Icon(scheduled == null ? Icons.chevron_right_rounded : Icons.edit_rounded, color: scheme.onSurfaceVariant),
      ]))),
    );
  }

  Widget _advancedCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(String title, String subtitle, bool value, ValueChanged<bool> onChanged, IconData icon) => SwitchListTile.adaptive(contentPadding: const EdgeInsets.symmetric(horizontal: 2), secondary: Icon(icon), title: Text(title), subtitle: Text(subtitle, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)), value: value, onChanged: _submitting || _uploading ? null : (v) { onChanged(v); _markDirty(); });
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withOpacity(.65))),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(contentPadding: const EdgeInsets.fromLTRB(16, 4, 10, 4), leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(11)), child: Icon(Icons.tune_rounded, color: scheme.onTertiaryContainer)), title: const Text('高级设置', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('售价、悬赏、权限、定时发布、动态与回复设置'), trailing: Switch(value: _advanced, onChanged: _submitting || _uploading ? null : (v) => setState(() { _advanced = v; _dirty = true; }))),
        if (_advanced) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Column(children: [
          const Divider(height: 1), const SizedBox(height: 12),
          DropdownButtonFormField<int>(value: _price, decoration: const InputDecoration(labelText: '主题售价', prefixIcon: Icon(Icons.monetization_on_outlined)), items: const [0, 1, 2, 3, 5, 10, 20].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '免费' : '$v 星币'))).toList(), onChanged: _reward > 0 ? null : (v) => setState(() { _price = v ?? 0; _dirty = true; })),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(value: _reward, decoration: InputDecoration(labelText: '悬赏奖励', helperText: _reward > 0 ? '将奖励给最佳回复' : null, prefixIcon: const Icon(Icons.card_giftcard_rounded)), items: const [0, 2, 3, 5, 8, 10, 20, 30, 50].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不悬赏' : '悬赏 $v 星币'))).toList(), onChanged: _price > 0 ? null : (v) => setState(() { _reward = v ?? 0; _dirty = true; })),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(value: _readperm, decoration: const InputDecoration(labelText: '阅读权限', prefixIcon: Icon(Icons.lock_outline_rounded)), items: const [0, 10, 20, 30, 50, 80, 100, 255].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不限' : '$v 级'))).toList(), onChanged: (v) => setState(() { _readperm = v ?? 0; _dirty = true; })),
          const SizedBox(height: 10), _scheduleCard(context), const SizedBox(height: 8), const Divider(height: 1),
          option('回帖仅作者可见', '其他用户的回复仅主题作者可见', _hiddenreplies, (v) => setState(() => _hiddenreplies = v), Icons.visibility_off_outlined),
          option('回帖倒序排列', '帖子打开时优先显示最新回复', _descviewdefault, (v) => setState(() => _descviewdefault = v), Icons.swap_vert_rounded),
          option('接收回复通知', '有人回复主题时通知我', _allownoticeauthor, (v) => setState(() => _allownoticeauthor = v), Icons.notifications_none_rounded),
          option('发送动态', '发布后同步到个人动态/广播', _addfeed, (v) => setState(() => _addfeed = v), Icons.campaign_outlined),
          option('使用个人签名', '在帖子正文末尾显示论坛签名', _usesig, (v) => setState(() => _usesig = v), Icons.draw_outlined),
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
        appBar: AppBar(titleSpacing: 4, title: const Text('发布帖子', style: TextStyle(fontWeight: FontWeight.w800)), actions: [if (_dirty) const Center(child: Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.cloud_done_outlined, size: 18))), IconButton(tooltip: _advanced ? '快速模式' : '高级模式', onPressed: _submitting || _uploading ? null : () => setState(() { _advanced = !_advanced; _dirty = true; }), icon: Icon(_advanced ? Icons.edit_note_rounded : Icons.tune_rounded)), const SizedBox(width: 4)]),
        bottomNavigationBar: SafeArea(child: Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), decoration: BoxDecoration(color: scheme.surface.withOpacity(.96), boxShadow: [BoxShadow(blurRadius: 18, color: Colors.black.withOpacity(.06))]), child: Row(children: [Expanded(child: Text(_submitting ? '正在发布…' : (_scheduledAt != null ? _scheduleLabel() : (_dirty ? '草稿已自动保存' : '准备好后就可以发布了')), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)), FilledButton.icon(onPressed: _submitting || _uploading || _loadingBoards ? null : _submit, icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 19), label: Text(_submitting ? '发布中' : (_scheduledAt == null ? '发布帖子' : '定时发布')), style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 20)))])),
        body: SafeArea(child: Form(key: _formKey, child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
          Container(padding: const EdgeInsets.fromLTRB(18, 16, 18, 14), decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]), borderRadius: BorderRadius.circular(24)), child: Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: scheme.surface.withOpacity(.72), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.forum_rounded, color: scheme.primary)), const SizedBox(width: 13), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('分享点什么吧', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), SizedBox(height: 3), Text('原生编辑 · 网页端 BBCode · 图片与附件', style: TextStyle(fontSize: 12))]))])),
          const SizedBox(height: 14),
          if (_loadingBoards) const LinearProgressIndicator(minHeight: 2),
          if (_boards.isNotEmpty) ...[DropdownButtonFormField<int>(value: _fid, decoration: _field('发布到版块', '选择一个版块', Icons.forum_outlined, scheme), items: _boards.map((b) => DropdownMenuItem(value: b.fid, child: Text(b.name))).toList(), onChanged: _submitting || _uploading ? null : (v) { setState(() { _fid = v; _dirty = true; }); if (v != null) _loadTypes(v); }), const SizedBox(height: 11)],
          if (_types.isNotEmpty) ...[DropdownButtonFormField<int>(value: _typeid, decoration: _field('主题分类', '选择分类', Icons.label_outline_rounded, scheme), items: _types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(), onChanged: _submitting || _uploading ? null : (v) => setState(() { _typeid = v; _dirty = true; })), const SizedBox(height: 11)],
          if (_loadingTypes) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 2)),
          TextFormField(controller: _title, enabled: !_submitting && !_uploading, maxLength: 100, textInputAction: TextInputAction.next, decoration: _field('标题', '一句话概括你的帖子', Icons.title_rounded, scheme), validator: (v) => v == null || v.trim().isEmpty ? '请输入标题' : null),
          const SizedBox(height: 2),
          _editor(context),
          const SizedBox(height: 12),
          _attachmentCard(context),
          const SizedBox(height: 12),
          _advancedCard(context),
          if (_error != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(17)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer), const SizedBox(width: 9), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))]))],
          const SizedBox(height: 12), const Center(child: Text('草稿仅保存在本机；附件仍通过论坛原生上传。', style: TextStyle(fontSize: 11))),
        ]))),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || _uploading || !_formKey.currentState!.validate() || _fid == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await ThreadPublishService.instance.createThread(
      fid: _fid!, subject: _title.text, message: _body.text, typeid: _typeid, price: _price, readperm: _readperm,
      usesig: _usesig, allownoticeauthor: _allownoticeauthor, hiddenreplies: _hiddenreplies, descviewdefault: _descviewdefault,
      addfeed: _addfeed, scheduledAt: _scheduledAt, reward: _reward, attachments: List.unmodifiable(_attachments),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      await PostDraftService.instance.clear();
      _dirty = false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_scheduledAt == null ? '帖子发布成功' : '帖子已提交，按定时发布时间发布')));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = result);
    }
  }
}
