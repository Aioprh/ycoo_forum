import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// Discuz 主题编辑：严格按照实际编辑页的 form action + 隐藏字段提交。
class ThreadEditService {
  ThreadEditService._();
  static final instance = ThreadEditService._();

  static String get _base => SiteConfig.base;

  Future<String?> editThread({
    required int tid,
    required int fid,
    required int pid,
    required String subject,
    required String message,
  }) async {
    if (!AuthService.instance.isLoggedIn ||
        (AuthService.instance.authCookie ?? '').isEmpty) {
      return '请先登录论坛';
    }

    final title = subject.trim();
    final body = message.trim();
    if (title.isEmpty) return '请输入标题';
    if (title.length > 100) return '标题不能超过 100 个字符';
    if (body.isEmpty) return '请输入正文';

    try {
      final client = await NetClient.instance.client;
      final headers = _headers();
      final editUrl = Uri.parse(
        '${_base}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1&mobile=2',
      );

      final page = await NetClient.retry(
        () => client.get(editUrl, headers: headers).timeout(NetClient.timeout),
      );
      if (page.statusCode != 200) {
        return '读取编辑页失败 HTTP ${page.statusCode}';
      }

      final html = NetClient.decode(page.bodyBytes);
      final doc = parser.parse(html);
      final form = doc.querySelector('form#postform') ??
          doc.querySelector('form[name="postform"]') ??
          doc.querySelector('form');

      if (form == null) {
        final text = _plain(doc);
        if (_looksLikeLogin(text)) return '登录状态已失效，请重新登录';
        if (_looksLikePermission(text)) return '只有帖子作者可以编辑该主题';
        return '未取得编辑表单，请重新进入帖子后再试';
      }

      final formhash = NetClient.extractFormHash(html) ??
          (doc.querySelector('input[name="formhash"]')?.attributes['value'] ?? '').trim();
      if (formhash.isEmpty) return '未取得编辑令牌(formhash)，请重新进入帖子后再试';

      final fields = _collectForm(form);
      fields['formhash'] = formhash;
      fields['fid'] = '$fid';
      fields['tid'] = '$tid';
      fields['pid'] = '$pid';
      fields['subject'] = title;
      fields['message'] = body;
      fields['editsubmit'] = 'yes';

      // 关键修复：不要硬编码 POST 地址，优先使用论坛编辑页真正的 form action。
      // 不同 Discuz 二开模板可能把 tid/pid/extra 放在 action 查询串中。
      final action = (form.attributes['action'] ?? '').trim();
      Uri postUrl = editUrl;
      if (action.isNotEmpty) {
        final parsed = Uri.tryParse(action);
        if (parsed != null) {
          postUrl = parsed.hasScheme
              ? parsed
              : editUrl.resolveUri(parsed);
        }
      }

      final query = Map<String, String>.from(postUrl.queryParameters);
      query['editsubmit'] = 'yes';
      query.putIfAbsent('fid', () => '$fid');
      query.putIfAbsent('tid', () => '$tid');
      query.putIfAbsent('pid', () => '$pid');
      postUrl = postUrl.replace(queryParameters: query);

      final response = await client
          .post(
            postUrl,
            headers: {
              ...headers,
              'Referer': editUrl.toString(),
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            },
            body: fields,
          )
          .timeout(NetClient.timeout);

      final result = NetClient.decode(response.bodyBytes);
      final resultDoc = parser.parse(result);
      final text = _plain(resultDoc);

      if (_isSuccess(resultDoc, text)) return null;
      if (_looksLikeLogin(text)) return '登录状态已失效，请重新登录';
      if (text.contains('formhash') || text.contains('非法请求') || text.contains('验证失败')) {
        return '编辑令牌已失效，请重新进入帖子后再试';
      }
      if (_looksLikePermission(text)) return '只有帖子作者可以编辑该主题';
      if (text.contains('验证码')) return '论坛要求验证码，请使用网页完成验证后再编辑';
      if (text.contains('内容不能为空')) return '正文不能为空';
      if (text.contains('标题不能为空')) return '标题不能为空';
      if (text.contains('标题太长')) return '标题不能超过 100 个字符';

      return _firstFailure(text) ?? '保存失败，请稍后重试';
    } catch (e) {
      return '编辑请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  Map<String, String> _collectForm(dynamic form) {
    final out = <String, String>{};

    void put(String name, String value) {
      if (name.isNotEmpty) out[name] = value;
    }

    for (final input in form.querySelectorAll('input')) {
      if (input.attributes['disabled'] != null) continue;
      final name = input.attributes['name'] ?? '';
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (name.isEmpty || type == 'file') continue;

      if (type == 'radio' || type == 'checkbox') {
        if (input.attributes['checked'] != null) {
          put(name, input.attributes['value'] ?? 'on');
        }
      } else {
        put(name, input.attributes['value'] ?? '');
      }
    }

    for (final area in form.querySelectorAll('textarea')) {
      final name = area.attributes['name'] ?? '';
      if (name.isNotEmpty) put(name, area.text);
    }

    for (final select in form.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      String? value;
      for (final option in select.querySelectorAll('option')) {
        if (option.attributes['selected'] != null) {
          value = option.attributes['value'] ?? '';
          break;
        }
      }
      value ??= select.querySelector('option')?.attributes['value'] ?? '';
      put(name, value);
    }

    return out;
  }

  Map<String, String> _headers() => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if ((AuthService.instance.authCookie ?? '').isNotEmpty)
          'Cookie': AuthService.instance.authCookie!,
      };

  String _plain(dynamic doc) =>
      (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _looksLikeLogin(String text) =>
      text.contains('请登录') || text.contains('登录后') || text.contains('请先登录');

  bool _looksLikePermission(String text) =>
      text.contains('无权') || text.contains('没有权限') || text.contains('权限不足');

  bool _isSuccess(dynamic doc, String text) {
    if (RegExp(r'(编辑成功|保存成功|主题已(?:编辑|更新)|已(?:保存|更新))').hasMatch(text)) {
      return true;
    }
    if (doc.querySelector('meta[http-equiv="refresh"]') != null) return true;
    final redirect = doc.querySelector('a[href*="thread-"]');
    return redirect != null && !text.contains('失败');
  }

  String? _firstFailure(String text) {
    const keys = <String>[
      '禁止编辑',
      '编辑失败',
      '内容包含敏感词',
      '操作失败',
      '帖子不存在',
      '主题不存在',
    ];
    for (final key in keys) {
      if (text.contains(key)) return key;
    }
    return null;
  }
}
