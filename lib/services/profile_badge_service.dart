import 'package:html/parser.dart' as parser;

import 'auth_service.dart';
import 'net_client.dart';

class ProfileBadgeService {
  ProfileBadgeService._();
  static final instance = ProfileBadgeService._();
  static const _base = 'https://www.ycoo.net/';

  Future<List<String>> fetch(int uid) async {
    if (uid <= 0) return const [];
    final client = await NetClient.instance.client;
    final uri = Uri.parse('${_base}home.php?mod=space&uid=$uid&do=profile&mobile=2').replace(queryParameters: {
      'mod': 'space',
      'uid': '$uid',
      'do': 'profile',
      'mobile': '2',
      '_ycoo_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final cookie = AuthService.instance.authCookie;
    final response = await NetClient.retry(() => client.get(uri, headers: {
      'User-Agent': NetClient.ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    }).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) return const [];

    final doc = parser.parse(NetClient.decode(response.bodyBytes));
    final source = <String>[];
    for (final selector in [
      '.comiis_space_level',
      '.comiis_space_user .gm',
      '.gm',
      '.top_lev',
      'a[href*="gid="]',
    ]) {
      for (final node in doc.querySelectorAll(selector)) {
        final value = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (value.isNotEmpty && value.length <= 80 && !source.contains(value)) source.add(value);
      }
    }

    final all = source.join(' ');
    final result = <String>[];
    final level = RegExp(r'Lv[.]?\s*\d+', caseSensitive: false).firstMatch(all)?.group(0);
    if (level != null) result.add(level.replaceAll(RegExp(r'\s+'), ''));
    const ranks = ['童生','秀才','举人','进士','探花','榜眼','状元','九品','八品','七品','六品','五品','四品','三品','二品','一品'];
    for (final rank in ranks) {
      if (all.contains(rank)) {
        result.add(rank);
        break;
      }
    }
    return result;
  }
}
