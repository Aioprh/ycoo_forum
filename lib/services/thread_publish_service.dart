import 'package:html/parser.dart' as parser;

import 'site_config.dart';
import 'attachment_upload_service.dart';
import 'auth_service.dart';
import 'net_client.dart';

/// 版块的主题分类（typeid）选项。
class ThreadType {
  final int id;
  final String name;
  const ThreadType(this.id, this.name);
}

/// 通过当前登录 Cookie 调用 Discuz 原生发帖接口。
class ThreadPublishService {
  ThreadPublishService._();
  static final instance = ThreadPublishService._();
  static String get _base => SiteConfig.base;

  Future<List<ThreadType>> fetchThreadTypes(int fid) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) return const [];
    try {
      final doc = await _postPage(fid);
      final result = <ThreadType>[];
      for (final select in doc.querySelectorAll('select[name="typeid"]')) {
        for (final opt in select.querySelectorAll('option')) {
          final id = int.tryParse(opt.attributes['value'] ?? '');
          final name = opt.text.trim();
          if (id == null || id <= 0 || name.isEmpty || name.contains('请选择')) continue;
          if (result.every((e) => e.id != id)) result.add(ThreadType(id, name));
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<String?> createThread({
    required int fid,
    required String subject,
    required String message,
    int? typeid,
    int price = 0,
    int readperm = 0,
    bool usesig = true,
    bool allownoticeauthor = true,
    bool hiddenreplies = false,
    bool descviewdefault = false,
    bool addfeed = true,
    DateTime? scheduledAt,
    List<UploadedAttachment> attachments = const [],
  }) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) return '请先登录论坛';
    final title = subject.trim();
    final body = message.trim();
    if (title.isEmpty) return '请输入标题';
    if (title.length > 100) return '标题不能超过 100 个字符';
    if (body.isEmpty && attachments.isEmpty) return '请输入正文或添加附件';
    if (scheduledAt != null && !scheduledAt.isAfter(DateTime.now())) return '定时发布时间必须晚于当前时间';

    try {
      final client = await NetClient.instance.client;
      final forumUrl = '${_base}forum.php?mod=post&action=newthread&fid=$fid&mobile=2';
      final headers = _headers();
      final page = await NetClient.retry(() => client.get(Uri.parse(forumUrl), headers: headers).timeout(NetClient.timeout));
      if (page.statusCode != 200) return '读取发帖页面失败 HTTP ${page.statusCode}';
      final html = NetClient.decode(page.bodyBytes);
      final doc = parser.parse(html);
      final formhash = NetClient.extractFormHash(html) ?? _value(doc, 'formhash');
      if (formhash.isEmpty) return _guestOrMessage(doc, '未取得发帖令牌(formhash)，请重新进入版块后再试');

      final form = <String, String>{
        'formhash': formhash,
        'posttime': _value(doc, 'posttime'),
        'wysiwyg': '0',
        'subject': title,
        'message': body,
        'topicsubmit': 'yes',
        'usesig': usesig ? '1' : '0',
        'allownoticeauthor': allownoticeauthor ? '1' : '0',
      };

      _copyIfPresent(doc, form, 'typeid');
      _copyIfPresent(doc, form, 'sortid');
      _copyIfPresent(doc, form, 'special');
      _setIfPresent(doc, form, 'hiddenreplies', hiddenreplies ? '1' : '0');
      // Discuz X3.x 原生字段名是 ordertype，部分二开模板才使用 descviewdefault。
      _setIfPresent(doc, form, 'ordertype', descviewdefault ? '1' : '0');
      _setIfPresent(doc, form, 'descviewdefault', descviewdefault ? '1' : '0');
      _setIfPresent(doc, form, 'addfeed', addfeed ? '1' : '0');

      if (typeid != null && typeid > 0 && _hasField(doc, 'typeid')) form['typeid'] = '$typeid';
      if (price > 0 && _hasField(doc, 'price')) form['price'] = '$price';
      if (readperm > 0 && _hasField(doc, 'readperm')) form['readperm'] = '$readperm';

      if (scheduledAt != null) {
        final seconds = scheduledAt.millisecondsSinceEpoch ~/ 1000;
        if (_hasField(doc, 'cronpublish')) {
          form['cronpublish'] = '$seconds';
        } else if (_hasField(doc, 'publishdate')) {
          form['publishdate'] = '$seconds';
        }
      }

      for (final attachment in attachments) {
        form['attachnew[${attachment.aid}][description]'] = '';
        form['attachnew[${attachment.aid}][readperm]'] = '';
        form['attachnew[${attachment.aid}][price]'] = '0';
      }

      final response = await client.post(
        Uri.parse(forumUrl),
        headers: {
          ...headers,
          'Referer': forumUrl,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: form,
      ).timeout(NetClient.timeout);
      final result = NetClient.decode(response.bodyBytes);
      final resultDoc = parser.parse(result);
      final text = resultDoc.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? result;
      if (_success(resultDoc, text)) return null;
      if (text.contains('登录') || text.contains('请先登录')) return '登录状态已失效，请重新登录';
      if (text.contains('formhash') || text.contains('验证失败') || text.contains('非法请求')) return '发帖令牌已失效，请重新进入版块后再试';
      if (text.contains('权限') || text.contains('无权')) return '当前账号没有在该版块发帖的权限';
      if (text.contains('验证码')) return '论坛要求验证码，请使用网页完成验证后再发帖';
      return _firstFailure(text) ?? '发帖失败，请稍后重试';
    } catch (e) {
      return '发帖请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  /// 编辑自己已发布的主题。严格对齐网页端流程：
  /// 1) GET 编辑页拿到 formhash 与整张 `#postform` 表单(含 price/typeid/readperm/
  ///    附件配置等隐藏与回显字段);
  /// 2) 原样收集这些字段(保留原文的售价、分类、阅读权限、附件等设置);
  /// 3) 仅覆写 subject/message 并 POST 到表单指向的 action(editsubmit=yes)。
  Future<String?> editThread({
    required int tid,
    required int fid,
    required int pid,
    required String subject,
    required String message,
  }) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) return '请先登录论坛';
    final title = subject.trim();
    final body = message.trim();
    if (title.isEmpty) return '请输入标题';
    if (body.isEmpty) return '请输入正文';

    try {
      final client = await NetClient.instance.client;
      final headers = _headers();
      // GET 地址携带 fid/tid/pid 用于定位要编辑的楼层, 与网页端一致。
      final getUrl =
          '${_base}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1&mobile=2';
      final page = await NetClient.retry(() => client.get(Uri.parse(getUrl), headers: headers).timeout(NetClient.timeout));
      if (page.statusCode != 200) return '读取编辑页失败 HTTP ${page.statusCode}';
      final html = NetClient.decode(page.bodyBytes);
      final doc = parser.parse(html);
      final form = doc.querySelector('form#postform, form[id="postform"]');
      if (form == null) {
        final permText = doc.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        if (permText.contains('无权') || permText.contains('没有权限') || permText.contains('权限不足')) return '只有帖子作者可以编辑该主题';
        return '未取得编辑表单，请重新进入帖子后再试';
      }
      final formhash = NetClient.extractFormHash(html) ?? _value(doc, 'formhash');
      if (formhash.isEmpty) return '未取得编辑令牌(formhash)，请重新进入帖子后再试';

      // 沿网页端把整张表单现有字段原样带回, 保留售价/分类/权限/附件等设置。
      final fields = _collectPostForm(form);
      fields['formhash'] = formhash;
      fields['subject'] = title;
      fields['message'] = body;
      // 网页端提交按钮也是 editsubmit=yes, 强制兜底确保触发编辑提交。
      fields['editsubmit'] = 'yes';

      // POST 目标使用表单自带 action(editsubmit=yes, 不含 fid/tid/pid), 与网页端一致。
      final postUrl =
          '${_base}forum.php?mod=post&action=edit&extra=&editsubmit=yes&mobile=2';
      final response = await client.post(
        Uri.parse(postUrl),
        headers: {
          ...headers,
          'Referer': getUrl,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: fields,
      ).timeout(NetClient.timeout);
      final result = NetClient.decode(response.bodyBytes);
      final resultDoc = parser.parse(result);
      final text = resultDoc.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? result;
      if (RegExp(r'(编辑成功|保存成功|主题已(?:编辑|更新)|已(?:保存|更新))').hasMatch(text)) return null;
      if (resultDoc.querySelector('meta[http-equiv="refresh"]') != null) return null;
      if (resultDoc.querySelector('a[href*="thread-"]') != null && !text.contains('失败')) return null;
      if (text.contains('登录') || text.contains('请先登录')) return '登录状态已失效，请重新登录';
      if (text.contains('formhash') || text.contains('非法请求') || text.contains('验证失败')) return '编辑令牌已失效，请重新进入帖子后再试';
      if (text.contains('无权') || text.contains('没有权限') || text.contains('权限不足')) return '只有帖子作者可以编辑该主题';
      if (text.contains('验证码')) return '论坛要求验证码，请使用网页完成验证后再编辑';
      return _firstFailure(text) ?? '保存失败，请稍后重试';
    } catch (e) {
      return '编辑请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  /// 收集编辑表单元表单控件的当前值(隐藏/文本输入、复选框、下拉与多行文本框),
  /// 等效于浏览器随表单一起提交的内容。
  Map<String, String> _collectPostForm(dynamic form) {
    final out = <String, String>{};
    void put(String name, String value) {
      if (name.isEmpty) return;
      out[name] = value;
    }

    for (final input in form.querySelectorAll('input')) {
      if (input.attributes['disabled'] != null) continue;
      final name = input.attributes['name'] ?? '';
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (name.isEmpty || type == 'file') continue;
      if (type == 'radio' || type == 'checkbox') {
        if (input.attributes['checked'] != null) put(name, input.attributes['value'] ?? '');
      } else {
        put(name, input.attributes['value'] ?? (input.text ?? ''));
      }
    }
    for (final area in form.querySelectorAll('textarea')) {
      final name = area.attributes['name'] ?? '';
      if (name.isNotEmpty) put(name, area.text ?? '');
    }
    for (final select in form.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      String? value;
      for (final opt in select.querySelectorAll('option')) {
        if (opt.attributes['selected'] != null) {
          value = opt.attributes['value'] ?? '';
          break;
        }
      }
      value ??= select.querySelector('option')?.attributes['value'] ?? '';
      if (value != null) put(name, value);
    }
    return out;
  }

  Future<dynamic> _postPage(int fid) async {
    final client = await NetClient.instance.client;
    final url = '${_base}forum.php?mod=post&action=newthread&fid=$fid&mobile=2';
    final resp = await NetClient.retry(() => client.get(Uri.parse(url), headers: _headers()).timeout(NetClient.timeout));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return parser.parse(NetClient.decode(resp.bodyBytes));
  }

  Map<String, String> _headers() => {
    'User-Agent': NetClient.ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cache-Control': 'no-cache, no-store',
    'Pragma': 'no-cache',
    if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!,
  };

  String _value(dynamic doc, String name) => (doc.querySelector('input[name="$name"]')?.attributes['value'] ?? '').trim();
  bool _hasField(dynamic doc, String name) => doc.querySelector('[name="$name"]') != null;
  void _copyIfPresent(dynamic doc, Map<String, String> form, String name) {
    final value = _value(doc, name);
    if (value.isNotEmpty) form[name] = value;
  }
  void _setIfPresent(dynamic doc, Map<String, String> form, String name, String value) {
    if (_hasField(doc, name)) form[name] = value;
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
    const keys = ['禁止发帖', '发帖频率', '内容包含敏感词', '标题太长', '标题不能为空', '内容不能为空', '版块不存在', '附件', '售价', '定时发布'];
    for (final key in keys) {
      if (text.contains(key)) {
        if (key == '附件') return '附件未能绑定到帖子，请重新上传后再试';
        if (key == '售价') return '当前版块不允许设置该售价';
        return key;
      }
    }
    return null;
  }
}
