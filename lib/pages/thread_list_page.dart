import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/thread_item.dart';
import '../services/api_service.dart';
import '../services/site_fallback_service.dart';
import '../widgets/thread_list_view.dart';

/// 版块帖子列表页:带分页,并展示网页端的「主题分类」筛选标签。
class BoardThreadListPage extends StatefulWidget {
  final int fid;
  final String filter;

  const BoardThreadListPage({super.key, required this.fid, required this.filter});

  @override
  State<BoardThreadListPage> createState() => _BoardThreadListPageState();
}

class _BoardThreadListPageState extends State<BoardThreadListPage> {
  List<ForumTypeTag> _types = const [];
  int _typeid = 0; // 0 表示「全部」

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final tags = await ApiService.instance.fetchForumTypes(widget.fid);
      if (!mounted) return;
      setState(() => _types = tags);
    } catch (_) {
      // 无法解析分类时保持为空，帖子流仍照常显示。
    }
  }

  Future<List<ThreadItem>> _load(int page) async {
    final url = ApiService.forumUrl(widget.fid, page, typeid: _typeid);
    try {
      final primary = await ApiService.instance.fetchThreads(url);
      if (primary.isNotEmpty) return primary;
    } catch (_) {
      // 站点模板变化或请求异常时继续使用兼容解析器。
    }
    return SiteFallbackService.instance.fetchThreads(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.filter)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_types.isNotEmpty) _typeBar(context),
            Expanded(
              child: ThreadListView(
                // typeid 变化时重建，让列表按新分类重新从第 1 页加载。
                key: ValueKey<int>(_typeid),
                paginate: true,
                loader: _load,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBar(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _chip(context, 0, '全部'),
          for (final t in _types) _chip(context, t.typeid, t.name),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, int typeid, String name) {
    final selected = typeid == _typeid;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Center(child: Text(name)),
        // 去掉选中对勾，否则对勾会占据左侧空间让文字不再居中。
        showCheckmark: false,
        selected: selected,
        onSelected: (_) {
          if (typeid == _typeid) return;
          setState(() => _typeid = typeid);
        },
      ),
    );
  }
}