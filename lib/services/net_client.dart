import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 统一网络客户端工厂。
/// 对显式携带 formhash/hash 的 URL-encoded 写请求提供一次透明的令牌恢复。
class NetClient {
  NetClient._();
  static final NetClient instance = NetClient._();

  static const String ua = 'Mozilla/5.0 (Linux; Android 10) YcoForum/1.0';
  static const Duration timeout = Duration(seconds: 20);

  http.Client? _client;

  Future<http.Client> get client async {
    final raw = _client ??= await _build();
    if (raw is _FormHashAwareClient) return raw;
    final wrapped = _FormHashAwareClient(raw);
    _client = wrapped;
    return wrapped;
  }

  Future<http.Client> _build() async {
    if (!Platform.isAndroid) return IOClient(HttpClient()..userAgent = ua);
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

  static String decode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final declared = _declaredCharset(bytes);
    if (declared != null) {
      final encoding = Charset.getByName(declared);
      if (encoding != null) {
        try { return encoding.decode(bytes); } catch (_) {}
      }
    }
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      try { return gbk.decode(bytes); } catch (_) { return const Utf8Decoder(allowMalformed: true).convert(bytes); }
    }
  }

  static String? _declaredCharset(List<int> bytes) {
    final length = bytes.length > 16384 ? 16384 : bytes.length;
    final ascii = String.fromCharCodes(bytes.take(length).map((b) => b < 128 ? b : 32));
    return RegExp(r'''charset\s*=\s*["']?\s*([A-Za-z0-9._-]+)''', caseSensitive: false).firstMatch(ascii)?.group(1)?.trim().toLowerCase();
  }

  static String? first(RegExp re, String s) => re.firstMatch(s)?.group(1);

  /// Discuz/Comiis 的 formhash 可能出现在 hidden input、data-formhash、JS/JSON 或 URL 中。
  static String? extractFormHash(String html) {
    if (html.isEmpty) return null;
    for (final match in RegExp(r'<input\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = match.group(0) ?? '';
      final name = _attribute(tag, 'name');
      if (name?.toLowerCase() == 'formhash') {
        final value = _attribute(tag, 'value');
        if (_validFormHash(value)) return value;
      }
    }
    for (final match in RegExp(r'<[^>]*\bdata-formhash\s*=\s*["\']([^"\']+)["\'][^>]*>', caseSensitive: false).allMatches(html)) {
      final value = match.group(1)?.trim();
      if (_validFormHash(value)) return value;
    }
    final patterns = <RegExp>[
      RegExp(r'''(?:^|[?&])formhash=([A-Za-z0-9_-]{6,128})(?:&|$)''', caseSensitive: false),
      RegExp(r'''["']formhash["']\s*:\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
      RegExp(r'''\bformhash\s*[=:]\s*["']([A-Za-z0-9_-]{6,128})["']''', caseSensitive: false),
      RegExp(r'''\bformhash\s*=\s*([A-Za-z0-9_-]{6,128})''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1)?.trim();
      if (_validFormHash(value)) return value;
    }
    return null;
  }

  static String? _attribute(String tag, String name) {
    final re = RegExp('\\b${RegExp.escape(name)}\\s*=\\s*["\\\']([^"\\\']*)["\\\']', caseSensitive: false);
    return re.firstMatch(tag)?.group(1)?.trim();
  }

  static bool _validFormHash(String? value) => value != null && RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(value);

  static bool _tokenFailure(String body) {
    final lower = body.toLowerCase();
    final explicit = lower.contains('操作令牌') || lower.contains('令牌已失效') || lower.contains('token expired') || lower.contains('invalid token') || lower.contains('非法操作') || lower.contains('来路不正确');
    final formHashError = lower.contains('formhash') && (lower.contains('错误') || lower.contains('非法') || lower.contains('失效') || lower.contains('无效') || lower.contains('invalid') || lower.contains('error') || lower.contains('expired'));
    return explicit || formHashError;
  }

  static String _replaceEncodedField(String body, String name, String token) {
    final pattern = RegExp('((?:^|&)${RegExp.escape(name)}=)[^&]*', caseSensitive: false);
    final match = pattern.firstMatch(body);
    if (match == null) return body;
    final start = match.start;
    final end = match.end;
    return '${body.substring(0, start)}${match.group(1)}${Uri.encodeQueryComponent(token)}${body.substring(end)}';
  }

  static String _replaceToken(String body, String token) {
    var result = _replaceEncodedField(body, 'formhash', token);
    result = _replaceEncodedField(result, 'hash', token);
    return result;
  }

  static Uri _replaceQueryToken(Uri uri, String token) {
    final qp = <String, String>{...uri.queryParameters};
    if (qp.containsKey('formhash')) qp['formhash'] = token;
    if (qp.containsKey('hash')) qp['hash'] = token;
    return uri.replace(queryParameters: qp);
  }

  static Future<http.StreamedResponse?> _freshResponse(http.Client inner, http.BaseRequest request) async {
    final referer = request.headers['Referer'] ?? request.headers['referer'];
    if (referer == null || referer.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(referer);
      final headers = <String, String>{'User-Agent': ua, 'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', 'Cache-Control': 'no-cache, no-store', 'Pragma': 'no-cache'};
      final cookie = request.headers['Cookie'] ?? request.headers['cookie'];
      if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
      return await inner.send(http.Request('GET', uri)..headers.addAll(headers));
    } catch (_) { return null; }
  }

  static http.BaseRequest? _cloneWithToken(http.BaseRequest request, String token) {
    if (request is! http.Request) return null;
    final contentType = request.headers['Content-Type'] ?? request.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/x-www-form-urlencoded')) return null;
    final clone = http.Request(request.method, _replaceQueryToken(request.url, token));
    clone.headers.addAll(request.headers);
    clone.body = _replaceToken(request.body, token);
    return clone;
  }

  static Future<http.StreamedResponse> _sendWithRefresh(http.Client inner, http.BaseRequest request) async {
    final response = await inner.send(request);
    if (response.statusCode < 200 || response.statusCode >= 500) return response;

    final isUrlEncoded = request is http.Request && (request.headers['Content-Type'] ?? request.headers['content-type'] ?? '').toLowerCase().contains('application/x-www-form-urlencoded');
    final hasToken = request.url.queryParameters.containsKey('formhash') || request.url.queryParameters.containsKey('hash') || (isUrlEncoded && RegExp(r'(?:^|&)formhash=', caseSensitive: false).hasMatch(request.body));
    if (!hasToken) return response;

    final bodyBytes = await response.stream.toBytes();
    final bodyText = decode(bodyBytes);
    if (!_tokenFailure(bodyText)) return _buffered(response, bodyBytes);

    final fresh = await _freshResponse(inner, request);
    if (fresh == null) return _buffered(response, bodyBytes);
    final freshBytes = await fresh.stream.toBytes();
    final token = extractFormHash(decode(freshBytes));
    if (token == null || token.isEmpty) return _buffered(response, bodyBytes);

    final retryRequest = _cloneWithToken(request, token);
    if (retryRequest != null) return inner.send(retryRequest);

    if (request.url.queryParameters.containsKey('formhash') || request.url.queryParameters.containsKey('hash')) {
      final replacement = http.Request(request.method, _replaceQueryToken(request.url, token));
      replacement.headers.addAll(request.headers);
      return inner.send(replacement);
    }
    return _buffered(response, bodyBytes);
  }

  static http.StreamedResponse _buffered(http.StreamedResponse response, List<int> bytes) => http.StreamedResponse(
    Stream<List<int>>.value(bytes), response.statusCode, contentLength: bytes.length,
    request: response.request, headers: response.headers, isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection, reasonPhrase: response.reasonPhrase,
  );

  static Future<T> retry<T>(Future<T> Function() fn, {int times = 3, Duration delay = const Duration(milliseconds: 600), void Function(Object error, int attempt)? onRetry}) async {
    Object? last;
    for (var i = 0; i < times; i++) {
      try { return await fn(); } catch (e) {
        last = e; onRetry?.call(e, i + 1);
        if (i < times - 1) await Future<void>.delayed(delay);
      }
    }
    Error.throwWithStackTrace(last!, StackTrace.current);
  }
}

class _FormHashAwareClient extends http.BaseClient {
  final http.Client _inner;
  _FormHashAwareClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => NetClient._sendWithRefresh(_inner, request);

  @override
  void close() => _inner.close();
}
