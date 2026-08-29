import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/login_log.dart';

/// 原生登录页:与 Discuz!X 站点通过 AuthService 直接交互,不依赖 WebView。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  bool _showLog = false;
  String _logs = '';

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshLogs() async {
    final t = LoginLog.instance.text;
    if (mounted) setState(() => _logs = t);
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _logs));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('诊断日志已复制')),
    );
  }

  Future<void> _clearLogs() async {
    await LoginLog.instance.clear();
    await _refreshLogs();
  }

  Future<void> _submit() async {
    final account = _accountCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await AuthService.instance.login(account, password);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() =>
            _error = AuthService.instance.lastError ?? '登录失败,请稍后重试');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '登录失败:$e');
    } finally {
      if (mounted) {
        await _refreshLogs();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.forum_outlined,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              '源论坛',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '登录后可回帖、发帖、打卡、评分等',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _accountCtrl,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
            const SizedBox(height: 12),
            Text(
              '如账号启用了安全提问或验证码,请到网页端登录',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            // 登录失败诊断日志入口(可展开查看 / 复制)。
            TextButton.icon(
              onPressed: () => setState(() => _showLog = !_showLog),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(_showLog ? '收起诊断日志' : '查看登录诊断日志'),
            ),
            if (_showLog) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('共 ${_logs.split('\n').where((l) => l.trim().isNotEmpty).length} 条',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _logs.isEmpty ? null : _copyLogs,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                  ),
                  TextButton.icon(
                    onPressed: _clearLogs,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 300),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _logs.isEmpty ? '(暂无日志:登录后自动生成)' : _logs,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}