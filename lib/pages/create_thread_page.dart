import 'dart:async';

import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/post_draft_service.dart';
import '../services/site_fallback_service.dart';
import '../services/thread_publish_service.dart';

/// 原生发帖页面。
/// 保留版块、主题分类、标题、正文、草稿、售价、悬赏、阅读权限与签名等核心能力。
class CreateThreadPage extends StatefulWidget {
  const CreateThreadPage({super.key});

  @override
  State<CreateThreadPage> createState() => _CreateThreadPageState();
}

class _CreateThreadPageState extends State<CreateThreadPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
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
  bool _advanced = false;
  bool _loadingBoards = true;
  bool _loadingTypes = false;
  bool _submitting = false;
  bool _restoringDraft = true;
  bool _dirty = false;
  String? _error;

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
    super.dispose();
  }

  void _onTextChanged() {
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
      scheduledAt: null,
    ));
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

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate() || _fid == null) return;
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
      reward: _reward,
    );
    if (!mounted) return;
    if (result == null) {
      await PostDraftService.instance.clear();
      _dirty = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('帖子发布成功')));
      Navigator.of(context).pop(true);
    } else {
      setState(() { _submitting = false; _error = result; });
    }
  }

  Future<bool> _confirmLeave() async {
    if (_submitting || !_dirty || (_title.text.trim().isEmpty && _body.text.trim().isEmpty)) return true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('帖子尚未发布', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('可以保存草稿后离开。')),
          ListTile(leading: const Icon(Icons.save_outlined), title: const Text('保存草稿并离开'), onTap: () => Navigator.pop(context, 'save')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('直接离开'), onTap: () => Navigator.pop(context, 'leave')),
          ListTile(leading: const Icon(Icons.close), title: const Text('继续编辑'), onTap: () => Navigator.pop(context, 'cancel')),
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

  InputDecoration _decoration(String label, String hint, IconData icon, ColorScheme scheme) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary)),
      );

  Widget _advanced(ColorScheme scheme) => Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          leading: const Icon(Icons.tune_rounded),
          title: const Text('高级设置'),
          subtitle: const Text('售价、悬赏、阅读权限、通知与动态'),
          initiallyExpanded: _advanced,
          onExpansionChanged: (value) => setState(() { _advanced = value; _dirty = true; }),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            DropdownButtonFormField<int>(
              value: _price,
              decoration: const InputDecoration(labelText: '主题售价', prefixIcon: Icon(Icons.monetization_on_outlined)),
              items: const [0, 1, 2, 3, 5, 10, 20].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '免费' : '$v 星币'))).toList(),
              onChanged: _reward > 0 ? null : (v) => setState(() { _price = v ?? 0; _dirty = true; }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _reward,
              decoration: InputDecoration(labelText: '悬赏奖励', helperText: _reward > 0 ? '将奖励给最佳回复' : null, prefixIcon: const Icon(Icons.card_giftcard_rounded)),
              items: const [0, 2, 3, 5, 8, 10, 20, 30, 50].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不悬赏' : '悬赏 $v 星币'))).toList(),
              onChanged: _price > 0 ? null : (v) => setState(() { _reward = v ?? 0; _dirty = true; }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _readperm,
              decoration: const InputDecoration(labelText: '阅读权限', prefixIcon: Icon(Icons.lock_outline_rounded)),
              items: const [0, 10, 20, 30, 50, 80, 100, 255].map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '不限' : '$v 级'))).toList(),
              onChanged: (v) => setState(() { _readperm = v ?? 0; _dirty = true; }),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('使用个人签名'), value: _usesig, onChanged: (v) => setState(() { _usesig = v; _dirty = true; })),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('接收回复通知'), value: _allownoticeauthor, onChanged: (v) => setState(() { _allownoticeauthor = v; _dirty = true; })),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('回帖仅作者可见'), value: _hiddenreplies, onChanged: (v) => setState(() { _hiddenreplies = v; _dirty = true; })),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('回帖倒序排列'), value: _descviewdefault, onChanged: (v) => setState(() { _descviewdefault = v; _dirty = true; })),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('发送动态'), value: _addfeed, onChanged: (v) => setState(() { _addfeed = v; _dirty = true; })),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('发布帖子', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(onPressed: _submitting ? null : () => setState(() { _advanced = !_advanced; _dirty = true; }), icon: Icon(_advanced ? Icons.edit_note_rounded : Icons.tune_rounded)),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: FilledButton.icon(
              onPressed: _submitting || _loadingBoards ? null : _submit,
              icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
              label: Text(_submitting ? '发布中' : '发布帖子'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loadingBoards) const LinearProgressIndicator(minHeight: 2),
                if (_boards.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    value: _fid,
                    decoration: _decoration('发布到版块', '选择版块', Icons.forum_outlined, scheme),
                    items: _boards.map((b) => DropdownMenuItem(value: b.fid, child: Text(b.name))).toList(),
                    onChanged: _submitting ? null : (v) { setState(() { _fid = v; _dirty = true; }); if (v != null) _loadTypes(v); },
                  ),
                  const SizedBox(height: 10),
                ],
                if (_types.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    value: _typeid,
                    decoration: _decoration('主题分类', '选择分类', Icons.label_outline_rounded, scheme),
                    items: _types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                    onChanged: _submitting ? null : (v) => setState(() { _typeid = v; _dirty = true; }),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_loadingTypes) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 2)),
                TextFormField(
                  controller: _title,
                  enabled: !_submitting,
                  maxLength: 100,
                  decoration: _decoration('标题', '一句话概括你的帖子', Icons.title_rounded, scheme),
                  validator: (value) => value == null || value.trim().isEmpty ? '请输入标题' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _body,
                  enabled: !_submitting,
                  minLines: 10,
                  maxLines: 20,
                  maxLength: 10000,
                  decoration: _decoration('正文', '写下你的想法、经验或资源分享……', Icons.edit_note_rounded, scheme),
                  validator: (value) => value == null || value.trim().isEmpty ? '请输入正文' : null,
                ),
                const SizedBox(height: 12),
                _advanced(scheme),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)),
                    child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                ],
                const SizedBox(height: 12),
                Center(child: Text(_dirty ? '草稿已自动保存' : '填写完成后即可发布', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
