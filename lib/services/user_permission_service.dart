import 'dart:io';
import 'dart:convert';

import 'package:html/parser.dart' as parser;

import 'attachment_upload_service.dart';
import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// 用户等级/权限管理器。
/// 源论坛在 home.php?mod=spacecp&ac=usergroup 页面会渲染完整权限表:
/// 阅读权限、隐身、发帖限制、附件大小、签名长度、允许 @ 人数 等 50+ 项。
/// 同时从发帖页解析"单个最大附件尺寸"(有时与 usergroup 页面不一致, 以发帖页为准)。
class UserPermissionService {
  UserPermissionService._();
  static final instance = UserPermissionService._();

  static String get _base => SiteConfig.base;

  // ===== 缓存 =====
  static int _cachedUid = 0;
  static int _maxAttachBytes = 10 * 1024 * 1024; // 默认 10MB
  static int _maxImageBytes = 10 * 1024 * 1024;

  /// 最大附件尺寸(bytes), 供 AttachmentUploadService 和 UI 使用
  static int get maxAttachBytes => _maxAttachBytes;

  /// 最大单图尺寸(bytes)
  static int get maxImageBytes => _maxImageBytes;

  /// 当前缓存对应的 uid, 换用户时自动清空
  static int get cachedUid => _cachedUid;

  /// 换账号/登出时调, 清所有缓存
  static void resetCache() {
    _cachedUid = 0;
    _maxAttachBytes = 10 * 1024 * 1024;
    _maxImageBytes = 10 * 1024 * 1024;
    _cachedPermission = null;
    AttachmentUploadService.updateMaxBytes(_maxAttachBytes);
  }

  static String _formatMb(int bytes) {
    final mb = bytes / 1024 / 1024;
    return mb == mb.truncateToDouble() ? '${mb.toInt()} MB' : '${mb.toStringAsFixed(1)} MB';
  }

  static String get maxAttachLabel => _formatMb(_maxAttachBytes);
  static String get maxImageLabel => _formatMb(_maxImageBytes);

  // ===== 完整权限对象 =====
  static UserPermission? _cachedPermission;
  UserPermission? get current => _cachedPermission;

  /// 抓 usergroup 页面 + 发帖页, 解析所有权限。
  /// 发帖页优先解析附件大小(有时比 usergroup 更准)。
  Future<UserPermission?> refresh() async {
    final myUid = AuthService.instance.uid ?? 0;
    if (myUid <= 0) return null;
    if (_cachedUid == myUid && _cachedPermission != null) return _cachedPermission;

    try {
      final client = await NetClient.instance.client;
      final headers = <String, String>{
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': _base,
        if ((AuthService.instance.authCookie ?? '').isNotEmpty) 'Cookie': AuthService.instance.authCookie!,
      };

      // 1. 抓等级说明页, 拿全部权限
      final groupResp = await NetClient.retry(
        () => client.get(Uri.parse('${_base}home.php?mod=spacecp&ac=usergroup&mobile=2'), headers: headers),
      ).timeout(NetClient.timeout);

      if (groupResp.statusCode == 200) {
        final groupHtml = NetClient.decode(groupResp.bodyBytes);
        final perm = _parsePermission(groupHtml);
        if (perm != null) {
          // 发帖页的附件大小优先
          await _fetchAttachLimitFromNewthread(client, headers);
          perm.maxAttachBytes = _maxAttachBytes;
          _cachedPermission = perm;
          _cachedUid = myUid;
          return perm;
        }
      }
    } catch (_) {}
    return _cachedPermission;
  }

  /// 从发帖页再补一遍附件限制 (有时比 usergroup 更准)
  Future<void> _fetchAttachLimitFromNewthread(dynamic client, Map<String, String> headers) async {
    try {
      // 用 fid=2 (书源发布) 试, 换版块不影响附件大小
      final resp = await client.get(
        Uri.parse('${_base}forum.php?mod=post&action=newthread&fid=2&mobile=2'),
        headers: headers,
      ).timeout(NetClient.timeout);
      if (resp.statusCode != 200) return;
      final html = NetClient.decode(resp.bodyBytes);
      final parsed = AttachmentUploadService.parseMaxSizeFromHtml(html);
      if (parsed > 0) _maxAttachBytes = parsed;
    } catch (_) {}
  }

  /// 从等级说明页 HTML 解析权限表
  static UserPermission? _parsePermission(String html) {
    if (html.trim().isEmpty) return null;
    final doc = parser.parse(html);

    String levelName = '';
    String userLevel = '';
    int? points;
    int? readPerm;

    // 等级名: "我的等级: 举人"
    final levelMatch = RegExp(r'我的等级\s*[:：]\s*([^\n<]+)').firstMatch(html);
    if (levelMatch != null) levelName = levelMatch.group(1)!.trim();

    // 用户级别: Lv.N
    final userLevelMatch = RegExp(r'用户级别\s*[:：]\s*([^\n<]+)').firstMatch(html);
    if (userLevelMatch != null) userLevel = userLevelMatch.group(1)!.trim();

    // 积分
    final pointsMatch = RegExp(r'<th>积分</th>\s*<td>\s*(\d+)\s*</td>').firstMatch(html);
    if (pointsMatch != null) points = int.tryParse(pointsMatch.group(1)!);

    // 读权限表 <th>xxx</th><td>yyy</td>
    final pairs = RegExp(
      r'<th>([^<]+)</th>\s*<td>(.*?)</td>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html).toList();

    String readPermStr = '';
    String? maxAttachStr;
    String? maxImageStr;
    String? maxDailyAttachBytes;
    String? maxDailyAttachCount;
    String? maxSignatureLen;
    String maxAtCount = '';
    String spaceSize = '';
    final permissionMap = <String, String>{};

    for (final m in pairs) {
      final name = m.group(1)!.trim();
      var val = m.group(2) ?? '';
      val = val.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      permissionMap[name] = val;

      switch (name) {
        case '阅读权限':
          readPermStr = val;
        case '单个最大附件尺寸':
          maxAttachStr = val;
        case '单张图片最大尺寸':
          maxImageStr = val;
        case '每天最大附件总尺寸':
          maxDailyAttachBytes = val;
        case '每天最大附件数量':
          maxDailyAttachCount = val;
        case '最大签名长度':
          maxSignatureLen = val;
        case '允许 @ 的人数':
          maxAtCount = val;
        case '空间大小':
          spaceSize = val;
      }
    }

    readPerm = int.tryParse(readPermStr);

    // 解析 MB / KB / 字节
    int? parseSize(String? s) {
      if (s == null || s.isEmpty) return null;
      if (s == '没有限制') return -1;
      final mb = RegExp(r'(\d+(?:\.\d+)?)\s*MB', caseSensitive: false).firstMatch(s);
      if (mb != null) return (double.parse(mb.group(1)!) * 1024 * 1024).round();
      final kb = RegExp(r'(\d+(?:\.\d+)?)\s*KB', caseSensitive: false).firstMatch(s);
      if (kb != null) return (double.parse(kb.group(1)!) * 1024).round();
      final bytes = RegExp(r'(\d+)\s*字节').firstMatch(s);
      if (bytes != null) return int.parse(bytes.group(1)!);
      final plain = int.tryParse(s.trim());
      if (plain != null) return plain;
      return null;
    }

    final maxAttach = parseSize(maxAttachStr);
    if (maxAttach != null && maxAttach > 0) _maxAttachBytes = maxAttach;
    final maxImg = parseSize(maxImageStr);
    if (maxImg != null && maxImg > 0) _maxImageBytes = maxImg;

    // 回写到 AttachmentUploadService, 让发帖页 UI 直接读
    AttachmentUploadService.updateMaxBytes(_maxAttachBytes);

    return UserPermission(
      levelName: levelName,
      userLevel: userLevel,
      points: points,
      readPerm: readPerm,
      maxAttachBytes: _maxAttachBytes,
      maxImageBytes: _maxImageBytes,
      maxDailyAttachBytes: maxDailyAttachBytes ?? '',
      maxDailyAttachCount: maxDailyAttachCount ?? '',
      maxSignatureLen: maxSignatureLen ?? '',
      maxAtCount: maxAtCount,
      spaceSize: spaceSize,
      raw: permissionMap,
    );
  }
}

/// 用户权限快照
class UserPermission {
  final String levelName; // 如 "举人"
  final String userLevel; // 如 "Lv.3"
  final int? points;
  final int? readPerm;
  int maxAttachBytes;
  final int maxImageBytes;
  final String maxDailyAttachBytes; // 如 "没有限制" 或 "50 MB"
  final String maxDailyAttachCount;
  final String maxSignatureLen; // 如 "80 字节"
  final String maxAtCount;
  final String spaceSize;
  final Map<String, String> raw; // 完整原始权限表

  UserPermission({
    required this.levelName,
    required this.userLevel,
    required this.points,
    required this.readPerm,
    required this.maxAttachBytes,
    required this.maxImageBytes,
    required this.maxDailyAttachBytes,
    required this.maxDailyAttachCount,
    required this.maxSignatureLen,
    required this.maxAtCount,
    required this.spaceSize,
    required this.raw,
  });

  String get maxAttachLabel {
    final mb = maxAttachBytes / 1024 / 1024;
    return mb == mb.truncateToDouble() ? '${mb.toInt()} MB' : '${mb.toStringAsFixed(1)} MB';
  }

  String get maxImageLabel {
    final mb = maxImageBytes / 1024 / 1024;
    return mb == mb.truncateToDouble() ? '${mb.toInt()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
}
