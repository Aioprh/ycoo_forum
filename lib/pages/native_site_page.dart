import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../services/auth_service.dart';
import '../services/net_client.dart';

/// 将 Discuz 会员/工具页面的内容转换成 Flutter 原生控件。
/// 不使用 WebView：标题、段落、列表、表格、图片、链接、表单和按钮均由 Flutter 渲染。
class NativeSitePage extends StatefulWidget {
  final String path;
  final String title;
  const NativeSitePage({super.key, required this.path, required this.title});
  @override
  State<NativeSitePage> createState() => _NativeSitePageState();
}

class _NativeSitePageState extends State<NativeSitePage> {
  static const _base = 'https://www.ycoo.net/';
  static const _globalSelectors = <String>[
    'script','style','noscript','template','iframe','header','nav','footer','aside',
    '.header','.footer','.sidebar','.sidebox','.nav','.navbar','.menu',
    '.comiis_head','.comiis_nav','.comiis_menu','.comiis_footer',
    '.comiis_left_Touch','.comiis_bottom','.comiis_header',
  ];
  bool _loading = true;
  String? _error;
  dom.Element? _root;

  String _abs(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    if (href.startsWith('//')) return 'https:$href';
    final current = Uri.parse(widget.path.startsWith('http') ? widget.path : '$_base${widget.path}');
    return current.resolve(href).toString();
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD□]'), '')
      .replaceAll(RegExp(r'[ \t\u00A0\u3000]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();

  bool _readable(String value) => RegExp(r'[A-Za-z0-9\u3400-\u9FFF]').hasMatch(value);

  dom.Element _prepare(dom.Document doc) {
    for (final node in doc.querySelectorAll(_globalSelectors.join(','))) node.remove();
    return doc.body ?? doc.documentElement!;
  }

  dom.Element _contentRoot(dom.Element body) {
    const selectors = <String>[
      '#ct','#wp','#ctm','.wp','.mn','main','article','.content',
      '.comiis_main','.comiis_mainbox','.comiis_mobbox','.comiis_width',
      '.comiis_space','.comiis_spacecp','.comiis_profile','.comiis_setting',
      '.comiis_userbox','.bm','.bm_c',
    ];
    dom.Element? best;
    var bestScore = -1;
    for (final selector in selectors) {
      for (final e in body.querySelectorAll(selector)) {
        final text = _clean(e.text);
        if (!_readable(text) || text.length < 15) continue;
        var score = 10000 - text.length.clamp(0, 9000);
        if (e.querySelector('form,input,textarea,select') != null) score += 5000;
        if (e.querySelector('table,article,p,li') != null) score += 500;
        if (score > bestScore) { best = e; bestScore = score; }
      }
    }
    return best ?? body;
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final client = await NetClient.instance.client;
      await AuthService.instance.init();
      final cookie = AuthService.instance.authCookie;
      final uri = Uri.parse(widget.path.startsWith('http') ? widget.path : _abs(widget.path));
      final response = await NetClient.retry(() => client.get(uri, headers: {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      })).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      final root = _contentRoot(_prepare(doc));
      if (!mounted) return;
      setState(() { _root = root; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  String _label(dom.Element e) {
    final own = _clean(e.text);
    if (own.length <= 90) return own;
    return own.substring(0, 90);
  }

  Widget _node(dom.Node node, {int depth = 0}) {
    if (node is dom.Text) {
      final text = _clean(node.data ?? '');
      return text.isEmpty ? const SizedBox.shrink() : Text(text, style: const TextStyle(height: 1.55));
    }
    if (node is! dom.Element) return const SizedBox.shrink();
    final tag = node.localName ?? '';
    if (tag == 'br') return const SizedBox(height: 8);
    if (tag == 'img') {
      final src = node.attributes['src'] ?? node.attributes['data-src'] ?? '';
      if (src.isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_abs(src), fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink())));
    }
    if (tag == 'a') {
      final text = _label(node);
      final href = node.attributes['href'] ?? '';
      if (text.isEmpty || href.isEmpty) return const SizedBox.shrink();
      return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4), title: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right), onTap: () => _openLink(_abs(href), text));
    }
    if (tag == 'input' || tag == 'textarea' || tag == 'select') return const SizedBox.shrink();
    if (tag == 'button') return FilledButton(onPressed: () {}, child: Text(_label(node).isEmpty ? '操作' : _label(node)));
    if (tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4') {
      final text = _label(node);
      if (text.isEmpty) return const SizedBox.shrink();
      final size = tag == 'h1' ? 24.0 : tag == 'h2' ? 21.0 : 18.0;
      return Padding(padding: const EdgeInsets.fromLTRB(0, 12, 0, 7), child: Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)));
    }
    if (tag == 'li') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 6)), const SizedBox(width: 8), Expanded(child: _children(node, depth: depth + 1))]));
    }
    if (tag == 'table') return _table(node);
    if (tag == 'form') return _form(node);
    if (tag == 'hr') return const Divider(height: 24);
    if (tag == 'p' || tag == 'blockquote' || tag == 'pre') {
      final text = _clean(node.text);
      if (text.isEmpty) return const SizedBox.shrink();
      return Card(color: tag == 'blockquote' ? Theme.of(context).colorScheme.surfaceContainerHighest : null, child: Padding(padding: const EdgeInsets.all(14), child: Text(text, style: TextStyle(height: 1.6, fontFamily: tag == 'pre' ? 'monospace' : null))));
    }
    return _children(node, depth: depth + 1);
  }

  Widget _children(dom.Element e, {int depth = 0}) {
    final widgets = <Widget>[];
    for (final child in e.nodes) {
      final w = _node(child, depth: depth);
      if (w is SizedBox && w.width == 0 && w.height == 0) continue;
      widgets.add(w);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _table(dom.Element table) {
    final rows = <TableRow>[];
    for (final tr in table.querySelectorAll('tr')) {
      final cells = tr.querySelectorAll('th,td').map((c) => Padding(padding: const EdgeInsets.all(8), child: Text(_clean(c.text), style: TextStyle(fontWeight: c.localName == 'th' ? FontWeight.w700 : FontWeight.normal)))).toList();
      if (cells.isNotEmpty) rows.add(TableRow(children: cells));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Table(defaultColumnWidth: const IntrinsicColumnWidth(), border: TableBorder.all(color: Colors.black12), children: rows)));
  }

  Widget _form(dom.Element form) {
    final title = _label(form);
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name != null && name.isNotEmpty) fields[name] = input.attributes['value'] ?? '';
    }
    return Card(child: ListTile(title: Text(title.isEmpty ? '表单操作' : title), subtitle: Text('${fields.length} 个字段'), trailing: const Icon(Icons.play_arrow), onTap: () => _submit(form, fields)));
  }

  Future<void> _submit(dom.Element form, Map<String, String> fields) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (c) => AlertDialog(title: Text(_label(form).isEmpty ? '提交操作' : _label(form)), content: TextField(controller: controller, maxLines: 4, decoration: const InputDecoration(labelText: '输入内容')), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('提交'))]));
    controller.dispose();
    if (value == null) return;
    final data = <String, String>{...fields};
    if (value.isNotEmpty) { data['message'] ??= value; data['srchtxt'] ??= value; }
    try {
      final client = await NetClient.instance.client;
      await AuthService.instance.init();
      final action = _abs(form.attributes['action'] ?? widget.path);
      final response = await client.post(Uri.parse(action), headers: {'User-Agent': NetClient.ua, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Referer': _abs(widget.path), if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!}, body: data).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.statusCode >= 200 && response.statusCode < 400 ? '操作成功，正在刷新' : '操作失败 HTTP ${response.statusCode}')));
      if (response.statusCode >= 200 && response.statusCode < 400) await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败：$e'))); }
  }

  void _openLink(String url, String title) {
    if (!url.startsWith(_base)) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => NativeSitePage(path: url, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) body = const Center(child: CircularProgressIndicator());
    else if (_error != null) body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 48), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton(onPressed: _load, child: const Text('重试'))])));
    else if (_root == null) body = const Center(child: Text('页面暂无可显示内容'));
    else body = RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 32), children: [_children(_root!)]));
    return Scaffold(appBar: AppBar(title: Text(widget.title), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]), body: body);
  }
}
