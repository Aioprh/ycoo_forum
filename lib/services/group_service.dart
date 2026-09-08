import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 一个圈子(群组)。
class CircleGroup {
  final int groupId; // group 自身的 id (gid)
  final int fid;     // 对应论坛版块 id, 用于发帖
  final String name;
  const CircleGroup({required this.groupId, required this.fid, required this.name});
}

/// Discuz 圈子(群组)能力:
/// 1) 拉取 `group.php?mod=index` 的群组列表;
/// 2) 向指定群组 `group.php?mod=post&action=newthread` 发布主题。
class GroupService {
  GroupService._();
  static final instance = GroupService._();
  static String get _base => SiteConfig.base;

  Map<String, String> _headers({String? referer}) => {
    'User-Agent': NetClient.ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache, no-store',
    'Pragma': 'no-cache',
    if (referer != null) 'Referer': referer,
    if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!,
  };

  Future<List<CircleGroup>> fetchGroups() async {
    final client = await NetClient.instance.client;
    final result = <CircleGroup>[];
    final seen = <int>{};
    try {
      final uri = Uri.parse('$_base/group.php').replace(queryParameters: {
        'mod': 'index', '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final resp = await NetClient.retry(() => client.get(uri, headers: _headers()).timeout(NetClient.timeout));
      if (resp.statusCode != 200) return result;
      final html = NetClient.decode(resp.bodyBytes);
      final doc = parser.parse(html);
      for (final a in doc.querySelectorAll('a[href*="group.php"],a[href*="group-"]')) {
        final href = a.attributes['href'] ?? '';
        final lower = href.toLowerCase();
        // 只取指向群组自身/其版块的链接, 跳过发帖、帮助等动作链接。
        if (!lower.contains('mod=forumdisplay') && !lower.contains('mod=viewthread') && !RegExp(r'[\?&]fid=\d+', caseSensitive: false).hasMatch(href)) continue;
        final fid = int.tryParse(RegExp(r'(?:fid=|%26fid%3D|[\?&]fid=)\s*(\d+)', caseSensitive: false).firstMatch(href)?.group(1) ?? '') ?? 0;
        final gid = int.tryParse(RegExp(r'(?:gid=|%26gid%3D|[\?&]gid=)\s*(\d+)', caseSensitive: false).firstMatch(href)?.group(1) ?? '') ?? 0;
        final name = a.text.trim();
        if (fid <= 0 || name.isEmpty || name.contains('更多') || name.length > 40 || !seen.add(fid)) continue;
        result.add(CircleGroup(groupId: gid, fid: fid, name: name));
        if (result.length >= 100) break;
      }
    } catch (_) {}
    return result;
  }

  /// 向群组发布新主题。`fid` 为群组对应版块 id, `gid` 为群组 id(可能为 0)。
  Future<String?> createGroupThread({
    required int fid,
    required int gid,
    required String subject,
    required String message,
  }) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) return '请先登录论坛';
    final title = subject.trim();
    final body = message.trim();
    if (fid <= 0) return '未选择有效群组';
    if (title.isEmpty) return '请输入标题';
    if (body.isEmpty) return '请输入正文';
    try {
      final client = await NetClient.instance.client;
      final pageUrl = Uri.parse('$_base/group.php').replace(queryParameters: {
        'mod': 'post', 'action': 'newthread', 'fid': '$fid', 'gid': '$gid', 'mobile': '2',
      });
      final page = await NetClient.retry(() => client.get(pageUrl, headers: _headers(referer: _base)).timeout(NetClient.timeout));
      if (page.statusCode != 200) return '读取群组发帖页失败 HTTP ${page.statusCode}';
      final html = NetClient.decode(page.bodyBytes);
      final doc = parser.parse(html);
      final formhash = NetClient.extractFormHash(html) ?? _value(doc, 'formhash');
      if (formhash.isEmpty) return '未取得发帖令牌(formhash)，请重新进入群组后再试';

      final form = <String, String>{
        'formhash': formhash,
        'posttime': _value(doc, 'posttime'),
        'wysiwyg': '0',
        'subject': title,
        'message': body,
        'groupsubmit': 'yes',
        'usesig': '1',
      };
      for (final name in const ['typeid', 'sortid', 'special', 'gid']) {
        final v = _value(doc, name);
        if (v.isNotEmpty) form[name] = v;
      }
      if (gid > 0) form['gid'] = '$gid';

      final resp = await client.post(
        pageUrl,
        headers: {..._headers(referer: pageUrl.toString()), 'Origin': _base, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
        body: form,
      ).timeout(NetClient.timeout);
      final result = NetClient.decode(resp.bodyBytes);
      final text = _plain(result);
      if (_success(result, text)) return null;
      if (text.contains('登录')) return '登录状态已失效，请重新登录';
      if (text.contains('formhash') || text.contains('验证失败') || text.contains('非法请求')) return '发帖令牌已失效，请重新进入群组后再试';
      if (text.contains('权限') || text.contains('无权')) return '当前账号没有在该群组发帖的权限';
      if (text.contains('验证码')) return '论坛要求验证码，请使用网页完成验证后再发帖';
      final showError = RegExp(r'''showError\(\s*["']([^"']+)["']''').firstMatch(result)?.group(1)?.trim();
      if (showError != null && showError.isNotEmpty) return showError;
      return text.isEmpty ? '发帖失败，请稍后重试' : (text.length <= 120 ? text : '发帖失败，请稍后重试');
    } catch (e) {
      return '发帖请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  String _value(dynamic doc, String name) => (doc.querySelector('input[name="$name"]')?.attributes['value'] ?? '').trim();

  bool _success(String result, String text) {
    if (text.contains('发表成功') || text.contains('发布成功')) return true;
    if (_plainContains(result, 'succeedhandle_') || _plainContains(result, 'do_success')) return true;
    if (result.contains('meta[http-equiv="refresh"]'.replaceAll('meta[', 'meta '))) {
      // 仅当做转义占位, 真正的判定交给下方链接判断。
    }
    if (result.contains('location.href') && result.contains('group-')) return true;
    final redirect = RegExp(r'''a[^>]*href=["'][^"']*(?:group-|thread-\d|group\.php\?mod=viewthread)[^"']*["']''', caseSensitive: false).firstMatch(result);
    return redirect != null && !text.contains('发帖失败');
  }

  static bool _plainContains(String body, String needle) {
    final plain = body.replaceAll(RegExp(r'\s+'), '');
    return plain.contains(needle);
  }

  String _plain(String html) => (parser.parse(html).body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}