import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/thread_list_view.dart';
import 'search_page.dart';

/// 首页:最新发表 / 最新回复 / 热点推荐 / 社区热门 四个导读流。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 「热点推荐(hot)」与站点首页 feed 一样由 JS 动态加载,无静态内容,故去掉。
  static const _tabs = <(String, String)>[
    ('最新发表', 'newthread'),
    ('最新回复', 'newreply'),
    ('社区热门', 'digest'),
  ];
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final view = _tabs[_index].$2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('源论坛'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < _tabs.length; i++)
                      ButtonSegment(
                        value: i,
                        label: Text(_tabs[i].$1),
                      ),
                  ],
                  selected: {_index},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
                  ),
                  onSelectionChanged: (s) =>
                      setState(() => _index = s.first),
                ),
              ),
            ),
            Expanded(
              child: ThreadListView(
                // 导读为单页流,不翻页,切换 Tab 用 key 重建。
                key: ValueKey(view),
                paginate: false,
                loader: (_) =>
                    ApiService.instance.fetchThreads(ApiService.guideUrl(view)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}