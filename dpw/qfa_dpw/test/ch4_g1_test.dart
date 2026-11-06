// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER ch4_g1_test.dart · 2026-11-02 · lot 4b
// Vecteurs CH4 « G1 » publies par TLP le 02.11 (verifies aussi hors Dart).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/alone.dart';
import 'package:qfa_dpw/core/g1.dart';

void main() {
  const nap = '00112233-4455-6677-8899-aabbccddeeff';
  const kid = 'a4f924e70fae786bef2ae0474f7d8ecb';
  final k = g1Key(nap, kG1Ch4);
  final n = Uint8List.fromList(List.generate(12, (i) => i));

  test('kid et cle', () {
    expect(ch4Kid(nap), kid);
    expect(k.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'decab4d165d801e21955e9d913fe92531dc53bd71d404103c0e4ce95da710893');
  });

  test('1re trame : kid + G1(i:1), sans la cle en clair', () {
    final f = ch4First(k, kid, nonce: n);
    expect(f, '${kid}G1AAECAwQFBgcICQoLnF+p2QbBTdq7+MXTrq70yJOM2J+2K2KwOwYfA07NbuOYml+t');
    expect(f.contains('00112233'), isFalse);
  });

  test('reponse du serveur', () {
    expect(ch4Open(k, kid, 'G1AAECAwQFBgcICQoLnF+akkyYCo276cXT5/Hg/6TTBvdkE3yTV0NxV0SKlg=='),
        '{"Tip":{"r":2}}');
  });

  test('reponse alteree ou dans le mauvais sens : refusee', () {
    const rep = 'G1AAECAwQFBgcICQoLnF+akkyYCo276cXT5/Hg/6TTBvdkE3yTV0NxV0SKlg==';
    expect(ch4Open(k, kid, rep.replaceFirst('nF', 'nG')), isNull);
    expect(g1Open(k, 'ch4q|$kid', rep), isNull);
    expect(ch4Open(k, 'ffffffffffffffffffffffffffffffff', rep), isNull);
  });
}
