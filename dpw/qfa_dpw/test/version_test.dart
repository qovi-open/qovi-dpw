// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// W12 : la version affichee (lib/version.dart) = celle de pubspec.yaml.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/version.dart';

void main() {
  test('kDpwVer = version de pubspec.yaml', () {
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull);
    expect(kDpwVer, m!.group(1));
  });
  test('libelle lisible', () {
    expect(dpwVerLabel, '${kDpwVer.split('+')[0]} (${kDpwVer.split('+')[1]})');
  });
}
