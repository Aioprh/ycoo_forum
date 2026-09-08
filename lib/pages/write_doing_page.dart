import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/space_write_service.dart';
import '../utils/forum_text.dart';
import '../widgets/native_icon_style.dart';
import 'login_page.dart';

/// 记心情: 发表一条 Discuz 空间记录(doing)。
class WriteDoingPage extends StatefulWidget {
  const WriteDoingPage({super.key});

  @override
  State<WriteDoingPage> createState() => _WriteDoingPageState();
}

class _WriteDoingPageState extends State<WriteDoingPage> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ensureLogin();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensureLogin() async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn && mounted) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (ok == true && mounted) setState(() {});
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入记录内容');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final result = await SpaceWriteService.instance.postDoing(message: text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) {
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('心情发布成功'), behavior: SnackBarBehavior.floating));
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
      appBar: AppBar(title: const Text('记心情', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]), borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.surface.withOpacity(.72), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.self_improvement_rounded, color: scheme.primary)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('此刻的心情', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('一句话记录今天的想法或状态', style: TextStyle(fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              enabled: !_submitting,
              maxLines: 6,
              maxLength: 200,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '今天有什么想说的？\n\n例如：完成了第一阶段，真开心！',
                filled: true,
                fillColor: scheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.6))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('记录会同步到你的个人空间', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting ? '发布中' : '发布心情'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 18)),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer, size: 20), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))]),
            ],
          ],
        ),
      ),
    );
  }
}