import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 一个可插入正文的 Discuz 表情。
class ForumSmiley {
  /// 插入正文的 BBCode, 形如 `:lol:`。
  final String code;
  /// 表情图片地址(绝对 URL), 用于选择器预览。
  final String imageUrl;
  /// 显示名/提示。
  final String label;
  const ForumSmiley({required this.code, required this.imageUrl, required this.label});
}

/// 从发帖页拉取 Discuz 表情列表, 用于原生发帖编辑器的表情选择器。
///
/// 优先解析发帖页 `mfastpost` 里的表情面板(Comiis/DX 的 `img[smilieid]` 或
/// `/static/image/smiley/...` 图片); 若取不到(懒加载或模板差异), 回退到内置的
/// Discuz 默认表情集, 保证选择器始终可用——插入的 `:code:` 由论坛端渲染, 不会失效。
class SmileyService {
  SmileyService._();
  static final instance = SmileyService._();
  static String get _base => SiteConfig.base;
  static String get _cdn => SiteConfig.cdn;

  static const List<(String, String, String)> _builtin = [
    (':lol:', 'lol.gif', '大笑'),
    (':biggrin:', 'biggrin.gif', '偷笑'),
    (':victory:', 'victory.gif', '胜利'),
    (':loveliness:', 'loveliness.gif', '可爱'),
    (':shy:', 'shy.gif', '害羞'),
    (':sweat:', 'sweat.gif', '流汗'),
    (':grin:', 'grin.gif', '露齿笑'),
    (':titter:', 'titter.gif', '傻笑'),
    (':cool:', 'cool.gif', '酷'),
    (':lol: ', 'lol.gif', '大笑'),
    (':haha:', 'haha.gif', '哈哈'),
    (':handshake:', 'handshake.gif', '握手'),
    (':kiss:', 'kiss.gif', '亲亲'),
    (':call:', 'call.gif', '呼叫'),
    (':time:', 'time.gif', '时间'),
    (':mad:', 'mad.gif', '抓狂'),
    (':curse:', 'curse.gif', '咒骂'),
    (':huffy:', 'huffy.gif', '气鼓鼓'),
    (':cry:', 'cry.gif', '大哭'),
    (':sad:', 'sad.gif', '难过'),
    (':tongue:', 'tongue.gif', '吐舌'),
    (':blush:', 'blush.gif', '脸红'),
    (':shocked:', 'shocked.gif', '震惊'),
    (':sleepy:', 'sleepy.gif', '困'),
    (':funk:', 'funk.gif', '搞怪'),
    (':hug:', 'hug.gif', '拥抱'),
    (':shutup:', 'shutup.gif', '闭嘴'),
    (':dizzy:', 'dizzy.gif', '晕'),
  ];

  /// 返回可用的表情列表; 先尝试从发帖页解析, 不足时与内置集合并。
  Future<List<ForumSmiley>> fetchSmileys(int fid) async {
    final parsed = <ForumSmiley>[];
    final seen = <String>{};
    try {
      parsed.addAll(await _scrapeFromPostPage(fid));
      for (final s in parsed) {
        seen.add(s.code);
      }
    } catch (_) {}

    if (parsed.length < 12) {
      for (final (code, file, label) in _builtin) {
        if (seen.add(code)) {
          parsed.add(ForumSmiley(
            code: code == ':lol: ' ? ':lol:' : code,
            imageUrl: '${_cdn}static/image/smiley/default/$file',
            label: label,
          ));
        }
      }
    }
    return parsed;
  }

  /// 打开发帖页, 解析表情面板里的 `img`.
  Future<List<ForumSmiley>> _scrapeFromPostPage(int fid) async {
    final client = await NetClient.instance.client;
    final cookie = AuthService.instance.authCookie;
    final url = '$_base/f.php';
    final pageUrl = Uri.parse('$url').replace(queryParameters: {
      'mod': 'post', 'action': 'newthread', 'fid': '$fid', 'mobile': '2',
    });
    final resp = await NetClient.retry(() => client.get(pageUrl, headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(NetClient.timeout));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final html = NetClient.decode(resp.bodyBytes);
    return _parse(html);
  }

  List<ForumSmiley> _parse(String html) {
    final result = <ForumSmiley>[];
    final seen = <String>{};
    final doc = parser.parse(html);

    for (final img in doc.querySelectorAll('img')) {
      final src = (img.attributes['src'] ?? '').trim();
      if (src.isEmpty || !_isSmileyPath(src)) continue;
      final code = _codeOf(img, src, html);
      if (code.isEmpty) continue;
      final url = _absolute(src);
      if (seen.add(code)) {
        result.add(ForumSmiley(code: code, imageUrl: url, label: code.replaceAll(':', '')));
      }
    }

    // 部分模板用 onclick 插入表情码(如 insertSmile('lol') / insertFace(...)),
    // 额外抓取 `:xxx:` 形态的码并拼默认图。
    if (result.isEmpty || result.length < 8) {
      for (final m in RegExp(r'''(?:insertSmile|insertSmilie)\(\s*['"]([^'"]{1,24}?)['"]''', caseSensitive: false).allMatches(html)) {
        final name = m.group(1)!.trim();
        if (name.isEmpty) continue;
        final code = name.startsWith(':') ? name : ':$name:';
        if (seen.add(code)) {
          result.add(ForumSmiley(
            code: code,
            imageUrl: '${_cdn}static/image/smiley/default/$name.gif',
            label: name,
          ));
        }
      }
    }
    return result;
  }

  bool _isSmileyPath(String src) =>
      src.contains('/smiley/') ||
      src.contains('smile') && (src.endsWith('.gif') || src.endsWith('.png') || src.endsWith('.jpg'));

  String _codeOf(dynamic img, String src, String html) {
    final alt = (img.attributes['alt'] ?? '').trim();
    if (RegExp(r'^:[\w\u4e00-\u9fa5]{1,24}:$').hasMatch(alt)) return alt;
    final id = (img.attributes['smilieid'] ?? '').trim();
    final fileName = Uri.tryParse(src)?.pathSegments.lastOrNull?.replaceAll(RegExp(r'\.\w+$'), '') ?? '';
    final name = alt.isNotEmpty && alt.length <= 24 ? alt : (fileName.isNotEmpty ? fileName : id);
    if (name.isEmpty) return '';
    return name.startsWith(':') ? name : ':$name:';
  }

  String _absolute(String value) {
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return value.startsWith('/') ? _cdn + value.substring(1) : _cdn + value;
  }
}