import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../services/auth_service.dart';
import '../services/net_client.dart';
import 'credit_recharge_page.dart';

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
  dom.Element? _root;
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _selectValues = {};

  bool get _isRecharge => widget.path.contains('boan_buycredit:buycredit');
  String _abs(String href) => Uri.parse(
    widget.path.startsWith('http') ? widget.path : '$_base${widget.path}',
  ).resolve(href).toString();
  String _clean(String s) => s
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD□]'), '')
      .replaceAll(RegExp(r'[ \t\u00a0\u3000]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
  String _label(dom.Element e) {
    final s = _clean(e.text);
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  Future<void> _load() async {
    if (_isRecharge) return;
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final client = await NetClient.instance.client;
      await AuthService.instance.init();
      final r = await NetClient.retry(
        () => client.get(
          Uri.parse(
            widget.path.startsWith('http') ? widget.path : _abs(widget.path),
          ),
          headers: {
            'User-Agent': NetClient.ua,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Cache-Control': 'no-cache',
            if ((AuthService.instance.authCookie ?? '').isNotEmpty)
              'Cookie': AuthService.instance.authCookie!,
          },
        ),
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final doc = parser.parse(NetClient.decode(r.bodyBytes));
      for (final e in doc.querySelectorAll(
        'script,style,noscript,template,iframe',
      )) {
        e.remove();
      }
      dom.Element? best;
      var bestScore = -1;
      for (final s in [
        '#ct',
        '#wp',
        '#ctm',
        '.wp',
        '.mn',
        'main',
        'article',
        '.content',
        '.comiis_main',
        '.comiis_mainbox',
        '.comiis_space',
        '.comiis_spacecp',
        '.comiis_profile',
        '.comiis_setting',
        '.comiis_userbox',
        '.bm_c',
      ]) {
        for (final e in doc.querySelectorAll(s)) {
          final t = _clean(e.text);
          if (t.length < 10) continue;
          var score = t.length.clamp(0, 10000);
          if (e.querySelector('form,input,textarea,select') != null)
            score += 10000;
          if (score > bestScore) {
            best = e;
            bestScore = score;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _root = best ?? doc.body ?? doc.documentElement;
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  TextEditingController _controller(String key, String value) {
    return _fields.putIfAbsent(key, () => TextEditingController(text: value));
  }

  Widget _form(dom.Element form) {
    final widgets = <Widget>[];
    for (final e in form.querySelectorAll('input')) {
      final type = (e.attributes['type'] ?? 'text').toLowerCase();
      final name = e.attributes['name'] ?? e.attributes['id'];
      if (name == null ||
          type == 'hidden' ||
          type == 'submit' ||
          type == 'button' ||
          type == 'checkbox' ||
          type == 'radio')
        continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: _controller(name, e.attributes['value'] ?? ''),
            obscureText: type == 'password',
            keyboardType: type == 'number'
                ? TextInputType.number
                : TextInputType.text,
            decoration: InputDecoration(
              labelText:
                  e.attributes['placeholder'] ?? e.attributes['title'] ?? name,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      );
    }
    for (final e in form.querySelectorAll('textarea')) {
      final name = e.attributes['name'] ?? e.attributes['id'];
      if (name == null) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: _controller(name, _clean(e.text)),
            maxLines: 5,
            decoration: InputDecoration(
              labelText: name,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      );
    }
    for (final e in form.querySelectorAll('select')) {
      final name = e.attributes['name'] ?? e.attributes['id'];
      if (name == null) continue;
      final opts = e.querySelectorAll('option');
      final initial =
          e.attributes['value'] ??
          (opts.isEmpty
              ? null
              : opts.first.attributes['value'] ?? opts.first.text);
      _selectValues.putIfAbsent(name, () => initial ?? '');
      final current = _selectValues[name];
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String>(
            initialValue:
                opts.any((o) => (o.attributes['value'] ?? o.text) == current)
                ? current
                : null,
            decoration: InputDecoration(
              labelText: name,
              border: const OutlineInputBorder(),
            ),
            items: opts
                .map(
                  (o) => DropdownMenuItem<String>(
                    value: o.attributes['value'] ?? o.text,
                    child: Text(_clean(o.text)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _selectValues[name] = v;
            },
          ),
        ),
      );
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_label(form).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _label(form),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ...widgets,
            FilledButton.icon(
              onPressed: () => _submit(form),
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(dom.Element form) async {
    final data = <String, String>{};
    for (final e in form.querySelectorAll('input[type="hidden"]')) {
      final n = e.attributes['name'];
      if (n != null) data[n] = e.attributes['value'] ?? '';
    }
    for (final e in _fields.entries) {
      data[e.key] = e.value.text;
    }
    data.addAll(_selectValues);
    final formhash = data['formhash']?.trim() ?? '';
    if (formhash.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前页面没有有效 formhash，请刷新后重试')),
        );
      return;
    }
    try {
      final client = await NetClient.instance.client;
      await AuthService.instance.init();
      final r = await client
          .post(
            Uri.parse(_abs(form.attributes['action'] ?? widget.path)),
            headers: {
              'User-Agent': NetClient.ua,
              'Referer': _abs(widget.path),
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=UTF-8',
              if ((AuthService.instance.authCookie ?? '').isNotEmpty)
                'Cookie': AuthService.instance.authCookie!,
            },
            body: data,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final body = NetClient.decode(r.bodyBytes);
      if (_tokenFailed(body)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作令牌已失效，请刷新页面后重试')));
        return;
      }
      final ok = r.statusCode >= 200 && r.statusCode < 400;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '保存成功' : '保存失败：HTTP ${r.statusCode}')),
      );
      if (ok) await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  bool _tokenFailed(String body) =>
      body.contains('formhash') &&
      (body.contains('错误') ||
          body.contains('失效') ||
          body.contains('非法') ||
          body.contains('验证失败'));

  Widget _node(dom.Node n) {
    if (n is dom.Text) {
      final t = _clean(n.data ?? '');
      return t.isEmpty
          ? const SizedBox.shrink()
          : Text(t, style: const TextStyle(height: 1.55));
    }
    if (n is! dom.Element) return const SizedBox.shrink();
    final tag = n.localName ?? '';
    if (tag == 'form') return _form(n);
    if (tag == 'input' || tag == 'textarea' || tag == 'select')
      return const SizedBox.shrink();
    if (tag == 'img') {
      final src = n.attributes['src'] ?? n.attributes['data-src'] ?? '';
      return src.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _abs(src),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            );
    }
    if (tag == 'a') {
      final t = _label(n);
      final h = n.attributes['href'] ?? '';
      if (t.isEmpty || h.isEmpty) return const SizedBox.shrink();
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          t,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openLink(_abs(h), t),
      );
    }
    if (tag == 'li')
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Icon(Icons.circle, size: 6),
            ),
            const SizedBox(width: 8),
            Expanded(child: _children(n)),
          ],
        ),
      );
    if (tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4') {
      final t = _label(n);
      return t.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 7),
              child: Text(
                t,
                style: TextStyle(
                  fontSize: tag == 'h1'
                      ? 24
                      : tag == 'h2'
                      ? 21
                      : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
    }
    if (tag == 'button')
      return FilledButton(
        onPressed: () => _handleButton(n),
        child: Text(_label(n).isEmpty ? '操作' : _label(n)),
      );
    if (tag == 'p' || tag == 'blockquote' || tag == 'pre') {
      final t = _clean(n.text);
      return t.isEmpty
          ? const SizedBox.shrink()
          : Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  t,
                  style: TextStyle(
                    height: 1.6,
                    fontFamily: tag == 'pre' ? 'monospace' : null,
                  ),
                ),
              ),
            );
    }
    return _children(n);
  }

  Widget _children(dom.Element e) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: e.nodes.map(_node).toList(),
  );
  dom.Element? _closestForm(dom.Element element) {
    dom.Element? current = element;
    while (current != null) {
      if (current.localName == 'form') return current;
      current = current.parent;
    }
    return null;
  }

  Future<void> _handleButton(dom.Element e) async {
    final form = _closestForm(e);
    if (form != null) await _submit(form);
  }

  void _openLink(String url, String title) {
    if (url.startsWith(_base))
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NativeSitePage(path: url, title: title),
        ),
      );
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!_isRecharge) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRecharge) return const CreditRechargePage();
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null)
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    else
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            _root == null ? const Text('页面暂无可显示内容') : _children(_root!),
          ],
        ),
      );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: body,
    );
  }
}
