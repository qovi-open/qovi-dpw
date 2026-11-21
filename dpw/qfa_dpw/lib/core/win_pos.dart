// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER win_pos.dart · 2026-11-10 · lot 16 (W4 : place de la fenetre retenue)
// W4 (Marc 06.11) : sur ordinateur (Windows, Linux, macOS), DpW rouvre sa
// fenetre a la place et a la taille qu'elle avait a la fermeture.
// Fichier a part (dpw_win.json, dossier de l'app) pour ne jamais ecraser les
// reglages de dpw_cfg.json ; aucune donnee sensible, seulement x, y, l, h.
// Garde-fou : si cette place n'est plus visible (ecran debranche, autre
// resolution), on revient a la fenetre centree par defaut.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';

class WinPos {
  static Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File('${d.path}${Platform.pathSeparator}dpw_win.json');
  }

  /// Derniere place connue, ou null (premiere ouverture, fichier illisible).
  static Future<Rect?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map) return null;
      double n(String k) => (m[k] as num).toDouble();
      final r = Rect.fromLTWH(n('x'), n('y'), n('w'), n('h'));
      if (!r.isFinite || r.width < 200 || r.height < 200) return null;
      return r;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(Rect r) async {
    try {
      if (!r.isFinite || r.width < 200 || r.height < 200) return;
      final f = await _file();
      await f.writeAsString(jsonEncode({'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height}));
    } catch (_) {
      // sans gravite : on rouvrira simplement au centre
    }
  }

  /// Vrai si au moins un bon morceau de [r] tombe sur un ecran actuel.
  static Future<bool> visible(Rect r) async {
    try {
      for (final d in await screenRetriever.getAllDisplays()) {
        final area = (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
        final i = area.intersect(r);
        if (i.width >= 120 && i.height >= 80) return true;
      }
    } catch (_) {
      // ecrans inconnus : prudence, fenetre par defaut
    }
    return false;
  }
}
