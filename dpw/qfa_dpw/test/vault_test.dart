// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER vault_test.dart · 2026-11-20 · lot 27 (tests de l'ancien format WL retires)
// Tests du trousseau, sans reseau : flutter test.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/rand.dart';
import 'package:qfa_dpw/vault/entry.dart';
import 'package:qfa_dpw/vault/vault.dart';

void main() {
  late Directory dir;
  final sok = randHex(32);

  setUp(() async => dir = await Directory.systemTemp.createTemp('dpw_test_'));
  tearDown(() async => dir.delete(recursive: true));

  File f(String n) => File('${dir.path}${Platform.pathSeparator}$n');

  test('v2 : aller-retour', () {
    final key = vaultKey(sok);
    final b = encodeV2([Entry(nam: 'A', who: 'moi', pass: 'p1')], key);
    final l = decodeV2(b, key);
    expect(l.single.nam, 'A');
    expect(l.single.pass, 'p1');
  });

  test('v2 : mauvaise cle refusee', () {
    final b = encodeV2([Entry(nam: 'A')], vaultKey(sok));
    expect(() => decodeV2(b, vaultKey(randHex(32))), throwsA(isA<VaultError>()));
  });

  test('v2 : fichier modifie refuse (GCM)', () {
    final key = vaultKey(sok);
    final b = encodeV2([Entry(nam: 'A')], key);
    final t = Uint8List.fromList(b)..[b.length - 20] ^= 1;
    expect(() => decodeV2(t, key), throwsA(isA<VaultError>()));
  });

  test('fichier illisible : jamais ecrase', () async {
    final b = encodeV2([Entry(nam: 'A')], vaultKey(randHex(32)));
    await f(kVaultV2).writeAsBytes(b);
    final v = Vault(dir.path, sok);
    await expectLater(v.open(), throwsA(isA<VaultError>()));
    expect(await f(kVaultV2).readAsBytes(), b);
  });

  test('3 sauvegardes au plus', () async {
    final v = Vault(dir.path, sok);
    await v.open();
    for (var i = 0; i < 6; i++) {
      await v.upsert(Entry(nam: 'n$i'));
    }
    expect(await f('$kVaultV2.bak3').exists(), isTrue);
    expect(await f('$kVaultV2.bak4').exists(), isFalse);
  });

  test('modification par un autre poste : fusion par identifiant', () async {
    final a = Vault(dir.path, sok);
    await a.open();
    final b = Vault(dir.path, sok);
    await b.open();
    await a.upsert(Entry(nam: 'du poste A'));
    await b.upsert(Entry(nam: 'du poste B'));
    final c = Vault(dir.path, sok);
    await c.open();
    expect(c.entries.map((e) => e.nam).toSet(), {'du poste A', 'du poste B'});
  });

  test('mot de passe genere : 32 hexa + @Ab0', () {
    expect(RegExp(r'^[0-9a-f]{32}@Ab0$').hasMatch(Entry.newPassword()), isTrue);
  });
}
