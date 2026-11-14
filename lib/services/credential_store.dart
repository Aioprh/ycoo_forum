import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地保存的登录凭证（账号 / 密码 / 安全提问）。
class SavedCredential {
  const SavedCredential({
    required this.username,
    required this.password,
    this.questionId = '0',
    this.answer = '',
    this.autoLogin = true,
  });

  final String username;
  final String password;
  final String questionId;
  final String answer;

  /// 登录态失效时是否允许静默自动登录。
  /// 用户主动「退出登录」会把它置为 false，避免刚退出又被自动登回去。
  final bool autoLogin;

  SavedCredential copyWith({bool? autoLogin}) => SavedCredential(
    username: username,
    password: password,
    questionId: questionId,
    answer: answer,
    autoLogin: autoLogin ?? this.autoLogin,
  );
}

/// 登录凭证的本机存储。
///
/// 设计取舍：
/// - 只写入应用私有目录（SharedPreferences），不随任何网络请求上传，也不进日志；
/// - 落盘前用一次性的密钥流做可逆混淆，避免 `shared_prefs` 的 XML 里
///   直接出现明文密码。这不是强加密，定位是「防窥」级别；
/// - 若后续需要 Android Keystore 级保护，只需把 [_Vault] 换成
///   flutter_secure_storage，调用方（LoginPage / AuthService）无需改动。
class CredentialStore {
  CredentialStore._();
  static final CredentialStore instance = CredentialStore._();

  static const String _prefPayload = 'ycoo.auth.credential';
  static const String _prefAuto = 'ycoo.auth.credential.auto';
  static const String _prefRemember = 'ycoo.auth.remember';

  /// 用户上次是否勾选了「记住账号密码」。
  /// null 表示从未选择过（首次登录，按默认勾选处理）。
  Future<bool?> rememberChoice() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(_prefRemember);
    } catch (_) {
      return null;
    }
  }

  Future<SavedCredential?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefPayload);
      if (raw == null || raw.isEmpty) return null;
      final plain = _Vault.open(raw);
      if (plain == null) return null;
      final map = jsonDecode(plain);
      if (map is! Map) return null;
      final username = (map['u'] as String?)?.trim() ?? '';
      final password = map['p'] as String? ?? '';
      if (username.isEmpty || password.isEmpty) return null;
      final questionId = (map['q'] as String?)?.trim() ?? '';
      return SavedCredential(
        username: username,
        password: password,
        questionId: questionId.isEmpty ? '0' : questionId,
        answer: map['a'] as String? ?? '',
        autoLogin: sp.getBool(_prefAuto) ?? true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasSaved() async {
    final saved = await load();
    return saved != null;
  }

  Future<void> save(SavedCredential credential) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final plain = jsonEncode(<String, String>{
        'u': credential.username,
        'p': credential.password,
        'q': credential.questionId,
        'a': credential.answer,
      });
      await sp.setString(_prefPayload, _Vault.seal(plain));
      await sp.setBool(_prefAuto, credential.autoLogin);
      await sp.setBool(_prefRemember, true);
    } catch (_) {}
  }

  /// 用户主动退出登录：保留账号密码方便下次填充，但关闭静默自动登录。
  Future<void> disableAutoLogin() async {
    final saved = await load();
    if (saved == null) return;
    await save(saved.copyWith(autoLogin: false));
  }

  Future<void> clear() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefPayload);
      await sp.remove(_prefAuto);
      await sp.setBool(_prefRemember, false);
    } catch (_) {}
  }
}

/// 轻量混淆容器：nonce + 校验和 + 异或密文，整体 base64url。
///
/// 仅用于避免明文落盘，不承担对抗逆向的职责。
class _Vault {
  static const String _secret = 'ycoo.forum.credential.v1';
  static const int _header = 8;

  static String seal(String plain) {
    final data = utf8.encode(plain);
    final nonce = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
    final rng = _KeyStream(_seed(_secret) ^ nonce);
    final out = Uint8List(_header + data.length);
    out[0] = nonce & 0xFF;
    out[1] = (nonce >> 8) & 0xFF;
    out[2] = (nonce >> 16) & 0xFF;
    out[3] = (nonce >> 24) & 0xFF;
    final sum = _checksum(data);
    out[4] = sum & 0xFF;
    out[5] = (sum >> 8) & 0xFF;
    out[6] = (sum >> 16) & 0xFF;
    out[7] = (sum >> 24) & 0xFF;
    for (var i = 0; i < data.length; i++) {
      out[_header + i] = data[i] ^ rng.next();
    }
    return base64Url.encode(out);
  }

  static String? open(String sealed) {
    try {
      final bytes = base64Url.decode(sealed);
      if (bytes.length <= _header) return null;
      final nonce = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
      final rng = _KeyStream(_seed(_secret) ^ nonce);
      final data = Uint8List(bytes.length - _header);
      for (var i = 0; i < data.length; i++) {
        data[i] = bytes[_header + i] ^ rng.next();
      }
      final expected = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
      if (_checksum(data) != expected) return null;
      return utf8.decode(data);
    } catch (_) {
      return null;
    }
  }

  static int _seed(String value) {
    var hash = 0x811C9DC5;
    for (final b in utf8.encode(value)) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash == 0 ? 0x9E3779B9 : hash;
  }

  static int _checksum(List<int> data) {
    var hash = 0x811C9DC5;
    for (final b in data) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

class _KeyStream {
  _KeyStream(int seed) : _state = seed & 0xFFFFFFFF;
  int _state;

  int next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state & 0xFF;
  }
}
