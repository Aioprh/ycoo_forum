/// Normalizes text copied from Discuz HTML before it reaches Flutter widgets.
///
/// Discuz/Comiis uses private-use Unicode code points (for example \uE60D)
/// inside elements such as `.comiis_font` for its icon font. Those characters
/// have no glyph in Flutter's normal text fonts and appear as a square with an
/// X. They are presentation icons, not user content, so they must never enter
/// native Text widgets.
String forumText(String value) {
  if (value.isEmpty) return value;

  return value
      .replaceAll('\uFFFD', '')
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll(RegExp(r'[\uE000-\uF8FF]'), '')
      .replaceAll(RegExp(r'[\uDB80-\uDBFF][\uDC00-\uDFFF]'), '')
      .replaceAll('\uFEFF', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
