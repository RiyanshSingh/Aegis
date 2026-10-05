import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class VaultCrypto {
  static enc.Key _deriveKey(String password, List<int> salt, {int iterations = 10000}) {
    List<int> current = utf8.encode(password) + salt;
    for (int i = 0; i < iterations; i++) {
      current = sha256.convert(current).bytes;
    }
    return enc.Key(Uint8List.fromList(current));
  }

  static String encrypt({required String plainText, required String password}) {
    final saltBytes = enc.SecureRandom(16).bytes;
    final iv = enc.IV.fromSecureRandom(16);
    const int iterations = 10000;
    final key = _deriveKey(password, saltBytes, iterations: iterations);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    final mac = Hmac(sha256, key.bytes).convert(encrypted.bytes).toString();

    final envelope = {
      'app': 'SecureVault',
      'format': 'AES-256-CBC',
      'version': 2,
      'iterations': iterations,
      'timestamp': DateTime.now().toIso8601String(),
      'salt': base64Encode(saltBytes),
      'iv': iv.base64,
      'ciphertext': encrypted.base64,
      'mac': mac,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  static String? decrypt({required String encryptedJson, required String password}) {
    try {
      final Map<String, dynamic> envelope = jsonDecode(encryptedJson);
      if (envelope['app'] != 'SecureVault' || envelope['ciphertext'] == null || envelope['salt'] == null || envelope['iv'] == null) {
        return null;
      }
      final saltBytes = base64Decode(envelope['salt']);
      final int iterations = (envelope['iterations'] as int?) ?? 1;
      final key = _deriveKey(password, saltBytes, iterations: iterations);
      final iv = enc.IV.fromBase64(envelope['iv']);
      final ciphertext = envelope['ciphertext'];

      if (envelope['mac'] != null) {
        final expectedMac = Hmac(sha256, key.bytes).convert(base64Decode(ciphertext)).toString();
        if (expectedMac != envelope['mac']) {
          return null;
        }
      }

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt64(ciphertext, iv: iv);
      return decrypted;
    } catch (_) {
      return null;
    }
  }
}
