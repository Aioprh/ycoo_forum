import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/thread_list_view.dart';

/// 版块帖子列表页:带分页。
class BoardThreadListPage extends StatelessWidget {
  final int fid;
  final String filter;

  const BoardThreadListPage({super.key, required this.fid, required this.filter});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(filter)),
      body: SafeArea(
        top: false,
        child: ThreadListView(
          paginate: true,
          loader: (page) => ApiService.instance.fetchThreads(
            ApiService.forumUrl(fid, page),
          ),
        ),
      ),
    );
  }
}