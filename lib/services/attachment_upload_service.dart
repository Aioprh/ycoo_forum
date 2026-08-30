import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'net_client.dart';

/// Discuz/X3 论坛附件上传。
///
/// 站点网页端使用 misc.php?mod=swfupload&operation=upload，
/// 上传前从当前发帖页取得 uid/hash，上传后返回 aid，再由发帖请求提交
/// attachnew[aid][...] 将“未使用附件”绑定到新主题。
class UploadedAttachment {
  final int aid;
  final String name;
  final int size;
  /// 本地文件路径仅用于移动端上传后的即时预览，不参与服务端提交。
  final String? localPath;

  const UploadedAttachment({
    required this.aid,
    required this.name,
    required this.size,
    this.localPath,
  });
}

class AttachmentUploadService {
  AttachmentUploadService._();
  static final instance = AttachmentUploadService._();

  static const _base = 'https://www.ycoo.net/';
  static const int maxBytes = 10 * 1024 * 1024;

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

  Future<UploadedAttachment> upload({required int fid, required PlatformFile file}) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) {
      throw Exception('请先登录论坛');
    }
    if (fid <= 0) throw Exception('未选择有效版块');
    if (file.path == null || file.path!.isEmpty) throw Exception('无法读取所选文件');
    final size = file.size;
    if (size > maxBytes) throw Exception('附件不能超过 10 MB');

    final client = await NetClient.instance.client;
    final pageUrl = Uri.parse('${_base}forum.php?mod=post&action=newthread&fid=$fid&mobile=2');
    final pageResp = await NetClient.retry(() => client.get(pageUrl, headers: _headers(referer: _base)).timeout(NetClient.timeout));
    if (pageResp.statusCode != 200) throw Exception('读取发帖页面失败 HTTP ${pageResp.statusCode}');
    final html = NetClient.decode(pageResp.bodyBytes);
    final doc = parser.parse(html);
    final formhash = _hidden(doc, 'formhash');
    if (formhash.isEmpty) throw Exception('未取得发帖令牌(formhash)，请刷新后重试');

    final uid = AuthService.instance.uid;
    if (uid == null || uid <= 0) throw Exception('未取得当前用户ID，请重新登录');
    final uploadHash = _uploadHash(doc, html);
    if (uploadHash.isEmpty) throw Exception('未取得附件上传令牌，请重新进入发帖页面后重试');

    final uploadUrl = _uploadUrl(doc, html, fid);
    final request = http.MultipartRequest('POST', uploadUrl);
    request.headers.addAll(_headers(referer: pageUrl.toString(), ajax: true));
    request.fields['uid'] = '$uid';
    request.fields['hash'] = uploadHash;
    request.fields['formhash'] = formhash;
    request.fields['fid'] = '$fid';
    request.fields['simple'] = '2';
    request.fields['inajax'] = 'yes';
    request.files.add(await http.MultipartFile.fromPath('Filedata', file.path!, filename: file.name));

    final streamed = await request.send().timeout(NetClient.timeout);
    final response = await http.Response.fromStream(streamed);
    final body = NetClient.decode(response.bodyBytes).trim();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw Exception(_uploadError(body, response.statusCode));
    }

    final parsed = _parseUploadResponse(body, file.name, size, file.path);
    if (parsed == null) throw Exception(_uploadError(body, response.statusCode));
    return parsed;
  }

  String _hidden(dynamic doc, String name) {
    final input = doc.querySelector('input[name="$name"]');
    return (input?.attributes['value'] ?? '').trim();
  }

  String _uploadHash(dynamic doc, String html) {
    final input = _hidden(doc, 'hash');
    if (input.isNotEmpty) return input;
    final patterns = <RegExp>[
      RegExp(r'''["']hash["']\s*[:=]\s*["']([A-Za-z0-9_-]{16,128})["']''', caseSensitive: false),
      RegExp(r'''\bhash\s*[:=]\s*["']([A-Za-z0-9_-]{16,128})["']''', caseSensitive: false),
      RegExp(r'''["']hash["']\s*:\s*["']([A-Fa-f0-9]{16,128})["']''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null && match.group(1)!.isNotEmpty) return match.group(1)!;
    }
    return '';
  }

  Uri _uploadUrl(dynamic doc, String html, int fid) {
    for (final element in doc.querySelectorAll('form[action],script')) {
      final raw = element.localName == 'form' ? (element.attributes['action'] ?? '') : element.text;
      final match = RegExp(r'''((?:https?:)?//[^\s"']*misc\.php[^\s"']*mod=swfupload[^\s"']*operation=upload[^\s"']*)''', caseSensitive: false).firstMatch(raw) ??
          RegExp(r'''([\w./?=&:%-]*misc\.php[^\s"']*mod=swfupload[^\s"']*operation=upload[^\s"']*)''', caseSensitive: false).firstMatch(raw);
      if (match != null) {
        final value = match.group(1)!.replaceAll('\\/', '/').replaceAll('&amp;', '&');
        return Uri.parse(value.startsWith('http') ? value : '$_base${value.startsWith('/') ? value.substring(1) : value}');
      }
    }
    return Uri.parse('${_base}misc.php').replace(queryParameters: {
      'mod': 'swfupload',
      'action': 'swfupload',
      'operation': 'upload',
      'fid': '$fid',
      'inajax': 'yes',
      'infloat': 'yes',
      'simple': '2',
    });
  }

  UploadedAttachment? _parseUploadResponse(String body, String fallbackName, int size, String? localPath) {
    if (body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final dynamic data = json['data'] is Map ? json['data'] : json;
        final aid = int.tryParse('${data['aid'] ?? data['id'] ?? ''}') ?? 0;
        if (aid > 0) return UploadedAttachment(
          aid: aid,
          name: '${data['filename'] ?? data['name'] ?? fallbackName}',
          size: size,
          localPath: localPath,
        );
      }
    } catch (_) {}

    final parts = body.replaceAll('\r', '').replaceAll('\n', '').split('|');
    if (parts.length >= 4 && parts[0].trim() == 'DISCUZUPLOAD') {
      final error = int.tryParse(parts[2].trim()) ?? -1;
      final aid = int.tryParse(parts[3].trim()) ?? 0;
      if (error == 0 && aid > 0) {
        final name = parts.length > 6 && parts[6].trim().isNotEmpty ? parts[6].trim() : fallbackName;
        return UploadedAttachment(aid: aid, name: name, size: size, localPath: localPath);
      }
    }
    return null;
  }

  String _uploadError(String body, int status) {
    final text = body.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.contains('formhash') || text.contains('非法操作')) return '附件上传令牌已失效，请刷新后重试';
    if (text.contains('不支持此类扩展名')) return '当前版块不允许上传该文件类型';
    if (text.contains('附件文件无法保存')) return '论坛服务器无法保存附件';
    if (text.contains('没有合法的文件')) return '没有合法的文件被上传';
    if (text.contains('登录')) return '登录态已失效，请重新登录论坛';
    if (text.isEmpty) return '附件上传失败 HTTP $status';
    final end = text.length < 120 ? text.length : 120;
    return text.substring(0, end);
  }
}
