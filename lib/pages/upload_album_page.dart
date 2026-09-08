import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/space_write_service.dart';
import '../utils/forum_text.dart';
import 'login_page.dart';

/// 发相册: 选择/新建相册并上传图片。
class UploadAlbumPage extends StatefulWidget {
  const UploadAlbumPage({super.key});

  @override
  State<UploadAlbumPage> createState() => _UploadAlbumPageState();
}

class _UploadAlbumPageState extends State<UploadAlbumPage> {
  List<AlbumInfo> _albums = const [];
  bool _loadingAlbums = true;
  bool _createNew = false;
  final _newName = TextEditingController();
  final _newDes = TextEditingController();
  int? _albumId;
  final List<PlatformFile> _files = [];
  bool _busy = false;
  String? _error;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _newName.dispose();
    _newDes.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) {
      if (!mounted) return;
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (ok != true) { if (mounted) Navigator.of(context).pop(); return; }
    }
    await _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    if (!mounted) return;
    setState(() { _loadingAlbums = true; _error = null; });
    final albums = await SpaceWriteService.instance.fetchMyAlbums();
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _loadingAlbums = false;
      if (_albumId == null && albums.isNotEmpty) _albumId = albums.first.albumId;
    });
  }

  Future<void> _pickImages() async {
    if (_busy) return;
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image);
    if (picked == null || picked.files.isEmpty) return;
    setState(() {
      _files.addAll(picked.files.where((f) => f.path != null && !_files.any((e) => e.path == f.path)));
      if (_files.isNotEmpty) _error = null;
    });
  }

  void _removeFile(PlatformFile f) => setState(() => _files.remove(f));

  Future<int?> _ensureTargetAlbum() async {
    if (!_createNew) {
      return _albumId;
    }
    final name = _newName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入新相册名称');
      return null;
    }
    final create = await SpaceWriteService.instance.createAlbum(name: name, description: _newDes.text.trim());
    if (create != null) {
      setState(() => _error = forumText(create));
      return null;
    }
    final refreshed = await SpaceWriteService.instance.fetchMyAlbums();
    for (final a in refreshed) {
      if (a.name == name) return a.albumId;
    }
    // 创建后列表未刷新出新相册: 让用户重试选择。
    setState(() => _error = '相册已创建，请重新进入后再上传');
    return null;
  }

  Future<void> _publish() async {
    if (_busy) return;
    if (_files.isEmpty) { setState(() => _error = '请先选择要上传的图片'); return; }
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; _status = '准备上传…'; });
    final albumId = await _ensureTargetAlbum();
    if (albumId == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    for (var i = 0; i < _files.length; i++) {
      if (!mounted) return;
      final file = _files[i];
      setState(() => _status = '正在上传 ${i + 1}/${_files.length}：${file.name}');
      final result = await SpaceWriteService.instance.uploadAlbumImage(file: file, albumId: albumId);
      if (!mounted) return;
      if (result != null) {
        setState(() { _busy = false; _status = ''; _error = '${file.name}：${forumText(result)}'; });
        return;
      }
    }
    if (!mounted) return;
    _files.clear();
    setState(() { _busy = false; _status = ''; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片上传成功'), behavior: SnackBarBehavior.floating));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('发相册', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]), borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.surface.withOpacity(.72), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.photo_library_rounded, color: scheme.primary)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('分享你的相册', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('上传图片到个人空间的相册', style: TextStyle(fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            Text('选择相册', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
            const SizedBox(height: 8),
            if (_loadingAlbums)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()))
            else ...[
              _createNew ? _newAlbumCard(scheme) : _albumPicker(scheme),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('新建相册'),
                subtitle: Text(_createNew ? '上传到新创建的相册' : '上传到已有相册', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                value: _createNew,
                onChanged: _busy ? null : (v) => setState(() => _createNew = v),
              ),
            ],
            const SizedBox(height: 6),
            Text('选择图片', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
            const SizedBox(height: 8),
            _files.isEmpty
                ? InkWell(
                    onTap: _busy ? null : _pickImages,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant)),
                      child: Column(children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 30, color: scheme.primary),
                        const SizedBox(height: 8),
                        Text('添加图片', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text('从图库选择图片, 可多选 · 单张最大 10 MB', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant)),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in _files)
                        Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(f.path!), width: 90, height: 90, fit: BoxFit.cover, gaplessPlayback: false),
                          ),
                          Positioned(right: 2, top: 2, child: Material(color: Colors.black.withOpacity(.5), shape: const CircleBorder(), child: InkWell(onTap: _busy ? null : () => _removeFile(f), child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close_rounded, color: Colors.white, size: 15))))),
                        ]),
                      InkWell(
                        onTap: _busy ? null : _pickImages,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(width: 90, height: 90, decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(.5), borderRadius: BorderRadius.circular(10), border: Border.all(color: scheme.outlineVariant)), child: Icon(Icons.add_rounded, color: scheme.outline)),
                      ),
                    ]),
                  ),
                ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 6),
              Text(_status, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer, size: 20), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))]),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy || _files.isEmpty ? null : _publish,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded),
              label: Text(_busy ? '上传中' : '上传到相册'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _albumPicker(ColorScheme scheme) {
    if (_albums.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(.5), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text('还没有相册，请打开「新建相册」创建一个', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
        ]),
      );
    }
    return DropdownButtonFormField<int>(
      value: _albumId,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.photo_album_outlined),
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.6))),
      ),
      items: _albums.map((a) => DropdownMenuItem(value: a.albumId, child: Text(a.name))).toList(),
      onChanged: _busy ? null : (v) => setState(() => _albumId = v),
    );
  }

  Widget _newAlbumCard(ColorScheme scheme) {
    return Column(children: [
      TextField(
        controller: _newName,
        enabled: !_busy,
        decoration: InputDecoration(
          labelText: '相册名称',
          hintText: '例如：生活随拍',
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _newDes,
        enabled: !_busy,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: '相册简介(可选)',
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
        ),
      ),
    ]);
  }
}