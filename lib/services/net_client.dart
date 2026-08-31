import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
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

  /// 解码论坛返回的 HTML。
  ///
  /// 不能无条件使用 UTF-8。部分 Discuz 页面/历史主题仍可能声明 GBK、
  /// GB2312 或其它中文编码；直接用 Utf8Decoder(allowMalformed: true)
  /// 会把非法字节替换成 U+FFFD(�)，最终在 Flutter 中表现为方块/乱码，
  /// 也会让 HTML 里的用户名、帖子正文和关系数据无法正确解析。
  ///
  /// 这里按「HTML charset 声明 -> 严格 UTF-8 -> charset 检测 -> 宽容 UTF-8」
  /// 的顺序处理，避免为了兼容旧页面而破坏正常 UTF-8 页面。
  static String decode(List<int> bytes) {
    if (bytes.isEmpty) return '';

    final declared = _declaredCharset(bytes);
    if (declared != null) {
      final encoding = Charset.getByName(declared);
      if (encoding != null) {
        try {
          return encoding.decode(bytes);
        } catch (_) {
          // 声明错误时继续走自动检测。
        }
      }
    }

    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      // 不是合法 UTF-8。优先尝试 GBK/其它中文编码。
      try {
        final detected = Charset.detect(
          bytes,
          defaultEncoding: utf8,
          orders: <Encoding>[gbk, utf8],
        );
        if (detected != null) return detected.decode(bytes);
      } catch (_) {
        // 最后再用宽容 UTF-8，保证异常响应仍不会让 App 崩溃。
      }
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
  }

  /// 从响应前部提取 HTML/XML 的 charset 声明。
  /// 这里故意只扫描 ASCII 范围，因为 charset 声明本身只包含 ASCII，
  /// 即使正文是 GBK 也可以可靠识别。
  static String? _declaredCharset(List<int> bytes) {
    final length = bytes.length > 16384 ? 16384 : bytes.length;
    final ascii = String.fromCharCodes(
      bytes.take(length).map((b) => b < 128 ? b : 32),
    );
    final match = RegExp(
      r'(?:charset\s*=\s*["\']?|content-type[^>]*charset\s*=\s*["\']?)([A-Za-z0-9._-]+)',
      caseSensitive: false,
    ).firstMatch(ascii);
    return match?.group(1)?.trim().toLowerCase();
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