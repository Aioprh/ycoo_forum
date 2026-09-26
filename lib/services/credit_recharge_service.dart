import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'net_client.dart';
import 'site_config.dart';

/// 一个充值档位，例如「100 星币 + 赠 50」。
class RechargeBonus {
  const RechargeBonus({required this.amount, required this.bonus});

  /// 档位包含的积分数量(不含赠送)。
  final int amount;
  /// 额外赠送的积分数量。
  final int bonus;

  int get total => amount + bonus;
}

/// 可充值的一种积分(源币/星币)。
class RechargeCreditType {
  const RechargeCreditType({
    required this.creditType,
    required this.title,
    required this.balance,
    required this.rate,
    required this.minAmount,
    required this.bonusList,
  });

  /// 原站积分类型 id，提交表单时用。
  final String creditType;
  final String title;
  final int balance;
  /// 1 元兑换多少积分。
  final double rate;
  /// 自定义充值的最低金额(元)。
  final double minAmount;
  final List<RechargeBonus> bonusList;

  /// 元 -> 积分(原站用 parseInt 截断)。
  int creditOf(double yuan) => (yuan * rate).floor();

  /// 积分 -> 元。
  double priceOf(int credit) => credit / rate;

  factory RechargeCreditType.fromJson(Map<dynamic, dynamic> json) {
    final rawList = json['bonus_list'];
    final bonuses = <RechargeBonus>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is! Map) continue;
        final amount = _intOf(item['amount']);
        if (amount <= 0) continue;
        bonuses.add(RechargeBonus(amount: amount, bonus: _intOf(item['bonus'])));
      }
    }
    final title = '${json['title'] ?? ''}'.trim();
    final rate = _numOf(json['rate']);
    final minAmount = _numOf(json['minamount']);
    return RechargeCreditType(
      creditType: '${json['credittype'] ?? ''}'.trim(),
      title: title.isEmpty ? '积分' : title,
      balance: _intOf(json['balance']),
      rate: rate <= 0 ? 1 : rate,
      minAmount: minAmount <= 0 ? 1 : minAmount,
      bonusList: bonuses,
    );
  }
}

/// 充值页解析出来的配置(积分信息 + 可用渠道 + formhash)。
class RechargeConfig {
  const RechargeConfig({
    required this.creditTypes,
    required this.formhash,
    required this.alipay,
    required this.wxpay,
    required this.paypal,
  });

  final List<RechargeCreditType> creditTypes;
  final String formhash;
  final bool alipay;
  final bool wxpay;
  final bool paypal;
}

/// 原站下单后返回的订单。
class RechargeOrder {
  const RechargeOrder({required this.orderId, required this.payMethod});

  final String orderId;
  /// `alipay` / `wxpay` / `paypal` / `card`。
  final String payMethod;
}

/// 支付引导信息：微信给出二维码内容，支付宝给出交给系统浏览器打开的网关地址。
class RechargePayment {
  const RechargePayment({
    required this.payMethod,
    required this.tradeNo,
    required this.gatewayOrigin,
    this.qrContent,
    this.openUrl,
  });

  final String payMethod;
  /// 第三方网关的流水号，用于轮询支付状态；拿不到时为空。
  final String tradeNo;
  final String gatewayOrigin;
  /// 微信：二维码需要编码的内容(微信内打开才会进入支付)。
  final String? qrContent;
  /// 支付宝：直接交给系统浏览器打开，浏览器会自动提交到支付宝收银台。
  final String? openUrl;
}

/// 支付状态轮询结果。
class RechargeStatus {
  const RechargeStatus({required this.paid, this.backUrl});

  final bool paid;
  /// 支付成功时网关给的回跳地址，访问它可以触发原站入账。
  final String? backUrl;
}

class RechargeException implements Exception {
  const RechargeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 源币充值：把原本由 WebView 承载的 boan_buycredit 充值流程改成原生实现。
///
/// 实测链路：
/// 1. GET  充值页          -> `extcredits_list`(JSON) + 渠道开关 + formhash
/// 2. POST 充值页          -> 响应里的 `window.location.href` 指向 boan_payment:pay 订单页
/// 3. GET  订单页          -> 302 到第三方网关 `epay.srcmom.com/submit.php`
/// 4. GET  网关页          -> 微信: JS 跳到 `/pay/wap/<trade_no>/`；支付宝: 自动提交到支付宝开放平台
/// 5. 轮询 网关 check_status -> `{"code":1}` 即支付成功，并给出回跳地址
///
/// 论坛域的请求才带登录 Cookie，第三方网关只带必要的 Referer，避免把论坛会话泄露出去。
class CreditRechargeService {
  CreditRechargeService._();

  static final CreditRechargeService instance = CreditRechargeService._();

  static const String _path =
      'home.php?ac=plugin&id=boan_buycredit:buycredit&mod=spacecp&op=credit';

  static Uri get _rechargeUri => Uri.parse('${SiteConfig.base}$_path');

  static Uri _pluginUri(String id, Map<String, String> query) =>
      Uri.parse('${SiteConfig.base}plugin.php').replace(queryParameters: {
        'id': id,
        ...query,
      });

  /// 读取充值页：积分余额、兑换比率、档位、可用支付渠道、formhash。
  Future<RechargeConfig> fetchConfig() async {
    final response = await _get(
      _rechargeUri,
      headers: await _forumHeaders(),
      followRedirects: true,
    );
    final html = NetClient.decode(response.bodyBytes);
    if (html.trim().isEmpty) {
      throw const RechargeException('充值页返回为空，请稍后重试');
    }

    final match = RegExp(
      r'var\s+extcredits_list\s*=\s*(\[.*?\])\s*;',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) {
      if (html.contains('logging') || html.contains('登录')) {
        throw const RechargeException('登录态已失效，请重新登录后再试');
      }
      throw const RechargeException('充值页结构已变化，请改用网页版支付');
    }

    List<RechargeCreditType> types;
    try {
      final decoded = jsonDecode(match.group(1)!);
      types = (decoded as List)
          .whereType<Map>()
          .map(RechargeCreditType.fromJson)
          .where((type) => type.creditType.isNotEmpty)
          .toList();
    } catch (_) {
      throw const RechargeException('充值档位解析失败，请改用网页版支付');
    }
    if (types.isEmpty) {
      throw const RechargeException('当前账号暂无可充值的积分类型');
    }

    final formhash = NetClient.extractFormHash(html) ?? '';
    if (formhash.isEmpty) {
      throw const RechargeException('登录态已失效，请重新登录后再试');
    }

    return RechargeConfig(
      creditTypes: types,
      formhash: formhash,
      alipay: _enabled(html, 'alipay'),
      wxpay: _enabled(html, 'wxpay'),
      paypal: _enabled(html, 'paypal'),
    );
  }

  /// 下单。注意这里不做重试，避免重复生成订单。
  Future<RechargeOrder> createOrder({
    required String creditType,
    required int creditAmount,
    required String payMethod,
    required String formhash,
  }) async {
    final response = await _post(
      _rechargeUri,
      {
        'formhash': formhash,
        'buysubmit': 'true',
        'credittype': creditType,
        'extcreditamount': '$creditAmount',
        'paymethod': _payMethodCode(payMethod),
        'jumpurl': '',
      },
      headers: await _forumHeaders(referer: _rechargeUri.toString()),
    );
    final html = NetClient.decode(response.bodyBytes);
    final match = RegExp(
      r"""window\.location\.href\s*=\s*['"]([^'"]+)['"]""",
    ).firstMatch(html);
    if (match == null) {
      throw RechargeException(_orderError(html) ?? '下单失败，请稍后重试');
    }

    final target = _rechargeUri.resolve(match.group(1)!.trim());
    final orderId = target.queryParameters['order_id']?.trim() ?? '';
    if (orderId.isEmpty) {
      throw const RechargeException('下单失败：未获取到订单号');
    }
    return RechargeOrder(
      orderId: orderId,
      payMethod: target.queryParameters['pay_method']?.trim() ?? payMethod,
    );
  }

  /// 解析订单页和网关页，拿到二维码内容或需要外部打开的收银台地址。
  Future<RechargePayment> preparePayment(RechargeOrder order) async {
    final orderUri = _pluginUri('boan_payment:pay', {
      'order_id': order.orderId,
      'pay_method': order.payMethod,
      'qrcode': '',
      'qrcode_width': '0',
    });

    final landing = await _get(
      orderUri,
      headers: await _forumHeaders(referer: _rechargeUri.toString()),
      followRedirects: false,
    );
    final location = landing.headers['location']?.trim() ?? '';
    if (location.isEmpty) {
      throw const RechargeException('支付网关没有返回跳转地址，请改用网页版支付');
    }

    final gatewayUri = Uri.parse(location);
    final origin = '${gatewayUri.scheme}://${gatewayUri.authority}';
    final gatewayPage = await _get(
      gatewayUri,
      headers: _gatewayHeaders(referer: orderUri.toString()),
      followRedirects: true,
    );
    final gatewayHtml = NetClient.decode(gatewayPage.bodyBytes);

    // 微信：网关页用 JS 跳到 /pay/wap/<trade_no>/，二维码内容是该单的 jspay 链接。
    final wap = RegExp(
      r"""window\.location\.replace\(\s*['"]/pay/wap/(\d+)/['"]\s*\)""",
    ).firstMatch(gatewayHtml);
    if (wap != null) {
      final tradeNo = wap.group(1)!;
      return RechargePayment(
        payMethod: 'wxpay',
        tradeNo: tradeNo,
        gatewayOrigin: origin,
        qrContent: '$origin/pay/jspay/$tradeNo/',
      );
    }

    // 支付宝：网关页会自动提交表单到支付宝开放平台，交给系统浏览器打开即可。
    // 流水号从表单里的 notify_url(/pay/notify/<trade_no>/) 取，用于轮询支付状态。
    final tradeNo = RegExp(r'/pay/notify/(\d+)/').firstMatch(gatewayHtml)?.group(1) ??
        RegExp(r'/pay/return/(\d+)/').firstMatch(gatewayHtml)?.group(1) ??
        '';

    return RechargePayment(
      payMethod: 'alipay',
      tradeNo: tradeNo,
      gatewayOrigin: origin,
      openUrl: gatewayUri.toString(),
    );
  }

  /// 查询是否已支付。
  Future<RechargeStatus> checkStatus(RechargePayment payment) async {
    if (payment.tradeNo.isEmpty) return const RechargeStatus(paid: false);

    final response = await _get(
      Uri.parse(
        '${payment.gatewayOrigin}/payment/check_status?trade_no=${payment.tradeNo}',
      ),
      headers: {
        ..._gatewayHeaders(
          referer: '${payment.gatewayOrigin}/pay/wap/${payment.tradeNo}/',
        ),
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
      },
      followRedirects: true,
    );
    final body = NetClient.decode(response.bodyBytes);
    try {
      final data = jsonDecode(body);
      if (data is Map && data['code'] == 1) {
        final back = '${data['backurl'] ?? ''}'.trim();
        return RechargeStatus(paid: true, backUrl: back.isEmpty ? null : back);
      }
    } catch (_) {}
    return const RechargeStatus(paid: false);
  }

  /// 支付成功后访问网关回跳地址触发原站入账，并返回最新的积分余额。
  Future<int?> settle(RechargePayment payment, RechargeStatus status) async {
    final backUrl = status.backUrl;
    if (backUrl != null && backUrl.isNotEmpty) {
      final uri = Uri.tryParse(backUrl);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        try {
          await _get(
            uri,
            headers: uri.host == Uri.parse(SiteConfig.base).host
                ? await _forumHeaders(referer: _rechargeUri.toString())
                : _gatewayHeaders(referer: payment.gatewayOrigin),
            followRedirects: true,
          );
        } catch (_) {
          // 入账由服务端回调负责，这里失败不影响后续余额刷新。
        }
      }
    }

    try {
      final config = await fetchConfig();
      for (final type in config.creditTypes) {
        if (type.creditType == _lastCreditType) return type.balance;
      }
      return config.creditTypes.isEmpty ? null : config.creditTypes.first.balance;
    } catch (_) {
      return null;
    }
  }

  String? _lastCreditType;

  void rememberCreditType(String creditType) => _lastCreditType = creditType;

  String _payMethodCode(String payMethod) {
    switch (payMethod) {
      case 'wxpay':
        return '2';
      case 'paypal':
        return '4';
      case 'card':
        return '3';
      default:
        return '1';
    }
  }

  static bool _enabled(String html, String name) =>
      RegExp('var\\s+$name\\s*=\\s*1\\b').hasMatch(html);

  /// 下单失败的页面里通常会带一句中文提示，尽量把它取出来给用户看。
  String? _orderError(String html) {
    if (html.contains('余额不足')) return '积分余额不足';
    final match = RegExp(
      r'(?:错误|提示|抱歉)[^<]{0,60}',
    ).firstMatch(html);
    final text = match?.group(0)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<Map<String, String>> _forumHeaders({String? referer}) async {
    await AuthService.instance.init();
    final cookie = AuthService.instance.authCookie?.trim() ?? '';
    if (!AuthService.instance.isLoggedIn || cookie.isEmpty) {
      throw const RechargeException('请先登录论坛');
    }
    return {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache',
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
      'Cookie': cookie,
    };
  }

  Map<String, String> _gatewayHeaders({String? referer}) => {
        'User-Agent': NetClient.ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
      };

  Future<http.Response> _get(
    Uri uri, {
    required Map<String, String> headers,
    required bool followRedirects,
  }) async {
    final client = await NetClient.instance.client;
    final request = http.Request('GET', uri)..followRedirects = followRedirects;
    request.headers.addAll(headers);
    final streamed = await client.send(request).timeout(NetClient.timeout);
    return http.Response.fromStream(streamed);
  }

  Future<http.Response> _post(
    Uri uri,
    Map<String, String> body, {
    required Map<String, String> headers,
  }) async {
    final client = await NetClient.instance.client;
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll({
        ...headers,
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      })
      ..bodyFields = body;
    final streamed = await client.send(request).timeout(NetClient.timeout);
    return http.Response.fromStream(streamed);
  }
}

double _numOf(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _intOf(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ??
      _numOf(value).round();
}