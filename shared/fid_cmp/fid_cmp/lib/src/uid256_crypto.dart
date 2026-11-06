// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// uid256_crypto.dart — Port de UID256_Encode_s64/UID256_Decode_b (WLangage).
// Même structure qu'Uid128Crypto (CRC32 + clair, AES-CBC/PKCS7, IV préfixé,
// Base64) mais clé 256 bits (32 octets) au lieu de 128 — utilisé pour CH3
// (Cod_U, reçu du PuB via o_MoB_Hii_x).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class Uid256Crypto {
  static final _crc32Table = _buildCrc32Table();

  static List<int> _buildCrc32Table() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var j = 0; j < 8; j++) {
        crc = (crc & 1 != 0) ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
      table[i] = crc & 0xFFFFFFFF;
    }
    return table;
  }

  static String crc32Hex(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      final index = (crc ^ b) & 0xFF;
      crc = (crc >> 8) ^ _crc32Table[index];
    }
    crc = crc ^ 0xFFFFFFFF;
    return (crc & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  }

  /// Accepte une clé 256 bits en hex (64 car.), avec ou sans tirets.
  static Uint8List _keyBytes(String keyU) {
    final hex = keyU.replaceAll('-', '');
    return Uint8List.fromList(List<int>.generate(
      32,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ));
  }

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
  }

  /// Équivalent UID256_Encode_s64(Clr_s, Key_U)
  static String encode(String clrS, String keyU) {
    final keyBytes = _keyBytes(keyU);
    final chkS = crc32Hex(utf8.encode(clrS));
    final message = Uint8List.fromList(utf8.encode(chkS + clrS));
    final iv = _randomBytes(16); // taille de bloc AES = toujours 16, quelle que soit la clé

    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    cipher.init(
      true,
      PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(keyBytes), iv), null),
    );
    final ct = cipher.process(message);

    final out = Uint8List(16 + ct.length)
      ..setRange(0, 16, iv)
      ..setRange(16, 16 + ct.length, ct);
    return base64.encode(out);
  }

  /// Équivalent UID256_Decode_b — retourne null si CRC ou padding invalide
  static String? decode(String codS64, String keyU) {
    try {
      final keyBytes = _keyBytes(keyU);
      final raw = base64.decode(codS64);
      if (raw.length < 16) return null;
      final iv = raw.sublist(0, 16);
      final ct = Uint8List.fromList(raw.sublist(16));

      final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
      cipher.init(
        false,
        PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(keyBytes), iv), null),
      );
      final got = cipher.process(ct);

      if (got.length < 8) return null;
      final gotChkS = utf8.decode(got.sublist(0, 8));
      final decS = utf8.decode(got.sublist(8));
      if (gotChkS != crc32Hex(utf8.encode(decS))) return null;
      return decS;
    } catch (_) {
      return null;
    }
  }
}
