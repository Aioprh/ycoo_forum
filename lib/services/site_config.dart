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

  static const String _prefKey = 'site_config_raw';

  /// 当前生效的域名配置(host -> 带尾部 `/` 的绝对地址)。
  /// 来自远程配置, 至少含 [baseHost]; cdn / api 可选, 缺省时回退到 base。
  static Map<String, String> _hosts = const {};

  /// 主站点基址(带尾部 `/`)。
  static String get base => _hosts[baseHost] ?? '$defaultBase/';

  /// 资源 CDN / 图片等静态资源域名; 未单独配置时等同于 [base]。
  static String get cdn => _hosts[cdnHost] ?? base;

  /// 接口域名; 未单独配置时等同于 [base]。
  static String get api => _hosts[apiHost] ?? base;

  /// 配置文件里各字段的键名。
  static const String baseHost = 'base';
  static const String cdnHost = 'cdn';
  static const String apiHost = 'api';

  /// 把相对路径 / 网址统一解析为基于 [host] 的绝对地址。
  static String _resolveWith(String host, String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final prefix = host.endsWith('/') ? host : '$host/';
    return prefix + v.replaceFirst(RegExp(r'^/'), '');
  }

  /// 基于主站点域名解析(帖子、页面、接口等绝大多数场景)。
  static String resolve(String value) => _resolveWith(base, value);

  /// 基于 CDN 域名解析(图片/静态资源)。
  static String resolveCdn(String value) => _resolveWith(cdn, value);

  /// 基于 API 域名解析。
  static String resolveApi(String value) => _resolveWith(api, value);

  /// 应用启动时调用: 先加载本地缓存, 再后台尝试拉取远程配置(不阻塞启动)。
  static Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(_prefKey);
      if (cached != null && cached.trim().isNotEmpty) {
        final data = jsonDecode(cached);
        if (data is Map) _apply(data);
      }
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
      if (!_apply(data)) return;
      // 把完整的、校验通过后的配置原样缓存, 供下次启动离线使用。
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, jsonEncode(_hosts));
      debugPrint('SiteConfig: 已更新配置为 $_hosts');
    } catch (err) {
      debugPrint('SiteConfig: 拉取远程配置失败, 继续使用当前配置 ($err)');
    }
  }

  /// 应用远程配置。要求 base 合法; cdn / api 可选且必须合法才接受。
  /// 返回是否接受(即 base 合法)。
  static bool _apply(Map data) {
    final next = <String, String>{};
    final b = (data[baseHost] as String?)?.trim();
    if (b == null || b.isEmpty || !_looksLikeHttp(b)) return false;
    next[baseHost] = b.endsWith('/') ? b : '$b/';
    final c = (data[cdnHost] as String?)?.trim();
    if (c != null && c.isNotEmpty && _looksLikeHttp(c)) {
      next[cdnHost] = c.endsWith('/') ? c : '$c/';
    }
    final a = (data[apiHost] as String?)?.trim();
    if (a != null && a.isNotEmpty && _looksLikeHttp(a)) {
      next[apiHost] = a.endsWith('/') ? a : '$a/';
    }
    _hosts = next;
    return true;
  }

  static bool _looksLikeHttp(String s) {
    final u = Uri.tryParse(s);
    return u != null && (u.scheme == 'http' || u.scheme == 'https');
  }
}