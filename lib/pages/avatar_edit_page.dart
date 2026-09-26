import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/avatar_service.dart';

/// 更换头像: 从相册选图 -> 本地预览 -> 提交到论坛头像接口。
class AvatarEditPage extends StatefulWidget {
  const AvatarEditPage({super.key});

  @override
  State<AvatarEditPage> createState() => _AvatarEditPageState();
}

class _AvatarEditPageState extends State<AvatarEditPage> {
  Uint8List? _picked;
  bool _saving = false;

  String? get _currentAvatar {
    final url = AuthService.instance.avatarUrl;
    if (url == null || url.isEmpty) return null;
    return '$url${url.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _pick() async {
    if (_saving) return;
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      var bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        _toast('没有读取到图片，请重新选择');
        return;
      }
      if (!mounted) return;
      setState(() => _picked = bytes);
    } catch (_) {
      _toast('无法读取所选图片，请换一张试试');
    }
  }

  Future<void> _save() async {
    final bytes = _picked;
    if (bytes == null || _saving) return;
    setState(() => _saving = true);
    final error = await AvatarService.instance.upload(bytes);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _toast(error);
      return;
    }
    await AuthService.instance.refreshProfile();
    if (!mounted) return;
    _toast('头像已更换');
    Navigator.of(context).pop(true);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final picked = _picked;
    final current = _currentAvatar;

    ImageProvider? background;
    if (picked != null) {
      background = MemoryImage(picked);
    } else if (current != null) {
      background = NetworkImage(current);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('更换头像')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: CircleAvatar(
                radius: 68,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: background,
                child: background == null
                    ? Icon(Icons.person, size: 68, color: scheme.onPrimaryContainer)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              picked == null ? '当前头像' : '新头像预览',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _pick,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('从相册选择图片'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            if (picked != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_saving ? '正在上传…' : '保存并更换头像'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _saving ? null : () => setState(() => _picked = null),
                child: const Text('取消选择'),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              '图片会自动居中裁成正方形，并同步到论坛个人主页。\n若提示登录已失效，请重新登录后再试。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}