import 'dart:async';
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
      // 不开 QUIC(HTTP/3):站点对大部分网络走 HTTP/2 足矣;部分 4G/弱网/
      // 防火墙会丢弃 QUIC 的 UDP,导致 Cronet 反复报 ERR_CONNECTION_CLOSED。
      enableQuic: false,
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

  /// 对「瞬时网络故障」做简单重试。
  ///
  /// 站点握手强校验 + 弱网下会偶发 `ERR_CONNECTION_CLOSED` / 握手被掐断,
  /// 这类错误属于传输层瞬时故障,重试大概率成功。仅在请求真正发出前或
  /// 传输中途失败时触发(此时服务端未提交副作用),故对 GET/POST 都安全。
  static Future<T> retry<T>(
    Future<T> Function() fn, {
    int times = 3,
    Duration delay = const Duration(milliseconds: 600),
    void Function(Object error, int attempt)? onRetry,
  }) async {
    Object? last;
    for (var i = 0; i < times; i++) {
      try {
        return await fn();
      } catch (e) {
        last = e;
        onRetry?.call(e, i + 1);
        if (i < times - 1) await Future<void>.delayed(delay);
      }
    }
    Error.throwWithStackTrace(last!, StackTrace.current);
  }
}