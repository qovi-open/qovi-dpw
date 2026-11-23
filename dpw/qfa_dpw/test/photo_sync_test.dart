// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER photo_sync_test.dart · 2026-11-19 · lot 22 (W14 etape 2 : photos dans la synchro)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/sync/merge.dart';
import 'package:qfa_dpw/sync/mov.dart';
import 'package:qfa_dpw/vault/card_store.dart';

final String k = 'ab' * 32;
final String k2 = 'cd' * 32;
final String id1 = '1' * 32;
final String id2 = '2' * 32;

Uint8List fakeJpeg(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = (i * 31 + 7) & 0xFF;
  }
  b[0] = 0xFF;
  b[1] = 0xD8;
  b[2] = 0xFF;
  return b;
}

void main() {
  test('le bloc porte la liste des photos, triee et filtree', () {
    final b = sealBlob(VaultData([]), k, img: [id2, id1, id1]);
    final (d, img) = openBlobImg(b, k);
    expect(d.cod, isEmpty);
    expect(img, {id1, id2});
  });

  test('bloc d\'une version 3.5 (sans img) : null, pas d\'erreur', () {
    final (_, img) = openBlobImg(sealBlob(VaultData([]), k), k);
    expect(img, isNull);
  });

  test('une photo de plusieurs morceaux est reassemblee a l\'identique', () {
    final jpeg = fakeJpeg(kPhotoChunk * 2 + 1234);
    final fs = photoFrames(id1, jpeg, k);
    expect(fs.length, 3);
    final j = PhotoJoin(k);
    expect(j.add(fs[2]), isNull);
    expect(j.add(fs[0]), isNull);
    final r = j.add(fs[1]);
    expect(r!.$1, id1);
    expect(r.$2, jpeg);
    for (final f in fs) {
      expect(f.length, lessThan(699052)); // borne du serveur (512 Ko en base64)
    }
  });

  test('mauvaise cle, identifiant echange ou morceau altere : refuse', () {
    final jpeg = fakeJpeg(1000);
    final f = photoFrames(id1, jpeg, k).single;
    expect(PhotoJoin(k2).add(f), isNull);
    final m = jsonDecode(f) as Map<String, dynamic>;
    expect(PhotoJoin(k).add(jsonEncode({...m, 'i': id2})), isNull);
    expect(PhotoJoin(k).add(jsonEncode({...m, 'i': '../../etc'})), isNull);
    final d = base64.decode(m['d'] as String);
    d[20] ^= 1;
    expect(PhotoJoin(k).add(jsonEncode({...m, 'd': base64.encode(d)})), isNull);
  });

  test('ce qui n\'est pas un JPEG ou est trop gros n\'est pas accepte', () {
    final notJpeg = Uint8List.fromList(List.filled(500, 7));
    expect(PhotoJoin(k).add(photoFrames(id1, notJpeg, k).single), isNull);
    expect(photoFrames(id1, fakeJpeg(kPhotoMax + 1), k), isEmpty);
  });

  test('plan : chacun envoie ce qui manque a l\'autre', () {
    final used = {id1, id2, '3' * 32};
    final a = PhotoPlan.of(used, {id1, '3' * 32}, {id2, '3' * 32});
    expect(a.send, [id1]);
    expect(a.get, {id2});
    final s = PhotoPlan.of(used, {id2, '3' * 32}, {id1, '3' * 32});
    expect(s.send, [id2]);
    expect(s.get, {id1});
    expect(PhotoPlan.of(used, {id1}, null).isEmpty, isTrue); // autre en 3.5
    expect(PhotoPlan.of({id1}, {id1}, {id1}).isEmpty, isTrue);
  });

  test('putAs range la photo sous son identifiant, sans ecraser', () async {
    final dir = await Directory.systemTemp.createTemp('dpw_ph');
    try {
      final cs = CardStore(dir.path, 'ef' * 32);
      final jpeg = fakeJpeg(800);
      await cs.putAs(id1, jpeg);
      expect(await cs.get(id1), jpeg);
      await cs.putAs(id1, fakeJpeg(900));
      expect((await cs.get(id1))!.length, 800);
      await expectLater(cs.putAs('../x', jpeg), throwsArgumentError);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
