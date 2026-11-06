// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER g1_test.dart · 2026-11-02 · lot 3a
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/g1.dart';

void main() {
  const base = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
  const act = '0123456789abcdef0123456789abcdef';
  final k = g1Key(base, kG1Ch5);

  test('vecteur de reference (calcule hors Dart)', () {
    final n = Uint8List.fromList(List.generate(12, (i) => i));
    expect(g1Seal(k, 'ch5q|$act', '{"a":1}', nonce: n), 'G1AAECAwQFBgcICQoLTub5wqvQ/+TSP8jaSIVbEC2aLE//h9s=');
  });

  test('aller-retour', () {
    expect(g1Open(k, 'ch5q|$act', g1Seal(k, 'ch5q|$act', 'clé')), 'clé');
  });

  test('refus : mauvais contexte, mauvaise cle, message modifie, autre format', () {
    final e = g1Seal(k, 'ch5q|$act', 'secret');
    expect(g1Open(k, 'ch5r|$act', e), isNull);
    expect(g1Open(g1Key(base, kG1Mov), 'ch5q|$act', e), isNull);
    final t = e.substring(0, 10) + (e[10] == 'A' ? 'B' : 'A') + e.substring(11);
    expect(g1Open(k, 'ch5q|$act', t), isNull);
    expect(g1Open(k, 'ch5q|$act', 'abcdef'), isNull);
    expect(isG1(e), isTrue);
    expect(isG1('0011aabb'), isFalse);
  });
}
