// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER mov_test.dart · 2026-11-01 · lot 2 synchro DpW
// Tests sans reseau du transfert : QR et bloc chiffre (flutter test).
import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/rand.dart';
import 'package:qfa_dpw/sync/merge.dart';
import 'package:qfa_dpw/sync/mov.dart';
import 'package:qfa_dpw/vault/entry.dart';

void main() {
  test('QR : aller-retour MSB + Qrc', () {
    final msb = randHex(16), qrc = randHex(16);
    final q = parseQr(qrText(msb, qrc));
    expect(q, isNotNull);
    expect(q!.$1, msb);
    expect(q.$2, qrc);
  });

  test('QR : autre contenu refuse', () {
    expect(parseQr('https://exemple.ch'), isNull);
    expect(parseQr('DPWS1234'), isNull);
    expect(parseQr('DPWS${'z' * 64}'), isNull);
  });

  test('bloc : aller-retour avec la bonne cle', () {
    final k = randHex(32);
    final d = VaultData([Entry(nam: 'Banque', pass: 'p')], [Tomb('x', DateTime.utc(2026, 10, 1))]);
    final r = openBlob(sealBlob(d, k), k);
    expect(r.cod.single.nam, 'Banque');
    expect(r.del.single.id, 'x');
  });

  test('bloc : mauvaise cle refusee (GCM)', () {
    final b = sealBlob(VaultData([Entry(nam: 'A')]), randHex(32));
    expect(() => openBlob(b, randHex(32)), throwsA(isA<SyncError>()));
  });

  test('bloc : demi-cle seule (MSB sans LSB) refusee', () {
    final msb = randHex(16), lsb = randHex(16);
    final b = sealBlob(VaultData([Entry(nam: 'A')]), '$msb$lsb');
    expect(() => openBlob(b, '$msb${randHex(16)}'), throwsA(isA<SyncError>()));
  });
}
