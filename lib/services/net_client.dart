import 'dart:convert';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 统一网络客户端工厂。
///
/// Android 上改用系统 Cronet(Chromium 内核):它的 TLS 指纹与浏览器一致,
/// 不会被 www.ycoo.net 这类站点的握手校验(反爬)在 TLS 握手阶段重置
/// (dart:io / http 包会被 `Connection terminated during handshake` 掐断)。
/// 同时 Cronet 自动管理 Cookie 与重定向,会话在引擎生命周期内保持。
///
/// 其它平台(桌面 / 测试)回退到 dart:io。
class NetClient {
  NetClient._();
  static final NetClient instance = NetClient._();

  static const String ua = 'Mozilla/5.0 (Linux; Android 10) YcoForum/1.0';

  static const Duration timeout = Duration(seconds: 20);

  http.Client? _client;

  /// 取共享客户端(懒加载)。
  Future<http.Client> get client async => _client ??= await _build();

  Future<http.Client> _build() async {
    if (!Platform.isAndroid) {
      return IOClient(HttpClient()..userAgent = ua);
    }
    final engine = CronetEngine.build(
      cacheMode: CacheMode.memory,
      cacheMaxSize: 8 * 1024 * 1024,
      enableHttp2: true,
      enableBrotli: true,
      enableQuic: true,
      userAgent: ua,
    );
    return CronetClient.fromCronetEngine(engine, closeEngine: true);
  }

  /// 从字节流按 utf-8 解码(容忍非法字节)。
  static String decode(List<int> bytes) {
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  /// 解析单个正则捕获组。
  static String? first(RegExp re, String s) => re.firstMatch(s)?.group(1);
}