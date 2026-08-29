import 'package:flutter/material.dart';

import 'webview_page.dart';

/// 搜索页:打开原站移动端搜索(该站搜索需表单校验,封装为内置 WebView)。
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  static const String _searchUrl =
      'https://www.ycoo.net/search.php?mod=forum&mobile=2';

  @override
  Widget build(BuildContext context) {
    return const WebViewPage(url: _searchUrl, title: '搜索');
  }
}