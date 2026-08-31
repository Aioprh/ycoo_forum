import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/board_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YcoForumApp());
}

class YcoForumApp extends StatelessWidget {
  const YcoForumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '源论坛',
      debugShowCheckedModeBanner: false,
      // 中文本地化：让文本选择菜单(复制/全选等)显示中文
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        useMaterial3: true,
        // Android 系统 CJK/Emoji fallback，避免网页中文、扩展汉字和符号
        // 因默认字体缺少 glyph 而显示成“方框 X”。
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
      home: const RootShell(),
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
