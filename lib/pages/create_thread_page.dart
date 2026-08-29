import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/site_fallback_service.dart';
import '../services/thread_publish_service.dart';

/// 原生发帖页：选择版块、填写标题和正文后直接提交到论坛。
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
  int? _fid;
  bool _loadingBoards = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() { super.initState(); _loadBoards(); }

  @override
  void dispose() { _title.dispose(); _body.dispose(); super.dispose(); }

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
        // Discuz/Comiis 改版后旧 CSS 选择器可能失效，使用稳定 fid 链接解析。
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
    } catch (_) {
      if (mounted) setState(() { _loadingBoards = false; _error = '版块加载失败，请稍后重试'; });
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final fid = _fid;
    if (fid == null || fid <= 0) { setState(() => _error = '请选择发帖版块'); return; }
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await ThreadPublishService.instance.createThread(fid: fid, subject: _title.text, message: _body.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('发帖成功')));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = result);
    }
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
              onPressed: _submitting || _loadingBoards ? null : _submit,
              child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('发布'),
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
                  value: _fid,
                  decoration: InputDecoration(
                    labelText: '发布到版块', prefixIcon: const Icon(Icons.forum_outlined), filled: true,
                    fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  items: _boards.map((b) => DropdownMenuItem<int>(value: b.fid, child: Text(b.name))).toList(),
                  onChanged: _submitting ? null : (v) => setState(() => _fid = v),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _title, enabled: !_submitting, maxLength: 80, textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '标题', hintText: '请输入帖子标题', prefixIcon: const Icon(Icons.title_rounded), filled: true,
                  fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? '请输入标题' : null,
              ),
              const SizedBox(height: 2),
              TextFormField(
                controller: _body, enabled: !_submitting, minLines: 12, maxLines: 20, maxLength: 10000,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: '正文', hintText: '写下你想分享的内容……', alignLabelWithHint: true, filled: true,
                  fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? '请输入正文' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(14)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, color: scheme.onErrorContainer), const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                  ]),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting || _loadingBoards ? null : _submit,
                icon: const Icon(Icons.send_rounded), label: Text(_submitting ? '正在发布…' : '发布帖子'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 10),
              Text('发帖使用当前登录会话提交到源论坛，正文不会发送到第三方服务。', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
