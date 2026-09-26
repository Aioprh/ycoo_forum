import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// 更换论坛头像。
///
/// 走 Discuz 手机 API 的头像上传接口(uploadavatar): 服务端会自行缩放裁切并写入
/// UCenter, 客户端只需要提交一张图片, 不需要 formhash, 也不需要访问 UCenter:
///   POST {base}api/mobile/index.php?version=2&module=uploadavatar
///   multipart 字段 Filedata = 图片
/// 成功返回 {"Variables":{"uploadavatar":"api_uploadavatar_success"}}。
class AvatarService {
  AvatarService._();

  static final AvatarService instance = AvatarService._();

  /// 头像原图统一裁成正方形边长, 既保证头像不变形, 也避免超出服务端上传体积限制。
  static const double _avatarSide = 400;

  /// 解码上限: 手机相册原图可能非常大, 先按比例限制解码尺寸, 避免整张解码占满内存。
  static const double _maxDecodeSide = 800;

  /// 上传新头像。成功返回 null, 失败返回可直接展示给用户的文案。
  Future<String?> upload(Uint8List bytes) async {
    if (bytes.isEmpty) return '没有读取到图片，请重新选择';
    await AuthService.instance.init();
    final cookie = AuthService.instance.authCookie?.trim() ?? '';
    if (!AuthService.instance.isLoggedIn || cookie.isEmpty) {
      return '请先登录论坛';
    }

    final prepared = await _squareCrop(bytes);
    try {
      final client = await NetClient.instance.client;
      final uri = Uri.parse('${SiteConfig.base}api/mobile/index.php')
          .replace(queryParameters: {'version': '2', 'module': 'uploadavatar'});
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          'User-Agent': NetClient.ua,
          'Accept': 'application/json, text/plain, */*',
          'Referer': '${SiteConfig.base}home.php?mod=spacecp&ac=avatar&mobile=2',
          'Cookie': cookie,
        })
        ..files.add(http.MultipartFile.fromBytes(
          'Filedata',
          prepared,
          filename: 'avatar.png',
        ));
      final streamed = await client.send(request).timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      return _errorOf(NetClient.decode(response.bodyBytes));
    } catch (_) {
      return '上传失败，请检查网络后重试';
    }
  }

  /// 解析接口返回: 成功返回 null, 否则给出可读错误。
  String? _errorOf(String body) {
    String? code;
    var parsed = false;
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        parsed = true;
        final variables = data['Variables'];
        if (variables is Map) code = '${variables['uploadavatar'] ?? ''}'.trim();
        code ??= '${data['error'] ?? ''}'.trim();
      }
    } catch (_) {}
    // 没拿到 JSON 说明请求被登录页/错误页拦截, 多半是会话失效。
    if (!parsed) {
      return body.contains('登录') || body.contains('<html')
          ? '登录态已失效，请重新登录后再试'
          : '没有取得头像上传结果，请稍后重试';
    }
    switch (code) {
      case 'api_uploadavatar_success':
        return null;
      case 'api_uploadavatar_unavailable_user':
        return '登录态已失效，请重新登录后再试';
      case 'api_uploadavatar_unavailable_pic':
        return '没有读取到图片，请重新选择';
      case 'api_uploadavatar_unusable_image':
        return '这张图片无法作为头像，请换一张图片';
      case 'api_uploadavatar_service_unwritable':
        return '论坛暂时无法保存头像，请稍后再试';
      case 'api_uploadavatar_uc_error':
        return '论坛头像服务异常，请稍后再试';
      case 'module_not_exists':
        return '当前站点未开启头像上传接口';
      case null:
      case '':
        return '没有取得头像上传结果，请稍后重试';
      default:
        return '更换头像失败，请稍后重试';
    }
  }

  /// 把任意图片居中裁成正方形并缩放到 [_avatarSide], 失败时回退原图。
  Future<Uint8List> _squareCrop(Uint8List input) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? cropped;
    ui.Picture? picture;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(input);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final side = math.min(descriptor.width, descriptor.height);
      if (side <= 0) return input;

      final scale = math.min(1.0, _maxDecodeSide / side);
      codec = scale < 1
          ? await descriptor.instantiateCodec(
              targetWidth: math.max(1, (descriptor.width * scale).round()),
              targetHeight: math.max(1, (descriptor.height * scale).round()),
            )
          : await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      source = frame.image;
      final croppedSide = math.min(source.width, source.height);

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        source,
        ui.Rect.fromLTWH(
          (source.width - croppedSide) / 2,
          (source.height - croppedSide) / 2,
          croppedSide.toDouble(),
          croppedSide.toDouble(),
        ),
        const ui.Rect.fromLTWH(0, 0, _avatarSide, _avatarSide),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      picture = recorder.endRecording();
      cropped = await picture.toImage(_avatarSide.toInt(), _avatarSide.toInt());
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return input;
      return data.buffer.asUint8List();
    } catch (_) {
      return input;
    } finally {
      picture?.dispose();
      cropped?.dispose();
      source?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}