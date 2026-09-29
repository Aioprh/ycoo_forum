import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一条帖子浏览记录。
class BrowseHistoryEntry {
  final int tid;
  final String title;
  final String boardName; // 所属版块名, 可能为空
  final DateTime time;

  const BrowseHistoryEntry({required this.tid, required this.title, required this.boardName, required this.time});

  Map<String, dynamic> toJson() => {'tid': tid, 'title': title, 'board': boardName, 'time': time.millisecondsSinceEpoch};

  static BrowseHistoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tid = raw['tid'];
    if (tid is! int || tid <= 0) return null;
    final ms = raw['time'];
    return BrowseHistoryEntry(
      tid: tid,
      title: (raw['title'] as String? ?? '').trim(),
      boardName: (raw['board'] as String? ?? '').trim(),
      time: DateTime.fromMillisecondsSinceEpoch(ms is int ? ms : 0),
    );
  }
}

/// 帖子浏览历史, 仅保存在本机(与站点账号无关)。
///
/// 打开帖子详情成功后写入一条记录; 同一帖子只保留最新一条并置顶。
class BrowseHistoryService {
  BrowseHistoryService._();
  static final BrowseHistoryService instance = BrowseHistoryService._();

  static const _prefKey = 'ycoo.browse.history';
  static const _maxEntries = 200;

  final List<BrowseHistoryEntry> _entries = [];
  bool _loaded = false;

  Future<void> _ensure() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final data = sp.getString(_prefKey);
      if (data == null || data.isEmpty) return;
      final list = jsonDecode(data);
      if (list is! List) return;
      for (final raw in list) {
        final entry = BrowseHistoryEntry.fromJson(raw);
        if (entry != null) _entries.add(entry);
      }
    } catch (_) {
      // 持久化异常不影响历史功能。
    }
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// 按浏览时间倒序返回全部记录。
  Future<List<BrowseHistoryEntry>> list() async {
    await _ensure();
    return List.unmodifiable(_entries);
  }

  /// 记录一次浏览。同一帖子去重后置顶, 超过上限则丢弃最早的记录。
  Future<void> record({required int tid, required String title, String boardName = ''}) async {
    if (tid <= 0) return;
    await _ensure();
    _entries.removeWhere((e) => e.tid == tid);
    _entries.insert(
      0,
      BrowseHistoryEntry(tid: tid, title: title.trim(), boardName: boardName.trim(), time: DateTime.now()),
    );
    if (_entries.length > _maxEntries) _entries.removeRange(_maxEntries, _entries.length);
    await _save();
  }

  Future<void> remove(int tid) async {
    await _ensure();
    final before = _entries.length;
    _entries.removeWhere((e) => e.tid == tid);
    if (_entries.length != before) await _save();
  }

  Future<void> clear() async {
    await _ensure();
    _entries.clear();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefKey);
    } catch (_) {}
  }
}