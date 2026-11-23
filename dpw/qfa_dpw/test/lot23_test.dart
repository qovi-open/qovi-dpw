// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER lot23_test.dart · 2026-11-20 · lot 23 (W18 cadre de depart, texte du refus 575)
import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/txt.dart';
import 'package:qfa_dpw/ui/card_cam.dart';

void main() {
  test('cadre de depart : au format carte, centre, dans l\'image', () {
    for (final (w, h) in [(4000, 3000), (3000, 4000), (1200, 757), (800, 800), (5000, 1000)]) {
      final f = cardFrameFor(w, h);
      expect(f.left, greaterThanOrEqualTo(0));
      expect(f.top, greaterThanOrEqualTo(0));
      expect(f.right, lessThanOrEqualTo(1.0000001));
      expect(f.bottom, lessThanOrEqualTo(1.0000001));
      expect((f.left + f.right) / 2, closeTo(0.5, 1e-9));
      expect((f.top + f.bottom) / 2, closeTo(0.5, 1e-9));
      // rapport en pixels = rapport d'une carte
      expect(f.width * w / (f.height * h), closeTo(kCardRatio, 1e-6));
    }
  });

  test('refus 575 : un vrai texte, plus « message 575 »', () {
    expect(T.tip(575, ''), isNotNull);
    expect(T.tip(575, '')!, isNot(contains('575')));
    expect(T.tip(999, ''), isNull);
  });
}
