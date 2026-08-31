/// Normalizes text copied from Discuz HTML before it reaches Flutter widgets.
///
/// A missing-glyph tofu box should be solved by font fallback, but malformed
/// control characters and Unicode replacement characters should not be
/// propagated into the UI either.
String forumText(String value) {
  if (value.isEmpty) return value;

  return value
      .replaceAll('\uFFFD', '')
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll('\uFEFF', '')
      .trim();
}
