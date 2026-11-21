// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER lot17_test.dart · 2026-11-10 · lot 17
// Filtre avec exclusion (W3), dates de creation (W7), filtres synchronises (W2).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/sync/merge.dart';
import 'package:qfa_dpw/ui/app_state.dart';
import 'package:qfa_dpw/vault/entry.dart';

void main() {
  final t1 = DateTime.utc(2026, 1, 1), t2 = DateTime.utc(2026, 6, 1), t3 = DateTime.utc(2026, 9, 1);
  final now = DateTime.utc(2026, 11, 10);

  test('filtre : ET dans tous les ordres, « -mot » exclut', () {
    const txt = 'Qovi FTP\nserveur _qovi ftp';
    expect(matchFilter('_qovi ftp', txt), isTrue);
    expect(matchFilter('ftp _qovi', txt), isTrue);
    expect(matchFilter('ftp -serveur', txt), isFalse);
    expect(matchFilter('banque -test', 'Banque cantonale\ne-banking'), isTrue);
    expect(matchFilter('banque -test', 'Banque test\ncompte de test'), isFalse);
    expect(matchFilter('-', txt), isTrue);
  });

  test('date de creation : la plus ancienne connue, une absence ne gagne pas', () {
    final a = Entry(id: '01', nam: 'A', pass: 'p', mod: t2, cre: t2);
    final b = Entry(id: '01', nam: 'A', pass: 'p', mod: t3, cre: t1);
    expect(mergeVaults(VaultData([a]), VaultData([b]), now: now).data.cod.single.cre, t1);
    final c = Entry(id: '01', nam: 'A', pass: 'p', mod: t3);
    expect(mergeVaults(VaultData([a.copy()]), VaultData([c]), now: now).data.cod.single.cre, t2);
  });

  test('cre survit au JSON ; absente reste absente', () {
    final e = Entry(nam: 'A', cre: t1);
    expect(Entry.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map).cre, t1);
    expect(Entry.fromJson(jsonDecode(jsonEncode(Entry(nam: 'B').toJson())) as Map).cre, isNull);
  });

  test('filtres : le plus recent gagne, la destruction se propage, un ancien appareil ne les efface pas', () {
    final fa = Flt('f1', 'banque', t1, t1);
    final fb = Flt('f1', 'banque -test', t2, t2);
    final r = mergeVaults(VaultData([], [], [fa]), VaultData([], [], [fb]), now: now).data;
    expect(r.flt.single.txt, 'banque -test');
    final gone = mergeVaults(VaultData([], [], [fb]), VaultData([], [], [], [Tomb('f1', t3)]), now: now).data;
    expect(gone.flt, isEmpty);
    expect(gone.fdel.single.id, 'f1');
    final old = mergeVaults(VaultData([], [], [fb]), VaultData([]), now: now).data;
    expect(old.flt.single.id, 'f1');
  });

  test('VaultData : aller-retour JSON avec filtres', () {
    final d = VaultData([Entry(nam: 'A', cre: t1)], [], [Flt('f1', 'x', t1, t2)], [Tomb('f9', t3)]);
    final back = VaultData.fromJson(jsonDecode(jsonEncode(d.toJson())))!;
    expect(back.flt.single.use, t2);
    expect(back.fdel.single.id, 'f9');
    expect(back.cod.single.cre, t1);
  });
}
