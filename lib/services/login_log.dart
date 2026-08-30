import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 登录诊断日志。
///
/// 记录登录各步骤的结果(HTTP 状态、解析到的令牌、成功标记、异常等),
/// 并在内存 + 本地持久化,便于登录失败后查看日志定位问题。
class LoginLog {
  LoginLog._();
  static final LoginLog instance = LoginLog._();

  static const _prefKey = 'ycoo.login.log';
  static const _maxLines = 200;

  final List<String> _lines = [];
  bool _loaded = false;

  String get text => _lines.join('\n');
  bool get isEmpty => _lines.isEmpty;

  Future<void> _ensure() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final data = sp.getString(_prefKey);
      if (data != null && data.isNotEmpty) {
        _lines.addAll(const LineSplitter().convert(data));
      }
    } catch (_) {
      // 持久化异常不影响日志使用。
    }
  }

  /// 追加一行日志(带时间戳),并裁剪到上限后持久化。会同步打印便于抓取 logcat。
  Future<void> add(String message) async {
    await _ensure();
    final line =
        '${DateTime.now().toIso8601String().split('.').first}  $message';
    // ignore: avoid_print
    print('[Login] $line');
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, _lines.join('\n'));
    } catch (_) {}
  }

  /// 清空日志。
  Future<void> clear() async {
    _loaded = true;
    _lines.clear();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefKey);
    } catch (_) {}
  }
}