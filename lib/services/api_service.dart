  static String? _firstInputValue(dom.Document doc, String name) {
    final input = doc.querySelector('input[name="$name"]');
    return input?.attributes['value']?.trim();
  }

  static String _normSpace(String s) => s
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD□]'), '')
      .replaceAll(RegExp(r'[ \t\u00A0\u3000]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();

  static int? _firstInt(RegExp re, String s) {
    final m = re.firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static String? _firstMeta(dom.Document doc, String property) {
    for (final e in doc.querySelectorAll('meta')) {
      final key = e.attributes['property'] ?? e.attributes['name'] ?? '';
      if (key == property) return e.attributes['content'];
    }
    return null;
  }

  static String _stripTags(String value) => parser.parseFragment(value).text ?? '';
  static bool _navigationTitle(String text) => const {'下一页','上一页','首页','尾页','更多','回复','查看','详情','登录','注册','搜索'}.contains(text);
}

class _PaidState {
  final bool isPaid;
  final int? price;
  final String currency;
  final String purchaseUrl;
  const _PaidState(this.isPaid, this.price, this.currency, this.purchaseUrl);
}
