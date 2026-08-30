import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/api_service.dart';
import '../services/attachment_upload_service.dart';
import '../services/auth_service.dart';
import '../services/site_fallback_service.dart';
import '../services/thread_publish_service.dart';

/// 原生发帖页：选择版块、填写标题和正文，并支持按源论坛规则上传附件。
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
      if (mounted)
        setState(() {
          _loadingBoards = false;
          _error = '请先登录论坛';
        });
      return;
    }
    try {
      List<ForumCategory> groups;
      try {
        groups = await ApiService.instance.fetchBoards();
      } catch (_) {
        groups = await SiteFallbackService.instance.fetchBoards();
      }
      final boards = groups
          .expand((g) => g.boards)
          .where((b) => b.fid > 0)
          .toList();
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
      if (mounted)
        setState(() {
          _loadingBoards = false;
          _error = '版块加载失败，请稍后重试';
        });
    }
  }

  Future<void> _loadTypes(int fid) async {
    setState(() {
      _loadingTypes = true;
      _types = const [];
      _typeid = null;
    });
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
        if (mounted)
          setState(
            () => _uploadStatus =
                '正在上传 ${i + 1}/${picked.files.length}：${file.name}',
          );
        try {
          final uploaded = await AttachmentUploadService.instance.upload(
            fid: fid,
            file: file,
          );
          if (mounted) setState(() => _attachments.add(uploaded));
        } catch (e) {
          if (mounted)
            setState(
              () => _error =
                  '${file.name}：${e.toString().replaceFirst('Exception: ', '')}',
            );
        }
      }
    } catch (e) {
      if (mounted)
        setState(
          () =>
              _error = '选择附件失败：${e.toString().replaceFirst('Exception: ', '')}',
        );
    } finally {
      if (mounted)
        setState(() {
          _uploading = false;
          _uploadStatus = '';
        });
    }
  }

  void _removeAttachment(int aid) {
    if (_uploading || _submitting) return;
    setState(() => _attachments.removeWhere((e) => e.aid == aid));
    // Discuz 会把未绑定附件保留为当前账号的 unused attachment；这里不直接
    // 调用删除接口，避免误删用户此前的附件。最终发帖成功后会自动完成绑定。
  }

  Future<void> _submit() async {
    if (_submitting || _uploading || !_formKey.currentState!.validate()) return;
    final fid = _fid;
    if (fid == null || fid <= 0) {
      setState(() => _error = '请选择发帖版块');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ThreadPublishService.instance.createThread(
      fid: fid,
      subject: _title.text,
      message: _body.text,
      typeid: _typeid,
      attachments: List.unmodifiable(_attachments),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发帖成功')));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = result);
    }
  }

  Widget _attachmentCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_file_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '附件',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: _uploading || _submitting
                      ? null
                      : _pickAttachments,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '单个附件最大 10 MB，使用论坛原生上传接口。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (_uploading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 5),
              Text(
                _uploadStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._attachments.map(
                (attachment) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.insert_drive_file_outlined,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${(attachment.size / 1024 / 1024).toStringAsFixed(2)} MB · AID ${attachment.aid}',
                  ),
                  trailing: IconButton(
                    tooltip: '移除',
                    onPressed: _uploading || _submitting
                        ? null
                        : () => _removeAttachment(attachment.aid),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布帖子'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _submitting || _uploading || _loadingBoards
                  ? null
                  : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('发布'),
            ),
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
                  initialValue: _fid,
                  decoration: InputDecoration(
                    labelText: '发布到版块',
                    prefixIcon: const Icon(Icons.forum_outlined),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: .45,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: _boards
                      .map(
                        (b) => DropdownMenuItem<int>(
                          value: b.fid,
                          child: Text(b.name),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting || _uploading
                      ? null
                      : (v) {
                          setState(() => _fid = v);
                          if (v != null) _loadTypes(v);
                        },
                ),
                const SizedBox(height: 14),
              ],
              if (_types.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  initialValue: _typeid,
                  decoration: InputDecoration(
                    labelText: '主题分类',
                    prefixIcon: const Icon(Icons.label_outline),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: .45,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: _types
                      .map(
                        (t) => DropdownMenuItem<int>(
                          value: t.id,
                          child: Text(t.name),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting || _uploading
                      ? null
                      : (v) => setState(() => _typeid = v),
                ),
                const SizedBox(height: 14),
              ],
              if (_loadingTypes)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              TextFormField(
                controller: _title,
                enabled: !_submitting && !_uploading,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '标题',
                  hintText: '请输入帖子标题',
                  prefixIcon: const Icon(Icons.title_rounded),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(
                    alpha: .45,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入标题' : null,
              ),
              const SizedBox(height: 2),
              TextFormField(
                controller: _body,
                enabled: !_submitting && !_uploading,
                minLines: 12,
                maxLines: 20,
                maxLength: 10000,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: '正文',
                  hintText: '写下你想分享的内容……',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(
                    alpha: .45,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? (_attachments.isEmpty ? '请输入正文或添加附件' : null)
                    : null,
              ),
              const SizedBox(height: 12),
              _attachmentCard(context),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting || _uploading || _loadingBoards
                    ? null
                    : _submit,
                icon: const Icon(Icons.send_rounded),
                label: Text(_submitting ? '正在发布…' : '发布帖子'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '附件直接上传到源论坛，不经过第三方服务。上传成功后会在最终发帖请求中绑定到主题。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
