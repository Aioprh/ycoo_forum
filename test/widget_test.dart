import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ycoo_forum/main.dart';

/// 测试环境无网络:首页/社区页在 initState 即发起 http 请求,
/// 这里让所有 HTTP 请求立即失败,避免挂起与 20s 超时定时器残留导致测试失败。
class _NoNetOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _NoNetClient();
}

class _NoNetClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation inv) {
    // 配置项赋值、close 等只需透传忽略;真正发起请求的方法则直接抛错。
    switch (inv.memberName) {
      case #close:
      case #userAgent:
      case #idleTimeout:
      case #autoUncompress:
      case #connectionTimeout:
        return null;
    }
    throw const SocketException('网络已在测试中被禁用');
  }
}

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // 在 binding 初始化后再覆盖,确保 HomePage/社区页的网络请求立即失败。
    HttpOverrides.global = _NoNetOverrides();
    await tester.pumpWidget(const YcoForumApp());
    await tester.pump();

    // 底部导航三大功能区
    expect(find.text('首页'), findsWidgets);
    expect(find.text('社区'), findsOneWidget);
    expect(find.text('我的'), findsWidgets);
  });
}