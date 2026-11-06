// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER merge_test.dart · 2026-11-01 · lot 2 synchro DpW
// Tests de la fusion (regle B) et du contenu v3 du trousseau : flutter test.
import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/rand.dart';
import 'package:qfa_dpw/sync/merge.dart';
import 'package:qfa_dpw/vault/entry.dart';
import 'package:qfa_dpw/vault/vault.dart';

final t1 = DateTime.utc(2026, 10, 1, 8);
final t2 = DateTime.utc(2026, 10, 2, 8);
final t3 = DateTime.utc(2026, 10, 3, 8);
final now = DateTime.utc(2026, 11, 1);

/// Entree deja synchronisee (syn = son empreinte).
Entry synced(String id, String nam, String pass, DateTime mod) {
  final e = Entry(id: id, nam: nam, pass: pass, mod: mod, use: mod);
  e.syn = e.hash;
  return e;
}

/// Contenu comparable, pour verifier la convergence des deux appareils.
List<String> view(VaultData d) =>
    [for (final e in d.cod) '${e.id}|${e.nam}|${e.pass}']..sort();

void main() {
  test('une modification d\'un seul cote est reprise', () {
    final a = synced('01', 'Banque', 'p1', t1);
    final b = synced('01', 'Banque', 'p1', t1)
      ..pass = 'p2'
      ..mod = t2;
    final r = mergeVaults(VaultData([a]), VaultData([b]), now: now);
    expect(r.data.cod.single.pass, 'p2');
    expect(r.stats.changed, 1);
    expect(r.stats.copies, 0);
  });

  test('modifiee des deux cotes : on garde les deux (copie datee)', () {
    final a = synced('01', 'Banque', 'p1', t1)
      ..pass = 'pA'
      ..mod = t2;
    final b = synced('01', 'Banque', 'p1', t1)
      ..pass = 'pB'
      ..mod = t3;
    final r = mergeVaults(VaultData([a]), VaultData([b]), now: now);
    expect(r.data.cod.length, 2);
    expect(r.data.cod.firstWhere((e) => e.id == '01').pass, 'pB'); // la plus recente
    final c = r.data.cod.firstWhere((e) => e.id != '01');
    expect(c.pass, 'pA');
    expect(c.nam, startsWith('Banque (copie du 2026-10-02'));
    expect(r.stats.copies, 1);
  });

  test('la fusion est symetrique : les deux appareils convergent', () {
    final a = [
      synced('01', 'Banque', 'p1', t1)..pass = 'pA'..mod = t2,
      synced('02', 'Mail', 'm1', t1),
      Entry(id: '03', nam: 'Neuf A', pass: 'x', mod: t2),
    ];
    final b = [
      synced('01', 'Banque', 'p1', t1)..pass = 'pB'..mod = t3,
      Entry(id: '04', nam: 'Neuf B', pass: 'y', mod: t3),
    ];
    final ab = mergeVaults(VaultData(a.map((e) => e.copy()).toList(), [Tomb('99', t1)]),
        VaultData(b.map((e) => e.copy()).toList(), [Tomb('02', t3)]), now: now);
    final ba = mergeVaults(VaultData(b.map((e) => e.copy()).toList(), [Tomb('02', t3)]),
        VaultData(a.map((e) => e.copy()).toList(), [Tomb('99', t1)]), now: now);
    expect(view(ab.data), view(ba.data));
  });

  test('une suppression se propage', () {
    final a = synced('01', 'Vieux', 'p', t1);
    final r = mergeVaults(VaultData([a]), VaultData([], [Tomb('01', t2)]), now: now);
    expect(r.data.cod, isEmpty);
    expect(r.stats.removed, 1);
    expect(r.data.del.single.id, '01');
  });

  test('modifiee APRES la suppression ailleurs : on la garde', () {
    final a = synced('01', 'Vieux', 'p', t1)
      ..pass = 'p2'
      ..mod = t3;
    final r = mergeVaults(VaultData([a]), VaultData([], [Tomb('01', t2)]), now: now);
    expect(r.data.cod.single.pass, 'p2');
  });

  test('meme contenu sous deux identifiants (double import) : une seule entree', () {
    final a = Entry(id: '0a', nam: 'Banque', pass: 'p', mod: t1);
    final b = Entry(id: '0b', nam: 'Banque', pass: 'p', mod: t2);
    final r = mergeVaults(VaultData([a]), VaultData([b]), now: now);
    expect(r.data.cod.single.id, '0a');
  });

  test('traces de suppression expirees apres 1 an', () {
    final old = Tomb('01', now.subtract(const Duration(days: 366)));
    final young = Tomb('02', now.subtract(const Duration(days: 10)));
    final r = mergeVaults(VaultData([], [old, young]), VaultData([]), now: now);
    expect(r.data.del.map((t) => t.id), ['02']);
  });

  test('apres fusion, toutes les entrees sont marquees synchronisees', () {
    final r = mergeVaults(VaultData([Entry(id: '01', nam: 'A', mod: t1)]), VaultData([]), now: now);
    expect(r.data.cod.single.syn, r.data.cod.single.hash);
  });

  test('contenu v3 : aller-retour avec traces ; v2 lu sans traces', () {
    final key = vaultKey(randHex(32));
    final b3 = encodeVault(VaultData([Entry(nam: 'A')], [Tomb('x', t1)]), key);
    final d = decodeVault(b3, key);
    expect(d.cod.single.nam, 'A');
    expect(d.del.single.id, 'x');
    final b2 = encodeV2([Entry(nam: 'B')], key);
    expect(decodeVault(b2, key).cod.single.nam, 'B');
  });
}
