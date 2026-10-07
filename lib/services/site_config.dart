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

  /// 论坛可用的备用入口。主入口无法从当前网络访问时自动探测并切换。
  static const List<String> fallbackBases = <String>[
    'https://www.ycoo.net/',
    'https://ycoo.net/',
    'https://pc.sysbbs.com/',
    'https://src.top/',
  ];

  /// 远程域名配置地址。放在本仓库, 与站点域名无关, 位置恒定。
  static const String remoteConfigUrl =
      'https://raw.githubusercontent.com/Aioprh/ycoo_forum/main/config/site.json';

  static const String _prefKey = 'site_config_raw';

  /// 当前生效的域名配置(host -> 带尾部 `/` 的绝对地址)。
  /// 来自远程配置, 至少含 [baseHost]; cdn / api 可选, 缺省时回退到 base。
  static Map<String, String> _hosts = const {};
  static bool _probing = false;

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

  /// 与主站指向同一论坛的别名域名(同一套数据, 仅域名不同)。
  /// 站点正文里的站内链接会按访问域名改写, 例如出现 `pc.sysbbs.com`,
  /// 若只认 [base] 会被误判为外链, 改用浏览器打开而不是原生页面。
  static const Set<String> aliasHosts = {'sysbbs.com', 'src.top'};

  /// 判断主机名是否属于本站(忽略大小写与 `www.` 前缀, 并兼容 [aliasHosts])。
  static bool isForumHost(String host) {
    final h = _normalizeHost(host);
    if (h.isEmpty) return false;
    final main = _normalizeHost(Uri.parse(base).host);
    if (h == main || h.endsWith('.$main')) return true;
    return aliasHosts.any((alias) => h == alias || h.endsWith('.$alias'));
  }

  static String _normalizeHost(String host) {
    final h = host.trim().toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

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
    await _selectReachableBase();
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
      await _selectReachableBase();
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
  static List<String> _candidateBases() {
    final values = <String>[];
    final configured = _hosts[baseHost];
    if (configured != null && configured.isNotEmpty) values.add(configured);
    final configuredList = _hosts.entries
        .where((e) => e.key.startsWith('base_'))
        .map((e) => e.value);
    for (final value in configuredList) {
      if (!values.contains(value)) values.add(value);
    }
    for (final value in fallbackBases) {
      if (!values.contains(value)) values.add(value);
    }
    return values;
  }

  /// 并行探测备用入口，按候选优先级选择第一个可正常建立 HTTP(S) 连接的站点。
  static Future<void> _selectReachableBase() async {
    if (_probing) return;
    _probing = true;
    try {
      final candidates = _candidateBases();
      final results = await Future.wait(candidates.map((base) async {
        try {
          final response = await http.head(Uri.parse(base)).timeout(const Duration(seconds: 3));
          if (response.statusCode >= 200 && response.statusCode < 400) return true;
          if (response.statusCode == 405 || response.statusCode == 501) {
            final get = await http.get(Uri.parse(base)).timeout(const Duration(seconds: 3));
            return get.statusCode >= 200 && get.statusCode < 400;
          }
        } catch (_) {}
        return false;
      }));
      final index = results.indexWhere((ok) => ok);
      if (index >= 0) {
        _hosts = <String, String>{..._hosts, baseHost: candidates[index]};
      }
    } finally {
      _probing = false;
    }
  }

  static bool _apply(Map data) {
    final next = <String, String>{};
    final rawBases = data['bases'];
    if (rawBases is List) {
      var index = 0;
      for (final item in rawBases) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty && _looksLikeHttp(value)) {
          next['base_' + index.toString()] = value.endsWith('/') ? value : value + '/';
          index++;
        }
      }
    }
    final b = (data[baseHost] as String?)?.trim();
    final selected = b != null && b.isNotEmpty && _looksLikeHttp(b)
        ? b
        : (next['base_0'] ?? '');
    if (selected.isEmpty) return false;
    next[baseHost] = selected.endsWith('/') ? selected : selected + '/';
    final c = (data[cdnHost] as String?)?.trim();
    if (c != null && c.isNotEmpty && _looksLikeHttp(c)) {
      next[cdnHost] = c.endsWith('/') ? c : '$c/';
    }
    final fallbacks = <String>[];
    final rawFallbacks = data['fallbacks'];
    if (rawFallbacks is List) {
      for (final value in rawFallbacks) {
        final s = value?.toString().trim() ?? '';
        if (s.isNotEmpty && _looksLikeHttp(s)) {
          fallbacks.add(s.endsWith('/') ? s : '$s/');
        }
      }
    }
    if (fallbacks.isEmpty) fallbacks.addAll(fallbackBases);
    for (final value in fallbacks) {
      if (!next.values.contains(value)) {
        final index = next.keys.where((key) => key.startsWith('base_')).length;
        next['base_' + index.toString()] = value;
      }
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