import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局主题模式(亮/暗/跟随系统)控制器。
///
/// 用户的选择持久化到本地, 启动时恢复; 通过 [mode] ValueNotifier 通知
/// MaterialApp 重建主题。
class ThemeModeController {
  ThemeModeController._();

  static final ThemeModeController instance = ThemeModeController._();

  static const String _prefKey = 'theme_mode';

  /// 当前主题模式(默认跟随系统)。
  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// 应用启动时调用: 从本地恢复用户上次的选择。
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefKey);
      mode.value = switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (err) {
      debugPrint('ThemeModeController: 读取失败 $err');
    }
  }

  /// 设置主题模式并持久化。
  Future<void> set(ThemeMode value) async {
    if (mode.value == value) return;
    mode.value = value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _prefKey,
        switch (value) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
    } catch (err) {
      debugPrint('ThemeModeController: 保存失败 $err');
    }
  }
}
