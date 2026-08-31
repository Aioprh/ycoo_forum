import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 统一网络客户端工厂。
class NetClient {
  NetClient._();
  static final NetClient instance = NetClient._();

  static const String ua = 'Mozilla/5.0 (Linux; Android 10) YcoForum/1.0';
  static const Duration timeout = Duration(seconds: 20);

  http.Client? _client;

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
      enableQuic: false,
      userAgent: ua,
    );
    return CronetClient.fromCronetEngine(engine, closeEngine: true);
  }

  /// 解码论坛返回的 HTML，兼容 UTF-8、GBK/GB2312 等历史中文页面。
  static String decode(List<int> bytes) {
    if (bytes.isEmpty) return '';

    final declared = _declaredCharset(bytes);
    if (declared != null) {
      final encoding = Charset.getByName(declared);
      if (encoding != null) {
        try {
          return encoding.decode(bytes);
        } catch (_) {}
      }
    }

    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      // charset 包的 GBK 编码器可以直接处理非 UTF-8 的中文页面。
      try {
        return gbk.decode(bytes);
      } catch (_) {
        return const Utf8Decoder(allowMalformed: true).convert(bytes);
      }
    }
  }

  static String? _declaredCharset(List<int> bytes) {
    final length = bytes.length > 16384 ? 16384 : bytes.length;
    final ascii = String.fromCharCodes(
      bytes.take(length).map((b) => b < 128 ? b : 32),
    );

    // 使用三引号 raw string，避免 Dart 字符串与正则中的引号互相转义。
    final match = RegExp(
      r'''charset\s*=\s*["']?\s*([A-Za-z0-9._-]+)''',
      caseSensitive: false,
    ).firstMatch(ascii);

    return match?.group(1)?.trim().toLowerCase();
  }

  static String? first(RegExp re, String s) => re.firstMatch(s)?.group(1);

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
