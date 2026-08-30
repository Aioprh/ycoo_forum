import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地发帖草稿：只保存文本和发帖选项，不保存附件文件本身。
class PostDraft {
  final String title;
  final String body;
  final int? fid;
  final int? typeid;
  final int price;
  final int readperm;
  final bool usesig;
  final bool allownoticeauthor;

  const PostDraft({
    required this.title,
    required this.body,
    required this.fid,
    required this.typeid,
    required this.price,
    required this.readperm,
    required this.usesig,
    required this.allownoticeauthor,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'fid': fid,
        'typeid': typeid,
        'price': price,
        'readperm': readperm,
        'usesig': usesig,
        'allownoticeauthor': allownoticeauthor,
      };

  factory PostDraft.fromJson(Map<String, dynamic> json) => PostDraft(
        title: '${json['title'] ?? ''}',
        body: '${json['body'] ?? ''}',
        fid: int.tryParse('${json['fid'] ?? ''}'),
        typeid: int.tryParse('${json['typeid'] ?? ''}'),
        price: int.tryParse('${json['price'] ?? 0}') ?? 0,
        readperm: int.tryParse('${json['readperm'] ?? 0}') ?? 0,
        usesig: json['usesig'] != false,
        allownoticeauthor: json['allownoticeauthor'] != false,
      );
}

class PostDraftService {
  PostDraftService._();
  static final instance = PostDraftService._();
  static const _key = 'create_thread_draft_v1';

  Future<void> save(PostDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  Future<PostDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return PostDraft.fromJson(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
