import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 全局站点域名配置。
///
/// 正常运行使用编译期默认域名; 应用启动时从远程配置(存放在本项目仓库中,
/// 与站点域名解耦, 天然稳定)拉取最新域名并缓存到本地, 实现:
/// "站点更换域名后, 无需重新发包, 已安装的旧版本也能自动跟随新域名"。
/// 远程拉取失败时回退: 远程 -> 本地缓存 -> 编译期默认域名。
class SiteConfig {
  SiteConfig._();

  /// 编译期默认域名(最终兜底)。
  static const String defaultBase = 'https://www.ycoo.net';

  /// 远程域名配置地址。放在本仓库, 与站点域名无关, 位置恒定。
  static const String remoteConfigUrl =
      'https://raw.githubusercontent.com/Aioprh/ycoo_forum/main/config/site.json';

  static const String _prefKey = 'site_base';

  /// 当前生效的域名(带尾部 `/`)。
  static String? _current;

  /// 当前使用的站点基址(带尾部 `/`), 会随远程配置更新而变更。
  static String get base => _current ?? '$defaultBase/';

  /// 把相对路径 / 网址统一解析为基于当前域名的绝对地址。
  static String resolve(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final prefix = _current ?? '$defaultBase/';
    return prefix + v.replaceFirst(RegExp(r'^/'), '');
  }

  /// 应用启动时调用: 先加载本地缓存, 再后台尝试拉取远程配置(不阻塞启动)。
  static Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(_prefKey);
      if (cached != null && cached.trim().isNotEmpty) _set(cached);
    } catch (err) {
      debugPrint('SiteConfig: 读取本地缓存失败 $err');
    }
    unawaited(_refreshRemote());
  }

  static Future<void> _refreshRemote() async {
    try {
      final resp = await http
          .get(Uri.parse(remoteConfigUrl))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      if (data is! Map) return;
      final base = (data['base'] as String?)?.trim();
      if (base == null || base.isEmpty || !_looksLikeHttp(base)) return;
      _set(base);
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, _current!);
      debugPrint('SiteConfig: 已更新域名为 $_current');
    } catch (err) {
      debugPrint('SiteConfig: 拉取远程配置失败, 继续使用当前域名 ($err)');
    }
  }

  static bool _looksLikeHttp(String s) {
    final u = Uri.tryParse(s);
    return u != null && (u.scheme == 'http' || u.scheme == 'https');
  }

  static void _set(String base) {
    _current = base.endsWith('/') ? base : '$base/';
  }
}