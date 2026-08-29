import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';

/// 通过当前登录 Cookie 调用 Discuz 原生发帖接口。
class ThreadPublishService {
  ThreadPublishService._();
  static final instance = ThreadPublishService._();
  static const _base = 'https://www.ycoo.net/';

  Future<String?> createThread({
    required int fid,
    required String subject,
    required String message,
  }) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) {
      return '请先登录论坛';
    }
    final title = subject.trim();
    final body = message.trim();
    if (title.isEmpty) return '请输入标题';
    if (body.isEmpty) return '请输入正文';

    try {
      final client = await NetClient.instance.client;
      final headers = <String, String>{
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        'Cookie': AuthService.instance.authCookie!,
      };
      final forumUrl = '${_base}forum.php?mod=post&action=newthread&fid=$fid&mobile=2';
      final page = await client.get(Uri.parse(forumUrl), headers: headers).timeout(NetClient.timeout);
      final html = NetClient.decode(page.bodyBytes);
      final doc = parser.parse(html);
      final formhash = _value(doc, 'formhash');
      if (formhash.isEmpty) return _guestOrMessage(doc, '未取得发帖令牌(formhash)，请重新进入版块后再试');

      final form = <String, String>{
        'formhash': formhash,
        'posttime': _value(doc, 'posttime'),
        'wysiwyg': '1',
        'subject': title,
        'message': body,
        'topicsubmit': 'yes',
        'usesig': '1',
        'allownoticeauthor': '1',
      };
      _copyIfPresent(doc, form, 'typeid');
      _copyIfPresent(doc, form, 'sortid');
      _copyIfPresent(doc, form, 'special');
      _copyIfPresent(doc, form, 'hiddenreplies');
      _copyIfPresent(doc, form, 'readperm');

      final response = await client.post(
        Uri.parse(forumUrl),
        headers: {...headers, 'Referer': forumUrl, 'Content-Type': 'application/x-www-form-urlencoded'},
        body: form,
      ).timeout(NetClient.timeout);
      final result = NetClient.decode(response.bodyBytes);
      final resultDoc = parser.parse(result);
      final text = resultDoc.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? result;

      if (_success(resultDoc, text)) return null;
      if (text.contains('登录') || text.contains('请先登录')) return '登录状态已失效，请重新登录';
      if (text.contains('formhash') || text.contains('验证失败')) return '发帖令牌已失效，请重新进入版块后再试';
      if (text.contains('权限') || text.contains('无权')) return '当前账号没有在该版块发帖的权限';
      if (text.contains('验证码')) return '论坛要求验证码，请使用网页完成验证后再发帖';
      return _firstFailure(text) ?? '发帖失败，请稍后重试';
    } catch (_) {
      return '发帖请求失败，请检查网络后重试';
    }
  }

  String _value(dynamic doc, String name) {
    final input = doc.querySelector('input[name="$name"]');
    return input?.attributes['value'] ?? '';
  }

  void _copyIfPresent(dynamic doc, Map<String, String> form, String name) {
    final value = _value(doc, name);
    if (value.isNotEmpty) form[name] = value;
  }

  bool _success(dynamic doc, String text) {
    if (text.contains('发表成功') || text.contains('主题发表成功') || text.contains('发布成功')) return true;
    if (doc.querySelector('meta[http-equiv="refresh"]') != null) return true;
    final redirect = doc.querySelector('a[href*="thread-"]');
    return redirect != null && !text.contains('发帖失败');
  }

  String _guestOrMessage(dynamic doc, String fallback) {
    final text = doc.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (text.contains('请登录') || text.contains('登录后')) return '登录状态已失效，请重新登录';
    return fallback;
  }

  String? _firstFailure(String text) {
    const keys = ['禁止发帖', '发帖频率', '内容包含敏感词', '标题太长', '标题不能为空', '内容不能为空', '版块不存在'];
    for (final key in keys) {
      if (text.contains(key)) return key;
    }
    return null;
  }
}
