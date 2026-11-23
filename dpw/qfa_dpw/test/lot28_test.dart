// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER lot28_test.dart · 2026-11-20 · lot 30 (identifiant impose ; lot 28 : numero du refus, bouton Ouvrir Qovi)
import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/alone.dart';
import 'package:qfa_dpw/txt.dart';

void main() {
  test('numero du refus lu dans Tip.t', () {
    expect(AloneClient.tipNo({'Tip': {'r': 1, 't': [575, '%Edr', 'a@b.ch']}}), 575);
    expect(AloneClient.tipNo({'Tip': {'r': 1, 't': ['441']}}), 441);
    expect(AloneClient.tipNo({'Tip': {'r': 1, 's': 'x'}}), isNull);
    expect(AloneClient.tipNo({'a': 1}), isNull);
  });

  test('lot 30 : identifiant impose seulement s\'il a la forme d\'un UUID', () {
    const u = '0123abcd-4567-89ab-cdef-0123456789ab';
    expect(AloneClient.preAct(u), u);
    expect(AloneClient.preAct(null), isNull);
    expect(AloneClient.preAct('x&v=ok'), isNull);
    expect(AloneClient.preAct('0123ABCD-4567-89ab-cdef-0123456789ab'), isNull);
  });

  test('AloneError garde le numero', () {
    expect(AloneError('x', tip: 575).tip, 575);
    expect(AloneError('x').tip, isNull);
  });

  test('texte du bouton dans les 4 langues', () {
    final was = lang;
    for (final l in Lang.values) {
      lang = l;
      expect(T.qoviOpenRetry, contains('Qovi'));
    }
    lang = was;
  });
}
