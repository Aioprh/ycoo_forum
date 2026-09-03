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
  final bool addfeed;

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
    this.addfeed = true,
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
    int? selectedInt(String name) {
      final option = form.querySelector('select[name="$name"] option[selected]');
      return int.tryParse(option?.attributes['value'] ?? '');
    }
    return ThreadEditData(
      subject: value('subject'),
      message: value('message'),
      typeid: selectedInt('typeid'),
      price: intValue('price'),
      readperm: intValue('readperm'),
      usesig: checked('usesig', fallback: true),
      allownoticeauthor: checked('allownoticeauthor', fallback: true),
      hiddenreplies: checked('hiddenreplies'),
      descviewdefault: checked('descviewdefault') || value('ordertype') == '1',
      addfeed: checked('addfeed', fallback: true),
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
    bool? addfeed,
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
      if (typeid != null) fields['typeid'] = '$typeid';
      if (price != null) fields['price'] = '$price';
      if (readperm != null) fields['readperm'] = '$readperm';
      if (usesig != null) fields['usesig'] = usesig ? '1' : '0';
      if (allownoticeauthor != null) fields['allownoticeauthor'] = allownoticeauthor ? '1' : '0';
      if (hiddenreplies != null) fields['hiddenreplies'] = hiddenreplies ? '1' : '0';
      if (descviewdefault != null) {
        fields['descviewdefault'] = descviewdefault ? '1' : '0';
        if (fields.containsKey('ordertype')) fields['ordertype'] = descviewdefault ? '1' : '0';
      }
      if (addfeed != null) fields['addfeed'] = addfeed ? '1' : '0';

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
      final result = NetClient.decode(response.bodyBytes);
      final resultDoc = parser.parse(result);
      final text = _plain(resultDoc);
      if (_isSuccess(resultDoc, text)) return null;
      if (_looksLikeLogin(text)) return '登录状态已失效，请重新登录';
      if (text.contains('formhash') || text.contains('非法请求') || text.contains('验证失败')) return '编辑令牌已失效，请重新进入帖子后再试';
      if (_looksLikePermission(text)) return '只有帖子作者可以编辑该主题';
      if (text.contains('验证码')) return '论坛要求验证码，请使用网页完成验证后再编辑';
      return _firstFailure(text) ?? '保存失败：论坛未返回成功结果';
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
      final selected = select.querySelector('option[selected]') ?? select.querySelector('option');
      if (selected != null) put(name, selected.attributes['value'] ?? '');
    }
    return out;
  }

  String _plain(dynamic doc) => (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  bool _looksLikeLogin(String text) => text.contains('请登录') || text.contains('登录后') || text.contains('请先登录');
  bool _looksLikePermission(String text) => text.contains('无权') || text.contains('没有权限') || text.contains('权限不足');
  bool _isSuccess(dynamic doc, String text) {
    if (RegExp(r'(编辑成功|保存成功|主题已(?:编辑|更新)|已(?:保存|更新))').hasMatch(text)) return true;
    if (doc.querySelector('meta[http-equiv="refresh"]') != null) return true;
    final redirect = doc.querySelector('a[href*="thread-"]');
    return redirect != null && !text.contains('失败');
  }
  String? _firstFailure(String text) {
    const keys = <String>['禁止编辑', '编辑失败', '内容包含敏感词', '操作失败', '帖子不存在', '主题不存在', '标题不能为空', '内容不能为空'];
    for (final key in keys) {
      if (text.contains(key)) return key;
    }
    return null;
  }
}
