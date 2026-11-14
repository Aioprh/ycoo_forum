import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_service.dart';
import '../services/credential_store.dart';
import '../services/login_log.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _answerController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  bool _agreed = false;
  bool _remember = true;
  String _questionId = '0';
  String? _error;

  static const List<(String, String)> _questions = [
    ('0', '安全提问（未设置请忽略）'),
    ('1', '母亲的名字'),
    ('2', '爷爷的名字'),
    ('3', '父亲出生的城市'),
    ('4', '您其中一位老师的名字'),
    ('5', '您个人计算机的型号'),
    ('6', '您最喜欢的餐馆名称'),
    ('7', '驾驶执照最后四位数字'),
  ];

  @override
  void initState() {
    super.initState();
    _restoreSaved();
  }

  /// 回填本机记住的账号密码，免去每次登录重新输入。
  Future<void> _restoreSaved() async {
    final saved = await CredentialStore.instance.load();
    final choice = await CredentialStore.instance.rememberChoice();
    if (!mounted) return;
    setState(() {
      // 首次登录默认勾选；用户上次明确取消过则保持不勾选。
      _remember = saved != null || choice != false;
      if (saved == null) return;
      _usernameController.text = saved.username;
      _passwordController.text = saved.password;
      if (_questions.any((q) => q.$1 == saved.questionId)) {
        _questionId = saved.questionId;
        _answerController.text = saved.answer;
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    if (!_agreed) {
      setState(() => _error = '请先阅读并同意《用户协议》和《隐私声明》');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final questionId = _questionId;
    final answer = _answerController.text.trim();
    if (questionId != '0' && answer.isEmpty) {
      setState(() => _error = '请选择安全提问后填写答案');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });

    final error = await AuthService.instance.loginNative(
      _usernameController.text,
      _passwordController.text,
      questionId: questionId,
      answer: answer,
    );

    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      await _persistCredential();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = error);
    }
  }

  /// 按「记住账号密码」的勾选状态保存或清除本机凭证。
  Future<void> _persistCredential() async {
    if (_remember) {
      await CredentialStore.instance.save(SavedCredential(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        questionId: _questionId,
        answer: _answerController.text.trim(),
      ));
      LoginLog.instance.add('已记住账号密码（仅保存在本机）');
    } else {
      await CredentialStore.instance.clear();
      LoginLog.instance.add('未勾选记住账号密码，已清除本机保存的凭证');
    }
  }

  Future<void> _webFallback() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _LegacyLoginPage()));
    if (ok != true || !mounted) return;
    // 网页验证登录的账号不一定是本机记住的那个，且拿不到密码，
    // 清掉旧凭证，避免下次自动登录回错误的账号。
    await CredentialStore.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasQuestion = _questionId != '0';

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primaryContainer),
                      child: Icon(Icons.forum_rounded, size: 42, color: scheme.primary),
                    ),
                    const Text('登录源论坛', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('原生登录 · 登录后自动同步头像与个人资料', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: '用户名',
                        hintText: '请输入论坛用户名',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: hasQuestion ? TextInputAction.next : TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => hasQuestion ? FocusScope.of(context).nextFocus() : _login(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        hintText: '请输入论坛密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? '显示密码' : '隐藏密码',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _questionId,
                      decoration: InputDecoration(
                        labelText: '安全提问',
                        prefixIcon: const Icon(Icons.help_outline),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      items: _questions.map((q) => DropdownMenuItem<String>(value: q.$1, child: Text(q.$2))).toList(),
                      onChanged: _loading ? null : (value) {
                        if (value == null) return;
                        setState(() {
                          _questionId = value;
                          if (value == '0') _answerController.clear();
                        });
                      },
                    ),
                    if (hasQuestion) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _answerController,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: '答案',
                          hintText: '请输入安全提问答案',
                          prefixIcon: const Icon(Icons.edit_outlined),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest.withOpacity(.45),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                    CheckboxListTile(
                      value: _remember,
                      onChanged: _loading ? null : (v) => setState(() => _remember = v ?? false),
                      title: const Text('记住账号密码', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: const Text('下次登录自动填充，登录过期后自动重新登录', style: TextStyle(fontSize: 12)),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _loading ? null : () => setState(() => _agreed = !_agreed),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(value: _agreed, onChanged: _loading ? null : (v) => setState(() => _agreed = v ?? false)),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 11),
                                child: Text.rich(
                                  TextSpan(children: [
                                    const TextSpan(text: '阅读并同意 '),
                                    TextSpan(text: '《用户协议》', style: TextStyle(color: scheme.primary)),
                                    const TextSpan(text: ' 和 '),
                                    TextSpan(text: '《隐私声明》', style: TextStyle(color: scheme.primary)),
                                  ]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(14)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.info_outline, color: scheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _webFallback,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('需要验证码？使用网页验证'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _remember
                          ? '登录请求直接发送到源论坛。账号密码仅加密保存在本机，不会上传，取消勾选后登录即可清除。'
                          : '登录请求直接发送到源论坛，密码不会保存到应用配置或代码中。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 仅在论坛要求额外验证码/安全验证时使用的网页兜底。
class _LegacyLoginPage extends StatefulWidget {
  const _LegacyLoginPage();
  @override
  State<_LegacyLoginPage> createState() => _LegacyLoginPageState();
}

class _LegacyLoginPageState extends State<_LegacyLoginPage> {
  late final WebViewController _controller;
  bool _resolved = false;
  String _status = '请在网页中完成验证';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => _checkLogin()));
    _load();
  }

  Future<void> _load() async {
    try {
      await _controller.loadRequest(Uri.parse('${AuthService.base}${AuthService.loginPath}'));
      LoginLog.instance.add('加载网页验证登录页');
    } catch (e) {
      if (mounted) setState(() => _status = '加载失败:$e');
    }
  }

  Future<void> _checkLogin() async {
    if (_resolved) return;
    final cookies = await WebViewCookieManager().getCookies(domain: Uri.parse(AuthService.base));
    final cookieStr = cookies.where((c) => c.value.isNotEmpty).map((c) => '${c.name}=${c.value}').join('; ');
    final authed = cookies.any((c) => c.name.toLowerCase().endsWith('auth'));
    if (!authed) return;
    _resolved = true;
    await AuthService.instance.markLoggedInFromWeb('', cookieStr);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('网页验证登录')),
    body: Column(children: [
      Expanded(child: WebViewWidget(controller: _controller)),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _checkLogin, icon: const Icon(Icons.check, size: 18), label: const Text('已完成验证,返回应用')),
        ]),
      ),
    ]),
  );
}
