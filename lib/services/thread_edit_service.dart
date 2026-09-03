import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

class ThreadEditData {
  final String subject;
  final String message;
  final int? typeid;
  final int price;
  final int readperm;
  final bool usesig;
  final bool allownoticeauthor;
  final bool hiddenreplies;
  final bool descviewdefault;

  const ThreadEditData({
    required this.subject,
    required this.message,
    this.typeid,
    this.price = 0,
    this.readperm = 0,
    this.usesig = true,
    this.allownoticeauthor = true,
    this.hiddenreplies = false,
    this.descviewdefault = false,
  });
}

/// Discuz 主题编辑：先读取真实编辑表单，再按网页端 form action 提交。
class ThreadEditService {
  ThreadEditService._();
  static final instance = ThreadEditService._();
  static String get _base => SiteConfig.base;

  Map<String, String> _headers() => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
        if ((AuthService.instance.authCookie ?? '').isNotEmpty)
          'Cookie': AuthService.instance.authCookie!,
      };

  Uri _editUrl(int tid, int fid, int pid) => Uri.parse(
        '${_base}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1&mobile=2',
      );

  Future<(dynamic, Uri)?> _loadForm(int tid, int fid, int pid) async {
    final client = await NetClient.instance.client;
    final url = _editUrl(tid, fid, pid);
    final response = await NetClient.retry(
      () => client.get(url, headers: _headers()).timeout(NetClient.timeout),
    );
    if (response.statusCode != 200) return null;
    final doc = parser.parse(NetClient.decode(response.bodyBytes));
    final form = doc.querySelector('form#postform') ??
        doc.querySelector('form[name="postform"]') ??
        doc.querySelector('form');
    if (form == null) return null;
    return (form, url);
  }

  Future<ThreadEditData?> loadEditData({
    required int tid,
    required int fid,
    required int pid,
  }) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) {
      throw Exception('请先登录论坛');
    }
    final loaded = await _loadForm(tid, fid, pid);
    if (loaded == null) throw Exception('未取得网页编辑表单，请确认你是帖子作者并重新进入帖子');
    final form = loaded.$1;
    String value(String name) {
      final input = form.querySelector('input[name="$name"]');
      if (input != null) return (input.attributes['value'] ?? '').trim();
      final area = form.querySelector('textarea[name="$name"]');
      return area?.text.trim() ?? '';
    }
    int intValue(String name) => int.tryParse(value(name)) ?? 0;
    bool checked(String name, {bool fallback = false}) =>
        form.querySelector('input[name="$name"][checked]') != null ? true : fallback;
    // Comiis 移动模板会把“请选择”(value=0) 与真实分类同时标记为 selected，
    // 浏览器实际提交的是最后一个 selected 选项，这里也取最后一个且 value>0 的分类。
    int? selectedTypeId() {
      final options = form.querySelectorAll('select[name="typeid"] option[selected]');
      if (options.isEmpty) return null;
      final id = int.tryParse(options.last.attributes['value'] ?? '');
      return (id != null && id > 0) ? id : null;
    }
    // 阅读权限在编辑表单里是 <select> 而非 input；没有选中任何 option 表示“不限”(0)。
    int readperm = 0;
    final readpermSelect = form.querySelector('select[name="readperm"]');
    final readpermSelected = readpermSelect?.querySelector('option[selected]');
    if (readpermSelected != null) {
      readperm = int.tryParse(readpermSelected.attributes['value'] ?? '') ?? 0;
    }
    final typeId = selectedTypeId();
    return ThreadEditData(
      subject: value('subject'),
      message: value('message'),
      typeid: typeId,
      price: intValue('price'),
      readperm: readperm,
      usesig: checked('usesig', fallback: true),
      allownoticeauthor: checked('allownoticeauthor', fallback: true),
      hiddenreplies: checked('hiddenreplies'),
      // Discuz 编辑表单里“倒序排列”是 name=ordertype 的复选框，
      // 不能用 value('ordertype')（复选框 value 恒为 "1"，无论是否勾选）。
      descviewdefault: checked('ordertype'),
    );
  }

  Future<String?> editThread({
    required int tid,
    required int fid,
    required int pid,
    required String subject,
    required String message,
    int? typeid,
    int? price,
    int? readperm,
    bool? usesig,
    bool? allownoticeauthor,
    bool? hiddenreplies,
    bool? descviewdefault,
  }) async {
    if (!AuthService.instance.isLoggedIn || (AuthService.instance.authCookie ?? '').isEmpty) return '请先登录论坛';
    final title = subject.trim();
    final body = message.trim();
    if (title.isEmpty) return '请输入标题';
    if (title.length > 100) return '标题不能超过 100 个字符';
    if (body.isEmpty) return '请输入正文';

    try {
      final client = await NetClient.instance.client;
      final loaded = await _loadForm(tid, fid, pid);
      if (loaded == null) return '未取得网页编辑表单，请确认你是帖子作者并重新进入帖子';
      final form = loaded.$1;
      final editUrl = loaded.$2;
      final fields = _collectForm(form);
      final html = form.outerHtml;
      final formhash = NetClient.extractFormHash(html) ??
          (form.querySelector('input[name="formhash"]')?.attributes['value'] ?? '').trim();
      if (formhash.isEmpty) return '未取得编辑令牌(formhash)，请重新进入帖子后再试';

      fields['formhash'] = formhash;
      fields['fid'] = '$fid';
      fields['tid'] = '$tid';
      fields['pid'] = '$pid';
      fields['subject'] = title;
      fields['message'] = body;
      fields['editsubmit'] = 'yes';
      if (typeid != null && typeid > 0) fields['typeid'] = '$typeid';
      if (price != null) fields['price'] = '$price';
      if (readperm != null) fields['readperm'] = readperm == 0 ? '' : '$readperm';
      // Discuz 用 isset($_POST[...]) 判断复选框：勾选才随表单提交，
      // 未勾选必须完全不带该字段(提交 =0 也会被 isset 判为勾选, 导致无法取消)。
      if (usesig != null) _setCheckbox(fields, 'usesig', usesig);
      if (allownoticeauthor != null) _setCheckbox(fields, 'allownoticeauthor', allownoticeauthor);
      if (hiddenreplies != null) _setCheckbox(fields, 'hiddenreplies', hiddenreplies);
      // 编辑表单里“回帖倒序排列”的字段名是 ordertype(无 descviewdefault)。
      if (descviewdefault != null) _setCheckbox(fields, 'ordertype', descviewdefault);

      final action = (form.attributes['action'] ?? '').trim();
      Uri postUrl = editUrl;
      if (action.isNotEmpty) {
        final parsed = Uri.tryParse(action);
        if (parsed != null) postUrl = parsed.hasScheme ? parsed : editUrl.resolveUri(parsed);
      }
      final query = Map<String, String>.from(postUrl.queryParameters);
      query['editsubmit'] = 'yes';
      query.putIfAbsent('fid', () => '$fid');
      query.putIfAbsent('tid', () => '$tid');
      query.putIfAbsent('pid', () => '$pid');
      postUrl = postUrl.replace(queryParameters: query);

      final response = await client.post(
        postUrl,
        headers: {
          ..._headers(),
          'Referer': editUrl.toString(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: fields,
      ).timeout(NetClient.timeout);
      final status = response.statusCode;
      final location = (response.headers['location'] ?? '').toLowerCase();
      final result = NetClient.decode(response.bodyBytes);
      final resultDoc = parser.parse(result);
      final text = _plain(resultDoc);
      if (_isSuccess(resultDoc, text, result, status: status, location: location)) return null;
      if (_looksLikeLogin(text)) return '登录状态已失效，请重新登录';
      if (text.contains('formhash') || text.contains('非法请求') || text.contains('验证失败')) return '编辑令牌已失效，请重新进入帖子后再试';
      if (_looksLikePermission(text)) return '只有帖子作者可以编辑该主题';
      if (text.contains('验证码')) return '论坛要求验证码，请使用网页完成验证后再编辑';
      return _firstFailure(text) ?? _extractErrorLabel(text) ?? '保存失败：论坛未返回成功结果';
    } catch (e) {
      return '编辑请求失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  /// 复选框按 Discuz 语义写入表单字段：勾选 → 值为 "1"；未勾选 → 移除字段。
  void _setCheckbox(Map<String, String> fields, String name, bool value) {
    if (value) {
      fields[name] = '1';
    } else {
      fields.remove(name);
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
        if (input.attributes['checked'] != null) put(name, input.attributes['value'] ?? 'on');
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
      // 与浏览器一致：存在多个 selected 时取最后一个
      // (Comiis 模板的 typeid 会同时标记“请选择”和真实分类)。
      final selectedOptions = select.querySelectorAll('option[selected]');
      final selected = selectedOptions.isNotEmpty
          ? selectedOptions.last
          : select.querySelector('option');
      if (selected != null) put(name, selected.attributes['value'] ?? '');
    }
    return out;
  }

  String _plain(dynamic doc) => (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  bool _looksLikeLogin(String text) => text.contains('请登录') || text.contains('登录后') || text.contains('请先登录');
  bool _looksLikePermission(String text) => text.contains('无权') || text.contains('没有权限') || text.contains('权限不足');
  bool _isSuccess(dynamic doc, String text, [String? raw, int? status, String? location]) {
    // 0) 服务端成功后常直接 3xx 跳转到 viewthread(响应体为空)。
    //    跨平台(非 Android 的 IOClient 可能不跟随重定向)时靠 Location 兜底判定成功。
    if (status != null && status >= 300 && status < 400) {
      final loc = (location ?? '').toLowerCase();
      return loc.contains('viewthread') && !loc.contains('action=edit');
    }

    // 1) 明确成功提示。
    if (RegExp(r'(编辑成功|保存成功|主题已(?:编辑|更新)|已(?:保存|更新))').hasMatch(text)) return true;

    // 2) meta refresh 跳转。
    dynamic refresh;
    for (final meta in doc.querySelectorAll('meta')) {
      if ((meta.attributes['http-equiv'] ?? '').toLowerCase() == 'refresh') {
        refresh = meta;
        break;
      }
    }
    if (refresh != null) {
      final url = (refresh.attributes['content'] ?? '').toLowerCase();
      // 若被跳回 action=edit 编辑页，视为失败。
      if (url.contains('action=edit')) return false;
      return !text.contains('抱歉') && !text.contains('失败');
    }

    // 3) 移动端常以 JS 跳转到 viewthread 表示成功。
    final full = raw ?? text;
    if (RegExp(r'''location(?:\.href)?\s*=\s*["'][^"']*viewthread[^"']*["']''').hasMatch(full)) {
      return !text.contains('抱歉');
    }

    // 4) 服务端又重新渲染出编辑表单(编辑被打回) → 一定是失败。
    if (doc.querySelector('form#postform, form[name="postform"], textarea[name="message"]') != null) {
      return false;
    }

    // 5) 兼容仅返回主题页节点的情况。返回页带“返回主题”链接常见于失败后重新渲染，
    //    因此必须排除 失败/抱歉/来路 等关键词，避免把打回误判为成功。
    final redirect = doc.querySelector('a[href*="thread-"]');
    return redirect != null && !text.contains('失败') && !text.contains('抱歉') && !text.contains('来路');
  }
  String? _extractErrorLabel(String text) {
    final match = RegExp(r'(?:抱歉|错误|无标题)[，,、:]?[\s\S]{0,48}?[。;；]').firstMatch(text);
    return match?.group(0)?.trim();
  }
  String? _firstFailure(String text) {
    const keys = <String>['禁止编辑', '编辑失败', '内容包含敏感词', '操作失败', '帖子不存在', '主题不存在', '标题不能为空', '内容不能为空', '不能为空'];
    for (final key in keys) {
      if (text.contains(key)) return key;
    }
    return null;
  }
}
