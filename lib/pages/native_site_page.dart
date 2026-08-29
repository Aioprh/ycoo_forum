import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../services/auth_service.dart';
import '../services/net_client.dart';

/// 原生站点页面：只显示正文区域，并清理 Discuz 图标字体产生的方框字符。
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
  ];

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
    final current = Uri.parse(widget.path.startsWith('http') ? widget.path : '$_base${widget.path}');
    return current.resolve(href).toString();
  }

  String _cleanText(String value) => value
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD]'), '')
      .replaceAll('□', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _hasReadableText(String value) => RegExp(r'[A-Za-z0-9\u3400-\u9FFF]').hasMatch(value);

  dom.Element _prepareDocument(dom.Document doc) {
    for (final node in doc.querySelectorAll(_globalSelectors.join(','))) { node.remove(); }
    return doc.body ?? doc.documentElement!;
  }

  dom.Element _findContentRoot(dom.Element body) {
    final candidates = <dom.Element>[body];
    const selectors = <String>[
      '#wp','#ct','.wp','.mn','.comiis_main','.comiis_mainbox','.comiis_mobbox',
      '.comiis_width','.comiis_forum_box','.comiis_postbox','main','article','.content',
    ];
    for (final selector in selectors) { candidates.addAll(body.querySelectorAll(selector)); }
    dom.Element best = body;
    var bestScore = 0;
    for (final candidate in candidates) {
      final text = _cleanText(candidate.text);
      if (!_hasReadableText(text)) continue;
      var score = text.length;
      if (candidate.querySelector('form') != null) score += 500;
      if (candidate.querySelector('input,textarea,select') != null) score += 300;
      if (candidate.querySelector('p,article,table') != null) score += 100;
      if (score > bestScore) { best = candidate; bestScore = score; }
    }
    return best;
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
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      })).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final doc = parser.parse(NetClient.decode(response.bodyBytes));
      final contentRoot = _findContentRoot(_prepareDocument(doc));
      final text = _cleanText(contentRoot.text);

      final links = <_LinkItem>[];
      final seen = <String>{};
      for (final anchor in contentRoot.querySelectorAll('a[href]')) {
        final label = _cleanText(anchor.text);
        final href = anchor.attributes['href'] ?? '';
        if (label.isEmpty || href.isEmpty || label.length > 80 || !_hasReadableText(label)) continue;
        final url = _abs(href);
        if (!url.startsWith(_base) || const {'首页','登录','注册','退出登录','退出','返回','更多'}.contains(label)) continue;
        if (!seen.add('$label|$url')) continue;
        links.add(_LinkItem(label, url));
        if (links.length >= 60) break;
      }

      final forms = <_FormItem>[];
      for (final form in contentRoot.querySelectorAll('form')) {
        final fields = <String, String>{};
        for (final input in form.querySelectorAll('input')) {
          final name = input.attributes['name'];
          if (name == null || name.isEmpty) continue;
          fields[name] = input.attributes['value'] ?? '';
        }
        final label = _cleanText(form.text);
        if (label.isEmpty && fields.isEmpty) continue;
        forms.add(_FormItem(label.length > 240 ? label.substring(0, 240) : label,
            _abs(form.attributes['action'] ?? widget.path), fields));
        if (forms.length >= 12) break;
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
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(form.label.isEmpty ? '提交操作' : form.label, maxLines: 3, overflow: TextOverflow.ellipsis),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '输入内容（可选）')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('提交')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      final client = await NetClient.instance.client;
      await AuthService.instance.init();
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
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _errorView();
    } else {
      final children = <Widget>[];
      if (_bodyText.isNotEmpty) {
        children.add(Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_bodyText, style: const TextStyle(height: 1.6)))));
      }
      if (_forms.isNotEmpty) {
        children.addAll(const [SizedBox(height: 12), Text('可用操作', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), SizedBox(height: 8)]);
        for (final form in _forms) {
          children.add(Card(child: ListTile(title: Text(form.label.isEmpty ? '表单操作' : form.label), trailing: const Icon(Icons.play_arrow), onTap: () => _submit(form))));
        }
      }
      if (_links.isNotEmpty) {
        children.addAll(const [SizedBox(height: 12), Text('页面入口', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), SizedBox(height: 8)]);
        for (final link in _links) {
          children.add(Card(child: ListTile(title: Text(link.label), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NativeSitePage(path: link.url, title: link.label)))));
        }
      }
      if (children.isEmpty) children.add(const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('页面暂无可显示内容'))));
      body = RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: children));
    }
    return Scaffold(appBar: AppBar(title: Text(widget.title), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]), body: body);
  }

  Widget _errorView() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off, size: 48), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center),
    const SizedBox(height: 16), FilledButton(onPressed: _load, child: const Text('重试')),
  ]));
}

class _LinkItem { final String label; final String url; const _LinkItem(this.label, this.url); }
class _FormItem { final String label; final String action; final Map<String, String> fields; const _FormItem(this.label, this.action, this.fields); }
