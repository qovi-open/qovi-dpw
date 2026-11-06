// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// uid128_crypto.dart — Port de UID128_Encode_s64/UID128_Decode_b (Fid_Cmp_Pub.txt)
//
// Structure validée empiriquement le 09.07.2026 contre un vecteur de test réel
// (voir RoadLog) :
//   - Clé = 16 octets bruts du 128-bit UUID (pas de dérivation)
//   - Message clair = CRC32(Clr_s) en 8 car. hexa minuscule (ASCII) + Clr_s
//   - AES-128-CBC, padding PKCS7
//   - IV aléatoire 16 octets, PRÉFIXÉ au ciphertext (IV + CT), puis Base64
//
// Dépendance : pointycastle (voir pubspec.yaml)

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class Uid128Crypto {
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

  /// Équivalent CRC32_Run_s — 8 caractères hexa minuscules
  static String crc32Hex(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      final index = (crc ^ b) & 0xFF;
      crc = (crc >> 8) ^ _crc32Table[index];
    }
    crc = crc ^ 0xFFFFFFFF;
    return (crc & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  }

  /// Accepte un UID avec ou sans tirets (128 bits = 32 caractères hexa)
  static Uint8List _keyBytes(String keyU) {
    final hex = keyU.replaceAll('-', '');
    return Uint8List.fromList(List<int>.generate(
      16,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ));
  }

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
  }

  /// Équivalent UID128_Encode_s64(Clr_s, Key_U)
  static String encode(String clrS, String keyU) {
    final keyBytes = _keyBytes(keyU);
    final chkS = crc32Hex(utf8.encode(clrS));
    final message = Uint8List.fromList(utf8.encode(chkS + clrS));
    final iv = _randomBytes(16);

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

  /// Équivalent UID128_Decode_b — retourne null si CRC ou padding invalide
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
      return null; // padding invalide, décryptage échoué
    }
  }
}
