// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER filter_test.dart · 2026-11-01 · lot 2l
// Filtre de la liste : minuscules sans accents.
import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/ui/app_state.dart';

void main() {
  test('sans accents ni majuscules', () {
    expect(foldText('Clé Ça Œuvre Bâle'), 'cle ca ouvre bale');
  });
}
