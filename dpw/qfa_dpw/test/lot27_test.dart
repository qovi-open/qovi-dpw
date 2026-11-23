// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER lot27_test.dart · 2026-11-20 · lot 27 (ancien format WL retire, chemin Chrome)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/txt.dart';
import 'package:qfa_dpw/vault/vault.dart';

const String _sok = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dpw_l27_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('un ancien _DpW.aes est ignore : ni lu, ni efface', () async {
    final wl = File('${tmp.path}${Platform.pathSeparator}_DpW.aes');
    await wl.writeAsString('ancien');
    final v = Vault(tmp.path, _sok);
    await v.open();
    expect(v.entries, isEmpty);
    expect(await v.file.exists(), isTrue);
    expect(await wl.readAsString(), 'ancien');
  });

  test('le chemin Chrome est donne dans les 4 langues', () {
    final was = lang;
    for (final l in Lang.values) {
      lang = l;
      expect(T.fillChrome, contains('Chrome'));
    }
    lang = was;
  });
}
