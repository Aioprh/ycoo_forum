import 'package:flutter/material.dart';

import '../models/thread_item.dart';
import '../services/api_service.dart';
import '../services/site_fallback_service.dart';
import '../widgets/thread_list_view.dart';

/// 版块帖子列表页:带分页。
class BoardThreadListPage extends StatelessWidget {
  final int fid;
  final String filter;

  const BoardThreadListPage({
    super.key,
    required this.fid,
    required this.filter,
  });

  Future<List<ThreadItem>> _load(int page) async {
    final url = ApiService.forumUrl(fid, page);
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
      appBar: AppBar(title: Text(filter)),
      body: SafeArea(
        top: false,
        child: ThreadListView(paginate: true, loader: _load),
      ),
    );
  }
}
