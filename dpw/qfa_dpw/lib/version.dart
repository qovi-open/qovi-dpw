// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER version.dart · 2026-11-20 · lot 32 (note au-dessus du clavier : correctif)
// Version de l'app, affichee en bas des reglages. DOIT etre identique a la
// ligne `version:` de pubspec.yaml : test/version_test.dart le verifie.
const String kDpwVer = '3.7.7+346';

/// « 3.4.5 (333) » pour l'affichage.
String get dpwVerLabel {
  final p = kDpwVer.split('+');
  return p.length == 2 ? '${p[0]} (${p[1]})' : kDpwVer;
}
