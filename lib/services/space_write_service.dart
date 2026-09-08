import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 相册的简单描述。
class AlbumInfo {
  final int albumId;
  final String name;
  const AlbumInfo({required this.albumId, required this.name});
}

/// 面向「家园」(Home) 空间功能的原生发布服务：
/// 记心情(doing)、写日志(blog)、发相册(album)。
///
/// 所有写操作与发帖一致: 先用 GET 取得空间页的 formhash, 再以表单 POST 提交;
/// 若服务器返回令牌失效, 依赖 [NetClient] 透明携带 formhash 的一键恢复。
class SpaceWriteService {
  SpaceWriteService._();
  static final instance = SpaceWriteService._();
  static String get _base => SiteConfig.base;

  Map<String, String> _headers({String? referer, bool ajax = false}) => {
    'User-Agent': NetClient.ua,
    'Accept': ajax ? '*/*' : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache, no-store',
    'Pragma': 'no-cache',
    if (referer != null) 'Referer': referer,
    if (ajax) 'X-Requested-With': 'XMLHttpRequest',
    if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!,
  };

  String? get _cookie => AuthService.instance.authCookie;

  Future<String> _getRaw(String path) async {
    final client = await NetClient.instance.client;
    final uri = _withTs(path);
    final resp = await NetClient.retry(() => client.get(uri, headers: _headers()).timeout(NetClient.timeout));
    if (resp.statusCode != 200) throw Exception('请求失败 HTTP ${resp.statusCode}');
    final html = NetClient.decode(resp.bodyBytes);
    if (_looksLikeLogin(html)) throw Exception('登录态已失效，请重新登录论坛');
    return html;
  }

  Uri _withTs(String path) {
    final base = Uri.parse('$_base$path');
    final params = <String, String>{...base.queryParameters, '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString()};
    return base.replace(queryParameters: params);
  }

  // ---------------------------------------------------------------- 记心情
  /// 发表一条心情记录。`message` 为记录内容。
  Future<String?> postDoing({required String message}) async {
    final text = message.trim();
    if (text.isEmpty) return '请输入记录内容';
    if (_cookie == null || _cookie!.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final formhash = await _formhash('home.php?mod=spacecp&ac=doing&mobile=2');
      if (formhash.isEmpty) return '未取得令牌(formhash)，请刷新登录状态后重试';

      final uri = Uri.parse('$_base/home.php').replace(queryParameters: {
        'mod': 'spacecp', 'ac': 'doing', 'mobile': '2', 'inajax': '1',
      });
      final resp = await client.post(
        uri,
        headers: {..._headers(referer: '${_base}home.php?mod=spacecp&ac=doing&mobile=2', ajax: true), 'Origin': _base, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
        body: {'formhash': formhash, 'message': text, 'addfeed': '1', 'quickdoing_submit': 'yes'},
      ).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (_success(body, text)) return null;
      return _error(body) ?? '记录发表失败，请稍后重试';
    } catch (e) {
      return '网络请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  // ---------------------------------------------------------------- 写日志
  Future<String?> createBlog({
    required String title,
    required String content,
    int? categoryId,
  }) async {
    final subject = title.trim();
    final body = content.trim();
    if (subject.isEmpty) return '请输入日志标题';
    if (body.isEmpty) return '请输入日志内容';
    if (_cookie == null || _cookie!.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final formhash = await _formhash('home.php?mod=spacecp&ac=blog&mobile=2');
      if (formhash.isEmpty) return '未取得令牌(formhash)，请刷新登录状态后重试';

      final uri = Uri.parse('$_base/home.php').replace(queryParameters: {
        'mod': 'spacecp', 'ac': 'blog', 'mobile': '2', 'inajax': '1',
      });
      final params = <String, String>{
        'formhash': formhash,
        'subject': subject,
        'message': body,
        'blogcataid': '${categoryId ?? ''}',
        'relatedid': '1.0000000000,0.0000000000',
        'blogsubmit': 'yes',
      };
      final resp = await client.post(
        uri,
        headers: {..._headers(referer: '${_base}home.php?mod=spacecp&ac=blog&mobile=2', ajax: true), 'Origin': _base, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
        body: params,
      ).timeout(NetClient.timeout);
      final responseBody = NetClient.decode(resp.bodyBytes);
      if (_success(responseBody, subject)) return null;
      return _error(responseBody) ?? '日志发表失败，请稍后重试';
    } catch (e) {
      return '网络请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  // ---------------------------------------------------------------- 发相册
  /// 返回我的相册列表(可能为空)。
  Future<List<AlbumInfo>> fetchMyAlbums() async {
    final result = <AlbumInfo>[];
    final seen = <String>{};
    try {
      final html = await _getRaw('home.php?mod=space&do=album&view=me&mobile=2');
      final doc = parser.parse(html);
      for (final a in doc.querySelectorAll('a[href*="album-"],a[href*="ac=album"]')) {
        final href = a.attributes['href'] ?? '';
        final m = RegExp(r'(?:album-|\bid=)(\d+)', caseSensitive: false).firstMatch(href);
        if (m == null) continue;
        final id = int.tryParse(m.group(1)!) ?? 0;
        final name = _clean(a.text);
        if (id <= 0 || name.isEmpty || !seen.add('$id:$name')) continue;
        result.add(AlbumInfo(albumId: id, name: name));
      }
    } catch (_) {}
    return result.take(30).toList();
  }

  /// 新建相册。
  Future<String?> createAlbum({required String name, String description = ''}) async {
    final albumName = name.trim();
    if (albumName.isEmpty) return '请输入相册名称';
    if (_cookie == null || _cookie!.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final formhash = await _formhash('home.php?mod=spacecp&ac=album&mobile=2');
      if (formhash.isEmpty) return '未取得令牌(formhash)，请刷新登录状态后重试';
      final uri = Uri.parse('$_base/home.php').replace(queryParameters: {
        'mod': 'spacecp', 'ac': 'album', 'mobile': '2', 'inajax': '1',
      });
      final resp = await client.post(
        uri,
        headers: {..._headers(referer: '${_base}home.php?mod=spacecp&ac=album&mobile=2', ajax: true), 'Origin': _base, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
        body: {'formhash': formhash, 'albumname': albumName, 'albumdes': description.trim(), 'albumchar': '', 'albumsubmit': 'yes'},
      ).timeout(NetClient.timeout);
      final body = NetClient.decode(resp.bodyBytes);
      if (_success(body, albumName)) return null;
      return _error(body) ?? '相册创建失败，请稍后重试';
    } catch (e) {
      return '网络请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  /// 向指定相册上传一张图片。`albumId` 为相册 id(必须先创建或选定相册)。
  Future<String?> uploadAlbumImage({required PlatformFile file, required int albumId}) async {
    if (file.path == null || file.path!.isEmpty) return '无法读取所选图片';
    if (file.size > 10 * 1024 * 1024) return '图片不能超过 10 MB';
    if (albumId <= 0) return '请先选择或创建相册';
    if (_cookie == null || _cookie!.isEmpty) return '请先登录论坛';
    try {
      final client = await NetClient.instance.client;
      final pageUrl = Uri.parse('$_base/home.php').replace(queryParameters: {
        'mod': 'spacecp', 'ac': 'upload', 'albumid': '$albumId', 'mobile': '2',
      });
      for (var attempt = 0; attempt < 2; attempt++) {
        final pageResp = await NetClient.retry(() => client.get(pageUrl, headers: _headers(referer: _base)).timeout(NetClient.timeout));
        if (pageResp.statusCode != 200) return '读取相册上传页失败 HTTP ${pageResp.statusCode}';
        final html = NetClient.decode(pageResp.bodyBytes);
        final doc = parser.parse(html);
        final formhash = NetClient.extractFormHash(html) ?? (doc.querySelector('input[name="formhash"]')?.attributes['value'] ?? '').trim();
        if (formhash.isEmpty) return '未取得令牌(formhash)，请刷新后重试';
        final uid = AuthService.instance.uid;
        if (uid == null || uid <= 0) return '未取得当前用户ID，请重新登录';
        final uploadHash = _uploadHash(doc, html);
        final uploadUrl = _albumUploadUrl(doc, html, albumId);

        final request = http.MultipartRequest('POST', uploadUrl);
        request.headers.addAll(_headers(referer: pageUrl.toString(), ajax: true));
        request.fields['uid'] = '$uid';
        request.fields['hash'] = uploadHash;
        request.fields['formhash'] = formhash;
        request.fields['albumid'] = '$albumId';
        request.fields['type'] = 'image';
        request.fields['simple'] = '2';
        request.fields['inajax'] = 'yes';
        request.files.add(await http.MultipartFile.fromPath('Filedata', file.path!, filename: file.name));

        final streamed = await request.send().timeout(NetClient.timeout);
        final response = await http.Response.fromStream(streamed);
        final body = NetClient.decode(response.bodyBytes).trim();
        if (response.statusCode >= 200 && response.statusCode < 400 && _parseAlbumUpload(body)) {
          return null;
        }
        if (attempt == 0 && _isTokenFailure(body)) continue;
        return _uploadError(body, response.statusCode);
      }
      return '图片上传失败，请稍后重试';
    } catch (e) {
      return '网络请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  String _uploadHash(dynamic doc, String html) {
    final fromInput = (doc.querySelector('input[name="hash"]')?.attributes['value'] ?? '').trim();
    if (fromInput.isNotEmpty) return fromInput;
    for (final re in <RegExp>[
      RegExp(r'''["']hash["']\s*[:=]\s*["']([A-Za-z0-9_-]{16,128})["']''', caseSensitive: false),
      RegExp(r'''\bhash\s*[:=]\s*["']([A-Za-z0-9_-]{16,128})["']''', caseSensitive: false),
    ]) {
      final m = re.firstMatch(html);
      if (m != null && m.group(1)!.isNotEmpty) return m.group(1)!;
    }
    return '';
  }

  Uri _albumUploadUrl(dynamic doc, String html, int albumId) {
    for (final element in doc.querySelectorAll('form[action],script')) {
      final raw = element.localName == 'form' ? (element.attributes['action'] ?? '') : element.text;
      final m = RegExp(r'''([\w./?=&:%-]*(?:misc\.php|swfupload)[^\s"']*operation=upload[^\s"']*)''', caseSensitive: false).firstMatch(raw);
      if (m != null) {
        final value = m.group(1)!.replaceAll('\\/', '/').replaceAll('&amp;', '&');
        if (value.contains(':') && !value.startsWith('http')) {
          // 相对表单地址同样可解析, 这里继续走默认 URL。
        }
        return Uri.parse(value.startsWith('http') ? value : '$_base${value.startsWith('/') ? value.substring(1) : value}');
      }
    }
    return Uri.parse('$_base/misc.php').replace(queryParameters: {
      'mod': 'swfupload', 'action': 'swfupload', 'operation': 'upload',
      'type': 'image', 'albumid': '$albumId', 'inajax': 'yes', 'infloat': 'yes', 'simple': '2',
    });
  }

  bool _parseAlbumUpload(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final dynamic data = json['data'] is Map ? json['data'] : json;
        final picid = int.tryParse('${data['picid'] ?? data['id'] ?? data['albumid'] ?? ''}') ?? 0;
        if (picid > 0 || (json['status'] ?? '') == 'success') return true;
      }
    } catch (_) {}
    final parts = body.replaceAll('\r', '').replaceAll('\n', '').split('|');
    if (parts.length >= 2 && parts[0].trim().toUpperCase() == 'IMAGEUPLOAD') {
      return (int.tryParse(parts[1].trim()) ?? 1) == 0;
    }
    return body.contains('succeed') || body.contains('上传成功');
  }

  bool _isTokenFailure(String body) {
    final lower = body.toLowerCase();
    return (lower.contains('formhash') && (lower.contains('错误') || lower.contains('非法') || lower.contains('失效') || lower.contains('无效'))) ||
        lower.contains('操作令牌已失效') || lower.contains('来路不正确') || lower.contains('非法操作');
  }

  String _uploadError(String body, int status) {
    final text = body.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.contains('formhash') || text.contains('非法操作')) return '上传令牌已失效，请刷新后重试';
    if (text.contains('不支持此类扩展名')) return '不支持上传该图片类型';
    if (text.contains('超过')) return text.length <= 60 ? text : '图片过大，上传失败';
    if (text.contains('登录')) return '登录态已失效，请重新登录论坛';
    if (text.isEmpty) return '图片上传失败 HTTP $status';
    return text.length <= 80 ? text : '图片上传失败，请稍后重试';
  }

  // ---------------------------------------------------------------- 工具
  Future<String> _formhash(String path) async {
    final html = await _getRaw(path);
    final doc = parser.parse(html);
    final fromInput = (doc.querySelector('input[name="formhash"]')?.attributes['value'] ?? '').trim();
    if (fromInput.isNotEmpty) return fromInput;
    final fromNet = NetClient.extractFormHash(html);
    return fromNet ?? '';
  }

  static bool _success(String body, String echo) {
    final lower = body.toLowerCase();
    if (lower.contains('succeed') || lower.contains('do_success') || lower.contains('操作成功') || lower.contains('发布成功') || lower.contains('发表成功') || lower.contains('创建成功') || lower.contains('保存成功')) return true;
    final b = body.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), '');
    final t = echo.replaceAll(RegExp(r'\s+'), '');
    return lower.contains('<root') && t.isNotEmpty && b.contains(t.substring(0, t.length > 8 ? 8 : t.length));
  }

  static String? _error(String body) {
    final text = body.replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.contains('登录')) return '登录态已失效，请重新登录论坛';
    if (text.contains('formhash') || text.contains('非法请求') || text.contains('操作令牌')) return '操作令牌已失效，请重新进入页面后再试';
    final showError = RegExp(r'''showError\(\s*["']([^"']+)["']''').firstMatch(body)?.group(1)?.trim();
    if (showError != null && showError.isNotEmpty) return showError;
    if (text.isEmpty) return null;
    return text.length <= 120 ? text : null;
  }

  static bool _looksLikeLogin(String html) {
    final doc = parser.parse(html);
    for (final node in doc.querySelectorAll('script,style,noscript,template')) { node.remove(); }
    final text = _clean(doc.body?.text ?? '');
    return text.isNotEmpty && text.contains('登录') && RegExp(r'(用户名|登录密码)').hasMatch(text) && !html.contains('action=logout');
  }

  static String _clean(String text) =>
      text.replaceAll('\uFFFD', '').replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}