// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER tip_test.dart · 2026-11-16 · lot 18 (refus 441 : texte par numero, MoB.4)
import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/alone.dart';
import 'package:qfa_dpw/txt.dart';

Map<String, Object> ko(List<Object?> t) => {
      'Tip': {'r': 1, 't': t},
    };

void main() {
  setUp(() => lang = Lang.fr);

  test('441 avec %Waits : texte complet', () {
    expect(
        AloneClient.tipText(ko([441, '%Waits', '12 s', '%Edr', 'marc@gandar.ch']), T.qoviRefused),
        'Votre adresse est en cours de validation dans un autre contexte. Attendez 12 s et relancez.');
  });

  test('441 sans %Waits ou %Waits vide : 1re phrase seule', () {
    const p1 = 'Votre adresse est en cours de validation dans un autre contexte.';
    expect(AloneClient.tipText(ko([441]), T.reqRefused), p1);
    expect(AloneClient.tipText(ko([441, '%Waits', '', '%Edr', 'x']), T.reqRefused), p1);
    expect(AloneClient.tipText(ko(['441', '%Waits', null]), T.reqRefused), p1);
  });

  test('441 : valeur trop longue ou piegee ignoree', () {
    final r = AloneClient.tipText(ko([441, '%Waits', 'x' * 40]), T.reqRefused);
    expect(r, 'Votre adresse est en cours de validation dans un autre contexte.');
    final c = AloneClient.tipText(ko([441, '%Waits', '9\n s']), T.reqRefused);
    expect(c, contains('Attendez 9 s et relancez.'));
  });

  test('441 dans les 4 langues', () {
    for (final l in Lang.values) {
      lang = l;
      final r = AloneClient.tipText(ko([441, '%Waits', '5 s']), T.reqRefused);
      expect(r, contains('5 s'));
      expect(r, isNot(contains('441')));
    }
  });

  test('numero inconnu : ancien affichage avec le numero', () {
    expect(AloneClient.tipText(ko([999]), T.qoviRefused), 'Ouverture refusée par Qovi (message 999).');
  });

  test('sans Tip : repli', () {
    expect(AloneClient.tipText({'x': 1}, T.reqRefused), 'Demande refusée.');
  });
}
