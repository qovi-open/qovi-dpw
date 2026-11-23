// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER card_test.dart · 2026-11-19 · lot 20 (W14 : photo de carte)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qfa_dpw/sync/merge.dart';
import 'package:qfa_dpw/ui/card_cam.dart';
import 'package:qfa_dpw/vault/card_store.dart';
import 'package:qfa_dpw/vault/entry.dart';
import 'package:qfa_dpw/vault/vault.dart';

const String _sok = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const String _id1 = '0123456789abcdef0123456789abcdef';
const String _id2 = 'fedcba9876543210fedcba9876543210';

void main() {
  group('Entry (references de carte, champs inconnus)', () {
    test('aller-retour JSON : crd et champs inconnus gardes', () {
      final e = Entry.fromJson({
        'id': 'a1', 'nam': 'Visa', 'crd': [_id1, _id2], 'zzz': {'futur': 1}, //
      });
      expect(e.crd, [_id1, _id2]);
      final j = jsonDecode(jsonEncode(e.toJson())) as Map;
      expect(j['crd'], [_id1, _id2]);
      expect(j['zzz'], {'futur': 1});
      expect(Entry.fromJson(j).toJson()['zzz'], {'futur': 1});
    });

    test('references invalides, doublons et 3e face ignores (chemins surs)', () {
      final e = Entry.fromJson({
        'id': 'a1', 'crd': ['../../etc/passwd', _id1, _id1, 'ABCDEF0123456789ABCDEF0123456789', _id2, 'ffffffffffffffffffffffffffffffff'], //
      });
      expect(e.crd, [_id1, _id2]);
    });

    test('sans carte, empreinte identique aux versions precedentes', () {
      final e = Entry(id: 'a1', nam: 'n', url: 'u', who: 'w', pass: 'p', note: 'o');
      final old = sha256.convert(utf8.encode(jsonEncode(['n', 'u', 'w', 'p', 'o']))).toString();
      expect(e.hash, old);
      expect((e.copy()..crd = [_id1]).hash, isNot(old));
    });

    test('pas de cle crd dans le JSON sans carte', () {
      expect(Entry(id: 'a1').toJson().containsKey('crd'), isFalse);
    });
  });

  group('Chiffrement des photos', () {
    final key = cardKey(_sok);
    final jpeg = Uint8List.fromList(List<int>.generate(5000, (i) => i % 251));

    test('aller-retour', () {
      expect(openCard(sealCard(jpeg, _id1, key), _id1, key), jpeg);
    });

    test('fichier echange (autre identifiant) ou mauvaise cle : refuse', () {
      final b = sealCard(jpeg, _id1, key);
      expect(openCard(b, _id2, key), isNull);
      expect(openCard(b, _id1, cardKey('ff${_sok.substring(2)}')), isNull);
    });

    test('cle des photos distincte de celle du trousseau', () {
      expect(cardKey(_sok), isNot(vaultKey(_sok)));
    });
  });

  group('CardStore et Vault (suppression locale seulement)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('dpw_card_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('put / get / drop ; identifiant invalide sans effet', () async {
      final s = CardStore(tmp.path, _sok);
      final id = await s.put(Uint8List.fromList([1, 2, 3]));
      expect(kCardId.hasMatch(id), isTrue);
      expect(s.has(id), isTrue);
      expect(await s.get(id), [1, 2, 3]);
      expect(await s.get('../x'), isNull);
      expect(s.has('../x'), isFalse);
      await s.drop(id);
      expect(s.has(id), isFalse);
    });

    test('photo partagee par une copie : gardee tant qu’une fiche y fait reference', () async {
      final v = Vault(tmp.path, _sok);
      await v.open();
      final id = await v.cards.put(Uint8List.fromList([9]));
      await v.upsert(Entry(id: 'e1', nam: 'a', crd: [id]));
      await v.upsert(Entry(id: 'e2', nam: 'b', crd: [id]));
      await v.delete('e1');
      expect(v.cards.has(id), isTrue);
      await v.delete('e2');
      expect(v.cards.has(id), isFalse);
    });

    test('photo remplacee a l’enregistrement : l’ancienne disparait', () async {
      final v = Vault(tmp.path, _sok);
      await v.open();
      final a = await v.cards.put(Uint8List.fromList([1]));
      final b = await v.cards.put(Uint8List.fromList([2]));
      await v.upsert(Entry(id: 'e1', crd: [a]));
      await v.upsert(Entry(id: 'e1', crd: [b]));
      expect(v.cards.has(a), isFalse);
      expect(v.cards.has(b), isTrue);
    });

    test('la synchro ne supprime aucun fichier photo', () async {
      final v = Vault(tmp.path, _sok);
      await v.open();
      final id = await v.cards.put(Uint8List.fromList([7]));
      await v.upsert(Entry(id: 'e1', crd: [id]));
      // Un appareil ancien renvoie la fiche sans references (et plus recente).
      final remote = Entry(id: 'e1', mod: DateTime.now().toUtc().add(const Duration(minutes: 1)));
      await v.applyRemote(VaultData([remote]));
      expect(v.cards.has(id), isTrue);
    });
  });

  test('copie de conflit : garde les photos de la version perdante', () {
    final t = DateTime.utc(2026, 11, 19);
    final a = Entry(id: 'e1', nam: 'A', mod: t, crd: [_id1]);
    final b = Entry(id: 'e1', nam: 'B', mod: t.add(const Duration(minutes: 1)), crd: [_id2]);
    final r = mergeVaults(VaultData([a]), VaultData([b]), now: t);
    expect(r.data.cod.length, 2);
    final copy = r.data.cod.firstWhere((e) => e.id != 'e1');
    expect(copy.crd, [_id1]);
    expect(r.data.cod.firstWhere((e) => e.id == 'e1').crd, [_id2]);
  });

  test('redressement : 1200 x 757, JPEG sans EXIF', () {
    final src = img.Image(width: 1600, height: 1200);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    final jpeg = img.encodeJpg(src, quality: 90);
    final out = rectifyForTest(jpeg, [100, 100, 1500, 120, 1480, 1000, 120, 980]);
    expect(out, isNotNull);
    final d = img.decodeJpg(out!)!;
    expect(d.width, kCardW);
    expect(d.height, kCardH);
    expect(latin1.decode(out, allowInvalid: true).contains('Exif\u0000\u0000'), isFalse);
  });
}
