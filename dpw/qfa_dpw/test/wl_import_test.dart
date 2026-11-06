// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER wl_import_test.dart · 2026-11-01 · lot 2k
// Import de l'ancien trousseau WL : texte ANSI (Windows-1252) et controle
// Murmur3, comme UID256_Decode_b.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fid_cmp/fid_cmp.dart' show Uid256Crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:qfa_dpw/core/rand.dart';
import 'package:qfa_dpw/vault/vault.dart';

/// Chiffre comme WL : base64( IV + AES-256-CBC( chk(8) + clair ) ).
String wlEncrypt(List<int> clr, String chk, String keyHex) {
  final rnd = Random.secure();
  final iv = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
  final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(true, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(hexToBytes(keyHex)), iv), null));
  final ct = c.process(Uint8List.fromList([...ascii.encode(chk), ...clr]));
  return base64.encode([...iv, ...ct]);
}

void main() {
  final key = randHex(32);
  // « Clé » et « l’accès » en Windows-1252 : é = 0xE9, ’ = 0x92.
  final json = '{"Cod":[{"Nam":{"s":"Cl\u00e9"},"Who":{"s":"marc"},"Pass":{"s":"x"},"Cmt":{"s":"l\u2019acc\u00e8s"}}]}';
  final ansi = json.codeUnits.map((u) => u == 0x2019 ? 0x92 : u).toList();

  test('Murmur3 32 : valeurs de reference', () {
    expect(wlMurmur3(ascii.encode('hello')), 0x248bfa47);
    expect(wlMurmur3(<int>[]), 0);
    expect(wlMurmur3(ascii.encode('Hello, world!')), 0xc0363e43);
  });

  test('ANSI + CRC32 (sur les octets)', () {
    final b64 = wlEncrypt(ansi, Uid256Crypto.crc32Hex(ansi), key);
    final l = decodeWl(b64, key);
    expect(l.single.nam, 'Clé');
    expect(l.single.note, 'l’accès');
  });

  test('ANSI + Murmur3 en majuscules', () {
    final m = wlMurmur3(ansi).toRadixString(16).padLeft(8, '0').toUpperCase();
    final l = decodeWl(wlEncrypt(ansi, m, key), key);
    expect(l.single.nam, 'Clé');
  });

  test('UTF-8 + CRC32 (comme avant)', () {
    final u = utf8.encode(json);
    expect(decodeWl(wlEncrypt(u, Uid256Crypto.crc32Hex(u), key), key).single.note, 'l’accès');
  });

  test('controle inconnu mais JSON de trousseau : accepte', () {
    final l = decodeWl(wlEncrypt(ansi, 'e5a22964', key), key);
    expect(l.single.nam, 'Clé');
  });

  test('controle inconnu et pas un trousseau : refus', () {
    expect(wlDecrypt(wlEncrypt(ascii.encode('{"x":1}'), 'e5a22964', key), key), isNull);
  });

  test('mauvaise cle : refus', () {
    final b64 = wlEncrypt(ansi, Uid256Crypto.crc32Hex(ansi), key);
    expect(wlDecrypt(b64, randHex(32)), isNull);
  });
}
