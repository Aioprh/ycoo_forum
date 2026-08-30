import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;

import '../services/auth_service.dart';
import '../services/net_client.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  static const _base = 'https://www.ycoo.net/';
  final _nickname = TextEditingController();
  final _signature = TextEditingController();
  final _location = TextEditingController();
  final _bio = TextEditingController();
  final _birthday = TextEditingController();
  final Map<String, String> _hidden = {};
  String? _gender;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _formAction = 'home.php?mod=spacecp&ac=profile';

  Uri _uri(String path) => Uri.parse(path.startsWith('http') ? path : '$_base$path');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    _location.dispose();
    _bio.dispose();
    _birthday.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.init();
      if (!AuthService.instance.isLoggedIn) throw Exception('请先登录论坛');
      final client = await NetClient.instance.client;
      final r = await NetClient.retry(() => client.get(
        _uri('home.php?mod=spacecp&ac=profile&mobile=2'),
        headers: _headers(),
      )).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('请求失败 HTTP ${r.statusCode}');
      final doc = parser.parse(NetClient.decode(r.bodyBytes));
      final form = _findForm(doc);
      if (form == null) throw Exception('没有找到资料编辑表单');
      _hidden.clear();
      for (final e in form.querySelectorAll('input[type="hidden"]')) {
        final n = e.attributes['name'];
        if (n != null && n.isNotEmpty) _hidden[n] = e.attributes['value'] ?? '';
      }
      _formAction = form.attributes['action']?.trim().isNotEmpty == true
          ? form.attributes['action']!.trim()
          : 'home.php?mod=spacecp&ac=profile';
      _setFromInput(form, 'nickname', _nickname);
      _setFromInput(form, 'displayname', _nickname, onlyIfEmpty: true);
      _setFromInput(form, 'signature', _signature);
      _setFromInput(form, 'location', _location);
      _setFromInput(form, 'residecity', _location, onlyIfEmpty: true);
      _setFromTextarea(form, 'bio', _bio);
      _setFromTextarea(form, 'aboutme', _bio, onlyIfEmpty: true);
      _setFromInput(form, 'birthyear', _birthday);
      _setFromInput(form, 'birthday', _birthday, onlyIfEmpty: true);
      final gender = _selected(form, ['gender']);
      if (gender != null && mounted) _gender = gender;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Map<String, String> _headers() => {
    'User-Agent': NetClient.ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache',
    if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!,
  };

  dom.Element? _findForm(dom.Document doc) {
    for (final form in doc.querySelectorAll('form')) {
      final text = form.text.toLowerCase();
      final action = form.attributes['action'] ?? '';
      if (action.contains('spacecp') || text.contains('个人资料') || text.contains('资料')) return form;
    }
    return doc.querySelector('form');
  }

  void _setFromInput(dom.Element form, String name, TextEditingController c, {bool onlyIfEmpty = false}) {
    if (onlyIfEmpty && c.text.isNotEmpty) return;
    final e = form.querySelector('input[name="$name"]');
    if (e != null) c.text = e.attributes['value'] ?? '';
  }

  void _setFromTextarea(dom.Element form, String name, TextEditingController c, {bool onlyIfEmpty = false}) {
    if (onlyIfEmpty && c.text.isNotEmpty) return;
    final e = form.querySelector('textarea[name="$name"]');
    if (e != null) c.text = e.text.trim();
  }

  String? _selected(dom.Element form, List<String> names) {
    for (final name in names) {
      final e = form.querySelector('select[name="$name"]');
      if (e != null) {
        final selected = e.querySelector('option[selected]');
        if (selected != null) return selected.attributes['value'] ?? selected.text.trim();
        final first = e.querySelector('option');
        if (first != null) return first.attributes['value'] ?? first.text.trim();
      }
      final radio = form.querySelector('input[name="$name"][checked]');
      if (radio != null) return radio.attributes['value'];
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AuthService.instance.init();
      final client = await NetClient.instance.client;
      final data = <String, String>{..._hidden};
      if (_nickname.text.isNotEmpty) {
        data['nickname'] = _nickname.text.trim();
        data['displayname'] = _nickname.text.trim();
      }
      data['signature'] = _signature.text.trim();
      data['location'] = _location.text.trim();
      data['residecity'] = _location.text.trim();
      data['bio'] = _bio.text.trim();
      data['aboutme'] = _bio.text.trim();
      if (_birthday.text.trim().isNotEmpty) data['birthday'] = _birthday.text.trim();
      if (_gender != null) data['gender'] = _gender!;
      data['profilesubmit'] = 'true';
      final action = _uri(_formAction);
      final r = await client.post(action, headers: {
        ..._headers(),
        'Referer': _uri('home.php?mod=spacecp&ac=profile&mobile=2').toString(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      }, body: data).timeout(const Duration(seconds: 20));
      final body = NetClient.decode(r.bodyBytes);
      if (r.statusCode < 200 || r.statusCode >= 400) throw Exception('保存失败 HTTP ${r.statusCode}');
      if (_looksLikeLogin(body)) throw Exception('登录态已失效，请重新登录');
      if (_looksLikeError(body)) throw Exception(_extractMessage(body) ?? '论坛拒绝了这次修改');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('资料保存成功'), behavior: SnackBarBehavior.floating));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _looksLikeLogin(String s) => s.contains('登录') && (s.contains('用户名') || s.contains('密码'));
  bool _looksLikeError(String s) => s.contains('错误') || s.contains('失败') || s.contains('formhash') || s.contains('权限');
  String? _extractMessage(String html) {
    final doc = parser.parse(html);
    for (final selector in ['.alert_error', '.alert_info', '.xi1', '.xi2', '.showMsg', '.tip']) {
      final e = doc.querySelector(selector);
      if (e != null && e.text.trim().isNotEmpty) return e.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    return null;
  }

  InputDecoration _dec(String label, IconData icon, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    filled: true,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('资料设置'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 14), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('重试'))])))
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
                        CircleAvatar(radius: 30, backgroundColor: scheme.primaryContainer, child: const Icon(Icons.person, size: 30)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(AuthService.instance.username ?? '当前账号', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('修改后会同步到论坛个人主页', style: TextStyle(color: scheme.onSurfaceVariant)),
                        ])),
                      ]))),
                      const SizedBox(height: 14),
                      const Text('基本资料', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      TextField(controller: _nickname, decoration: _dec('昵称', Icons.badge_outlined, hint: '论坛显示名称')),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: const ['0','1','2'].contains(_gender) ? _gender : null,
                        decoration: _dec('性别', Icons.wc_outlined),
                        items: const [DropdownMenuItem(value: '0', child: Text('保密')), DropdownMenuItem(value: '1', child: Text('男')), DropdownMenuItem(value: '2', child: Text('女'))],
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: _birthday, decoration: _dec('生日', Icons.cake_outlined, hint: '例如 2000-01-01')),
                      const SizedBox(height: 12),
                      TextField(controller: _location, decoration: _dec('所在地', Icons.location_on_outlined)),
                      const SizedBox(height: 20),
                      const Text('个人信息', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      TextField(controller: _signature, maxLines: 3, maxLength: 120, decoration: _dec('个人签名', Icons.edit_note_outlined, hint: '介绍一下自己')),
                      const SizedBox(height: 12),
                      TextField(controller: _bio, maxLines: 6, maxLength: 500, decoration: _dec('个人介绍', Icons.notes_outlined, hint: '可以填写更详细的个人介绍')),
                      const SizedBox(height: 22),
                      FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? '正在保存…' : '保存资料'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
                      const SizedBox(height: 8),
                      Text('保存时会使用当前登录会话和论坛 formhash。', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
    );
  }
}
