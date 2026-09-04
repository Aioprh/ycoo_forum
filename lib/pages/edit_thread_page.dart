import 'package:flutter/material.dart';

import '../services/thread_edit_service.dart';

/// 编辑自己已发布的主题。
///
/// 这里直接使用论坛网页端编辑表单的字段模型，避免客户端只修改正文。
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

  List<ThreadType> _types = const [];
  List<ThreadReadpermOption> _readpermOptions = const [];
  int? _typeId;
  int _price = 0;
  int _maxPrice = 0;
  int _readPerm = 0;
  bool _useSig = true;
  bool _allowNoticeAuthor = true;
  bool _hiddenReplies = false;
  bool _descViewDefault = false;
  bool _showAdvanced = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

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
      if (!mounted) return;

      setState(() {
        if (data != null) {
          if (data.subject.isNotEmpty) _title.text = data.subject;
          if (data.message.isNotEmpty) _body.text = data.message;
          _typeId = data.typeid;
          _typeId ??= 0; // 无分类的帖子显示为“无分类”
          _price = data.price;
          _maxPrice = data.maxPrice;
          _readPerm = data.readperm;
          _useSig = data.usesig;
          _allowNoticeAuthor = data.allownoticeauthor;
          _hiddenReplies = data.hiddenreplies;
          _descViewDefault = data.descviewdefault;
          // 直接用编辑表单自身的选项，保证与网页端下拉一致。
          _types = data.typeOptions;
          _readpermOptions = data.readpermOptions;
        }
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
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, text.length)
        : text.length;
    final selected = text.substring(start, end);
    final replacement = value.replaceAll('{text}', selected.isEmpty ? '文字' : selected);
    final next = text.replaceRange(start, end, replacement);
    _body.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: (start + replacement.length).clamp(0, next.length),
      ),
    );
    _bodyFocus.requestFocus();
  }

  Widget _toolbarButton(IconData icon, String tooltip, VoidCallback action) {
    return IconButton(
      tooltip: tooltip,
      onPressed: _submitting ? null : action,
      icon: Icon(icon, size: 20),
    );
  }

  Widget _editor(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '正文编辑器',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _toolbarButton(Icons.format_bold_rounded, '粗体', () => _insert('[b]{text}[/b]')),
                _toolbarButton(Icons.format_italic_rounded, '斜体', () => _insert('[i]{text}[/i]')),
                _toolbarButton(Icons.format_quote_rounded, '引用', () => _insert('[quote]{text}[/quote]')),
                _toolbarButton(Icons.code_rounded, '代码', () => _insert('[code]{text}[/code]')),
                _toolbarButton(Icons.link_rounded, '链接', () => _insert('[url]{text}[/url]')),
              ],
            ),
          ),
          const Divider(height: 1),
          TextField(
            controller: _body,
            focusNode: _bodyFocus,
            enabled: !_submitting,
            minLines: 10,
            maxLines: 22,
            maxLength: 10000,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
            decoration: const InputDecoration(
              hintText: '编辑正文……支持网页端常用 BBCode。',
              border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(16, 12, 16, 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _advancedCard(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.tune_rounded),
            title: const Text('高级设置', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('分类、售价、阅读权限、回帖可见性与排序、签名、通知等'),
            value: _showAdvanced,
            onChanged: _submitting ? null : (value) => setState(() => _showAdvanced = value),
          ),
          if (_showAdvanced)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  if (_types.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: _typeId,
                      decoration: const InputDecoration(
                        labelText: '主题分类',
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: 0,
                          child: Text('无分类'),
                        ),
                        ..._types
                            .map((type) => DropdownMenuItem<int>(
                                  value: type.id,
                                  child: Text(type.name),
                                ))
                            .toList(),
                      ],
                      onChanged: _submitting ? null : (value) => setState(() => _typeId = value),
                    ),
                  const SizedBox(height: 10),
                  // 售价/阅读权限用下拉，与发布帖子功能保持一致交互；选项边界取自网页编辑表单。
                  DropdownButtonFormField<int>(
                    value: _price,
                    decoration: InputDecoration(
                      labelText: '主题售价',
                      prefixIcon: const Icon(Icons.monetization_on_outlined),
                      helperText: _maxPrice > 0 ? '最高可设置 $_maxPrice 星币' : '售价为 0 表示免费',
                    ),
                    items: _priceOptions().map((value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text(value == 0 ? '免费' : '$value 星币'),
                        )).toList(),
                    onChanged: _submitting ? null : (value) => setState(() => _price = value ?? 0),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: _readPerm,
                    decoration: const InputDecoration(
                      labelText: '阅读权限',
                      prefixIcon: Icon(Icons.lock_outline),
                      helperText: '与网页端一致，按用户组设定',
                    ),
                    items: () {
                      final opts = _readpermOptions.map<DropdownMenuItem<int>>((o) => DropdownMenuItem<int>(
                            value: o.value,
                            child: Text(o.value == 0 ? '不限' : '${o.label}（${o.value}）'),
                          )).toList();
                      if (_readpermOptions.isEmpty) {
                        return const [DropdownMenuItem<int>(value: 0, child: Text('不限'))];
                      }
                      // 确保当前值(可能重复)一定在选项中，避免下拉找不到 value 而崩溃。
                      if (!_readpermOptions.any((o) => o.value == _readPerm)) {
                        opts.add(DropdownMenuItem<int>(
                          value: _readPerm,
                          child: Text('自定义（$_readPerm）'),
                        ));
                      }
                      return opts;
                    }(),
                    onChanged: _submitting ? null : (value) => setState(() => _readPerm = value ?? 0),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用签名'),
                    value: _useSig,
                    onChanged: _submitting ? null : (value) => setState(() => _useSig = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('接收回复通知'),
                    value: _allowNoticeAuthor,
                    onChanged: _submitting ? null : (value) => setState(() => _allowNoticeAuthor = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.visibility_off_outlined),
                    title: const Text('回帖仅作者可见'),
                    subtitle: const Text('其他用户的回复仅主题作者可见'),
                    value: _hiddenReplies,
                    onChanged: _submitting ? null : (value) => setState(() => _hiddenReplies = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.swap_vert_rounded),
                    title: const Text('回帖倒序排列'),
                    subtitle: const Text('帖子打开时优先显示最新回复'),
                    value: _descViewDefault,
                    onChanged: _submitting ? null : (value) => setState(() => _descViewDefault = value),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 可选的售价档位：0 到网页端上限，取发布页常用档位并保证包含当前值。
  List<int> _priceOptions() {
    final tiers = const [0, 1, 2, 3, 5, 10, 20, 30, 50, 100, 200, 255];
    final maxOpt = _maxPrice > 0 ? _maxPrice : (_price > 0 ? _price : 0);
    final opts = <int>{}
      ..addAll(tiers.where((v) => v <= maxOpt))
      ..add(maxOpt)
      ..add(_price);
    final list = opts.toList()..sort();
    return list.length > 40 ? list.take(40).toList() : list;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await ThreadEditService.instance.editThread(
      tid: widget.tid,
      fid: widget.fid,
      pid: widget.pid,
      subject: _title.text,
      message: _body.text,
      typeid: _typeId,
      price: _price,
      readperm: _readPerm,
      usesig: _useSig,
      allownoticeauthor: _allowNoticeAuthor,
      hiddenreplies: _hiddenReplies,
      descviewdefault: _descViewDefault,
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('编辑已保存')));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑主题'),
        actions: [
          TextButton.icon(
            onPressed: _loading || _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                TextField(
                  controller: _title,
                  enabled: !_submitting,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '请输入主题标题',
                    prefixIcon: Icon(Icons.title_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                _editor(scheme),
                const SizedBox(height: 12),
                _advancedCard(scheme),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(_submitting ? '正在保存…' : '保存修改'),
                ),
              ],
            ),
    );
  }
}
