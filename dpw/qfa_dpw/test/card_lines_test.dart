// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER card_lines_test.dart · 2026-11-20 · lot 24 (W14c : ronds sur tout le pourtour)
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/ui/card_lines.dart';

void main() {
  const f = Rect.fromLTRB(0.1, 0.3, 0.9, 0.7);
  CardLines fresh() => CardLines.fromFrame(f, 0.05, 0.03);
  bool same(Offset a, Offset b) => (a - b).distance < 1e-9;

  test('depart sur le cadre : coins = coins du cadre', () {
    final q = fresh().corners()!;
    expect(q[0].dx, closeTo(0.1, 1e-9));
    expect(q[0].dy, closeTo(0.3, 1e-9));
    expect(q[2].dx, closeTo(0.9, 1e-9));
    expect(q[2].dy, closeTo(0.7, 1e-9));
  });

  test('ronds juste a l’interieur des bords', () {
    final (a, b) = fresh().handles(kTop);
    expect(a.dx, closeTo(0.05, 1e-9));
    expect(b.dx, closeTo(0.95, 1e-9));
    final (c, d) = fresh().handles(kLeft);
    expect(c.dy, closeTo(0.03, 1e-9));
    expect(d.dy, closeTo(0.97, 1e-9));
  });

  test('pourtour : point(paramOf(x)) = x sur le cadre, et projection dedans', () {
    final l = fresh();
    for (final o in [const Offset(0.5, 0.03), const Offset(0.95, 0.4), const Offset(0.3, 0.97), const Offset(0.05, 0.6)]) {
      expect(same(l.point(l.paramOf(o)), o), isTrue);
    }
    // un point interieur va sur le bord le plus proche
    expect(same(l.point(l.paramOf(const Offset(0.08, 0.5))), const Offset(0.05, 0.5)), isTrue);
  });

  test('translation parallele : la pente ne change pas', () {
    final l = fresh();
    expect(l.shift(kTop, const Offset(0, 0.05)), isTrue);
    final (a, b) = l.handles(kTop);
    expect(a.dy, closeTo(0.35, 1e-9));
    expect(b.dy, closeTo(0.35, 1e-9));
  });

  test('pente : un seul bout bouge', () {
    final l = fresh();
    final (a0, _) = l.handles(kLeft);
    expect(l.moveEnd(kLeft, 1, const Offset(0.15, 0.97)), isTrue);
    final (a, b) = l.handles(kLeft);
    expect(same(a, a0), isTrue);
    expect(b.dx, closeTo(0.15, 1e-9));
    expect(l.corners(), isNotNull);
  });

  test('W14c (essai de Marc 20.11) : droite penchee translatee, un rond change de bord', () {
    final l = fresh();
    // droite de gauche tres penchee : haut a x=0.07, bas a x=0.4
    expect(l.moveEnd(kLeft, 0, const Offset(0.07, 0.03)), isTrue);
    expect(l.moveEnd(kLeft, 1, const Offset(0.4, 0.97)), isTrue);
    // vers la gauche : le rond du haut sortait du bord haut -> autrefois refuse
    expect(l.shift(kLeft, const Offset(-0.1, 0)), isTrue);
    final (a, b) = l.handles(kLeft);
    expect(a.dx, closeTo(0.05, 1e-9)); // passe sur le bord GAUCHE
    expect(a.dy, greaterThan(0.03));
    expect(b.dy, closeTo(0.97, 1e-9)); // l'autre reste en bas
    expect(b.dx, closeTo(0.3, 1e-6));
    expect(l.corners(), isNotNull);
  });

  test('rond tire au-dela d’un coin : il passe sur le bord voisin', () {
    final l = fresh();
    expect(l.moveEnd(kTop, 0, const Offset(0.08, 0.0)), isTrue); // du bord gauche vers le bord haut
    final (a, _) = l.handles(kTop);
    expect(a.dy, closeTo(0.03, 1e-9));
    expect(a.dx, closeTo(0.08, 1e-9));
    expect(l.corners(), isNotNull);
  });

  test('garde-fou : geste incoherent refuse, derniere position gardee', () {
    final l = fresh();
    final before = List.of(l.v);
    expect(l.shift(kTop, const Offset(0, 0.5)), isFalse); // le haut passerait sous le bas
    expect(l.v, before);
    expect(l.moveEnd(kTop, 0, const Offset(0.05, 0.97)), isFalse); // haut-gauche sous le bas
    expect(l.v, before);
    expect(l.shift(kLeft, const Offset(0.85, 0)), isFalse); // gauche a droite de la droite
    expect(l.v, before);
  });

  test('droite qui sortirait du cadre ou se coucherait sur un bord : refusee', () {
    final l = fresh();
    final before = List.of(l.v);
    expect(l.shift(kLeft, const Offset(-0.5, 0)), isFalse); // hors du cadre
    expect(l.v, before);
    // gauche : rond du haut en (0.1, haut) ; rond du bas tire sur le bord haut -> couchee
    expect(l.moveEnd(kLeft, 1, const Offset(0.3, 0.0)), isFalse);
    expect(l.v, before);
  });

  test('toucher dans la carte / hors de la carte', () {
    final q = fresh().corners()!;
    expect(insideQuad(const Offset(0.5, 0.5), q), isTrue);
    expect(insideQuad(const Offset(0.5, 0.9), q), isFalse);
  });

  test('intersection de droites paralleles : null', () {
    expect(CardLines.cross(const Offset(0, 0), const Offset(1, 0), const Offset(0, 1), const Offset(1, 1)), isNull);
  });

  test('distance a une droite', () {
    expect(distToLine(const Offset(0, 5), const Offset(-1, 0), const Offset(1, 0)), closeTo(5, 1e-9));
  });
}
