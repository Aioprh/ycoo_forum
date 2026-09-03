import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/board_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'services/auth_service.dart';
import 'services/checkin_service.dart';
import 'services/site_config.dart';
import 'services/theme_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 加载站点域名配置(本地缓存 + 后台拉取远程配置)
  await SiteConfig.init();
  // 恢复用户上次选择的主题模式(亮/暗/跟随系统)
  await ThemeModeController.instance.init();
  runApp(const YcoForumApp());
}

class YcoForumApp extends StatelessWidget {
  const YcoForumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeController.instance.mode,
      builder: (context, themeMode, _) => MaterialApp(
        title: '源论坛',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(
          useMaterial3: true,
          fontFamilyFallback: const <String>[
            'Noto Sans CJK SC',
            'Noto Sans CJK TC',
            'Noto Sans CJK JP',
            'Noto Sans Symbols 2',
            'Noto Color Emoji',
            'sans-serif',
          ],
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4E6EF2),
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          fontFamilyFallback: const <String>[
            'Noto Sans CJK SC',
            'Noto Sans CJK TC',
            'Noto Sans CJK JP',
            'Noto Sans Symbols 2',
            'Noto Color Emoji',
            'sans-serif',
          ],
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4E6EF2),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: themeMode,
        home: const RootShell(),
      ),
    );
  }
}

/// 底部导航主框架:首页 / 社区 / 我的
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  static const _pages = <Widget>[
    HomePage(),
    BoardPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckIn());
  }

  Future<void> _autoCheckIn() async {
    // 先恢复本地登录会话，再执行自动签到；签到服务自身还会按本地日期限流。
    await AuthService.instance.init();
    if (!AuthService.instance.isLoggedIn) return;
    await AuthService.instance.checkLoggedIn();
    if (!AuthService.instance.isLoggedIn || !mounted) return;
    await CheckinService.instance.autoSignOncePerDay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: '社区',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
