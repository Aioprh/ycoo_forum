import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

class FollowService {
  FollowService._();
  static final instance = FollowService._();

  static String get _base => SiteConfig.base;

  Future<String?> toggle({required int uid, required bool follow}) async {
    if (uid <= 0) return '用户无效';
    final cookie = AuthService.instance.authCookie;
    if (cookie == null || cookie.isEmpty) return '请先登录论坛';

    final client = await NetClient.instance.client;
    final profileUrl = '${_base}home.php?mod=space&uid=$uid&do=profile&mobile=2&_ycoo_follow=${DateTime.now().millisecondsSinceEpoch}';

    try {
      final pageResp = await NetClient.retry(() => client.get(
            Uri.parse(profileUrl),
            headers: {
              'User-Agent': NetClient.ua,
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
              'Referer': '${_base}home.php?mod=space&uid=$uid&mobile=2',
              'Cookie': cookie,
            },
          ).timeout(const Duration(seconds: 20)));

      if (pageResp.statusCode != 200) return '读取个人资料失败 HTTP ${pageResp.statusCode}';
      final html = NetClient.decode(pageResp.bodyBytes);
      if (_looksLikeLogin(html)) return '登录态已失效，请重新登录论坛';

      // Discuz 的标准关注入口会把真正可用的 hash/formhash 直接渲染进 href：
      // home.php?mod=spacecp&ac=follow&op=add&hash={FORMHASH}&fuid=xxx&mobile=2
      // 这里直接复用页面生成的完整操作 URL，不再自行猜测 token 放在哪里。
      final action = _findFollowAction(html, uid, follow);
      if (action == null) {
        return '个人资料页未找到有效的关注操作，请刷新后重试';
      }

      final uri = Uri.parse(_absolute(action));
      final response = await NetClient.retry(() => client.get(
            uri,
            headers: {
              'User-Agent': NetClient.ua,
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Referer': profileUrl,
              'Cookie': cookie,
              'X-Requested-With': 'XMLHttpRequest',
            },
          ).timeout(const Duration(seconds: 20)));

      final body = NetClient.decode(response.bodyBytes);
      if (_success(body, follow)) return null;
      if (_looksLikeLogin(body)) return '登录态已失效，请重新登录论坛';
      if (_tokenError(body)) return '操作令牌已失效，请刷新后重试';
      return follow ? '关注失败，请稍后重试' : '取消关注失败，请稍后重试';
    } catch (_) {
      return '操作失败，请检查网络后重试';
    }
  }

  static String? _findFollowAction(String html, int uid, bool follow) {
    final doc = parser.parse(html);
    final expectedOp = follow ? 'add' : 'del';
    final candidates = <String>[];

    // 先从页面提取全局 hash —— 所有 follow 操作(op=add/del)共用同一令牌。
    final globalHash = _globalHash(doc, html);

    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final decoded = href.replaceAll('&amp;', '&');
      final lower = decoded.toLowerCase();
      if (!lower.contains('mod=spacecp') || !lower.contains('ac=follow')) continue;
      if (!lower.contains('op=$expectedOp')) continue;

      final uri = Uri.tryParse(decoded);
      if (uri == null) continue;
      final targetUid = int.tryParse(uri.queryParameters['fuid'] ?? uri.queryParameters['uid'] ?? '');
      if (targetUid != uid) continue;

      // Discuz op=del 虽然 href 通常不带 hash, 但服务端仍校验令牌,
      // 因此必须把页面全局 hash 补进 URL。op=add 同理, 这里统一补齐。
      if ((uri.queryParameters['hash'] ?? '').trim().isEmpty && globalHash.isNotEmpty) {
        final rebuilt = <String, String>{
          for (final entry in uri.queryParametersAll.entries) entry.key: entry.value.first,
          'hash': globalHash,
        };
        final built = uri.replace(queryParameters: rebuilt).toString();
        candidates.add(built);
      } else {
        candidates.add(decoded);
      }
    }

    if (candidates.isNotEmpty) return candidates.first;

    // 某些模板把操作链接放在 HTML/JS 字符串中, 而不是普通 <a>。
    final escapedUid = RegExp.escape('$uid');
    final pattern = RegExp(
      'home\\.php\\?mod=spacecp&ac=follow&op=$expectedOp[^"\\\'<>\\s]*?(?:fuid|uid)=$escapedUid[^"\\\'<>\\s]*',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(html)) {
      var value = match.group(0) ?? '';
      value = value.replaceAll('&amp;', '&');
      final uri = Uri.tryParse(value);
      if (uri == null) continue;
      if ((uri.queryParameters['hash'] ?? '').trim().isEmpty && globalHash.isNotEmpty) {
        final rebuilt = <String, String>{
          for (final entry in uri.queryParametersAll.entries) entry.key: entry.value.first,
          'hash': globalHash,
        };
        final built = uri.replace(queryParameters: rebuilt).toString();
        return built;
      }
      return value;
    }
    return null;
  }

  static String _globalHash(dom.Document doc, String html) {
    // 优先从 <input name="formhash"> / <input name="hash"> 取, 回退到页面脚本里常见的 hash 值。
    for (final input in doc.querySelectorAll('input[name="formhash"], input[name="hash"]')) {
      final v = input.attributes['value']?.trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final hashRe = RegExp('(?:formhash|hash)\\s*[=:]\\s*["\']([a-zA-Z0-9]{6,})["\']', caseSensitive: false);
    final m = hashRe.firstMatch(html);
    return m?.group(1) ?? '';
  }

  static bool _success(String body, bool follow) {
    final lower = body.toLowerCase();
    if (lower.contains('succeed') || body.contains('成功')) return true;
    if (follow && (body.contains('已关注') || body.contains('取消关注'))) return true;
    if (!follow && (body.contains('取消关注') || body.contains('关注ta') || body.contains('关注'))) {
      return !lower.contains('失败') && !lower.contains('error');
    }
    return false;
  }

  static bool _tokenError(String body) {
    final lower = body.toLowerCase();
    return lower.contains('formhash') ||
        (lower.contains('hash') && (lower.contains('错误') || lower.contains('invalid') || lower.contains('失效')));
  }

  static bool _looksLikeLogin(String html) {
    final lower = html.toLowerCase();
    return lower.contains('name="loginfield"') ||
        lower.contains('id="ls_username"') ||
        (html.contains('登录') && lower.contains('password'));
  }

  static String _absolute(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return _base + value.substring(1);
    return _base + value;
  }
}
