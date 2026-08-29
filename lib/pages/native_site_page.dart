import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../services/auth_service.dart';
import '../services/net_client.dart';

class NativeSitePage extends StatefulWidget {
  final String path;
  final String title;
  const NativeSitePage({super.key, required this.path, required this.title});
  @override
  State<NativeSitePage> createState() => _NativeSitePageState();
}

class _NativeSitePageState extends State<NativeSitePage> {
  static const _base = 'https://www.ycoo.net/';
  bool _loading = true;
  String? _error;
  String _bodyText = '';
  List<_LinkItem> _links = const [];
  List<_FormItem> _forms = const [];

  @override
  void initState() { super.initState(); _load(); }

  String _abs(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    if (href.startsWith('//')) return 'https:$href';
    if (href.startsWith('/')) return '$_base${href.substring(1)}';
    return '$_base$href';
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie;
      final uri = Uri.parse(widget.path.startsWith('http') ? widget.path : _abs(widget.path));
      final response = await client.get(uri, headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      for (final n in doc.querySelectorAll('script,style,noscript,template,iframe')) n.remove();
      final text = (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final links = <_LinkItem>[];
      final seen = <String>{};
      for (final a in doc.querySelectorAll('a[href]')) {
        final label = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final href = a.attributes['href'] ?? '';
        if (label.isEmpty || href.isEmpty || label.length > 80) continue;
        final url = _abs(href);
        if (!url.startsWith(_base) || !seen.add('$label|$url')) continue;
        if (const {'首页','登录','注册','退出登录'}.contains(label)) continue;
        links.add(_LinkItem(label, url));
        if (links.length >= 60) break;
      }
      final forms = <_FormItem>[];
      for (final form in doc.querySelectorAll('form')) {
        final fields = <String, String>{};
        for (final input in form.querySelectorAll('input')) {
          final name = input.attributes['name'];
          if (name == null || name.isEmpty) continue;
          fields[name] = input.attributes['value'] ?? '';
        }
        final label = form.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (label.isEmpty && fields.isEmpty) continue;
        forms.add(_FormItem(label.length > 180 ? label.substring(0, 180) : label, _abs(form.attributes['action'] ?? widget.path), fields));
        if (forms.length >= 8) break;
      }
      if (!mounted) return;
      setState(() { _bodyText = text; _links = links; _forms = forms; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _submit(_FormItem form) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(form.label.isEmpty ? '提交操作' : form.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '输入内容（可选）')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('提交'))],
    ));
    controller.dispose();
    if (value == null) return;
    try {
      final client = await NetClient.instance.client;
      final cookie = AuthService.instance.authCookie;
      final fields = <String, String>{...form.fields};
      if (value.isNotEmpty) { fields['message'] ??= value; fields['srchtxt'] ??= value; }
      final response = await client.post(Uri.parse(form.action), headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Content-Type': 'application/x-www-form-urlencoded',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      }, body: fields).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 400) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作已提交')));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? _errorView() : RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        if (_bodyText.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_bodyText, style: const TextStyle(height: 1.6)))),
        if (_forms.isNotEmpty) ...[const SizedBox(height: 12), const Text('可用操作', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 8), for (final form in _forms) Card(child: ListTile(title: Text(form.label.isEmpty ? '表单操作' : form.label), trailing: const Icon(Icons.play_arrow), onTap: () => _submit(form)))],
        if (_links.isNotEmpty) ...[const SizedBox(height: 12), const Text('页面入口', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 8), for (final link in _links) Card(child: ListTile(title: Text(link.label), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NativeSitePage(path: link.url, title: link.label))))],
      ]),
    ),
  );

  Widget _errorView() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 48), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton(onPressed: _load, child: const Text('重试'))]));
}

class _LinkItem { final String label, url; const _LinkItem(this.label, this.url); }
class _FormItem { final String label, action; final Map<String, String> fields; const _FormItem(this.label, this.action, this.fields); }
