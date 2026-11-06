// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER rand.dart · 2026-10-30 · lot 1 client DpW
import 'dart:math';
import 'dart:typed_data';

final Random _rnd = Random.secure();

Uint8List randBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _rnd.nextInt(256)));

/// n octets aleatoires en hexa (2n caracteres, minuscules).
String randHex(int n) =>
    randBytes(n).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// UUID v4 avec tirets (etiquette de suivi g.u).
String randUuid() {
  final b = randBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

Uint8List hexToBytes(String hex) {
  final h = hex.replaceAll('-', '');
  if (h.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(h)) {
    throw const FormatException('hexa invalide');
  }
  return Uint8List.fromList(List<int>.generate(
      h.length ~/ 2, (i) => int.parse(h.substring(2 * i, 2 * i + 2), radix: 16)));
}
