// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER vault_test.dart · 2026-10-30 · lot 1c (suppression des anciens fichiers apres import)
// Tests du trousseau, sans reseau : flutter test.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fid_cmp/fid_cmp.dart' show Uid256Crypto;
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

  test('ancien trousseau WL : lu, converti, jamais modifie', () async {
    final wl = jsonEncode({
      'Cod': [
        {
          'Nam': {'s': 'Banque'},
          'Whe': {'s': 'https://banque.example'},
          'Who': {'s': 'marc'},
          'Pass': {'s': 'secret'},
          'Cmt': {'s': ''},
          'Mod': {'t': '20250102T030405'},
          'Use': {'t': '2025-01-02 03:04:05'},
        }
      ],
      'Sel': {'i': 1},
    });
    final txt = Uid256Crypto.encode(wl, sok);
    await f(kVaultWl).writeAsString(txt);
    final v = Vault(dir.path, sok);
    await v.open();
    expect(v.convertedFromWl, isTrue);
    expect(v.entries.single.nam, 'Banque');
    expect(v.entries.single.use, DateTime.utc(2025, 1, 2, 3, 4, 5));
    expect(await f(kVaultV2).exists(), isTrue);
    expect(await f(kVaultWl).readAsString(), txt);
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

  test('ancien trousseau avec une autre cle : ouverture en v2 vide, puis import', () async {
    final oldKey = randHex(32);
    final wl = jsonEncode({
      'Cod': [
        {'Nam': {'s': 'Mail'}, 'Who': {'s': 'marc'}, 'Pass': {'s': 'x'}},
        {'Nam': {'s': 'Banque'}, 'Who': {'s': 'm'}, 'Pass': {'s': 'y'}},
      ]
    });
    final txt = Uid256Crypto.encode(wl, oldKey);
    await f(kVaultWl).writeAsString(txt);
    await f('_DpW+.aes').writeAsString(txt);
    await f('_DpW++.aes').writeAsString(txt);
    await f('autre.aes').writeAsString('garde');
    final v = Vault(dir.path, sok);
    await v.open();
    expect(v.convertedFromWl, isFalse);
    expect(v.entries, isEmpty);
    expect(v.hasWl, isTrue);
    await expectLater(v.importWl(randHex(32)), throwsA(isA<VaultError>()));
    expect(await f(kVaultWl).exists(), isTrue); // echec : rien de supprime
    expect(await v.importWl(oldKey.toUpperCase()), (2, 3));
    expect(v.entries.map((e) => e.nam).toSet(), {'Mail', 'Banque'});
    expect(v.hasWl, isFalse);
    for (final n in [kVaultWl, '_DpW+.aes', '_DpW++.aes']) {
      expect(await f(n).exists(), isFalse);
    }
    expect(await f('autre.aes').exists(), isTrue);
    expect(await f(kVaultV2).exists(), isTrue);
    final w = Vault(dir.path, sok); // relu avec la cle du compte : v2
    await w.open();
    expect(w.entries.length, 2);
  });
}
