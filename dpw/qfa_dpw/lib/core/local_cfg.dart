// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER local_cfg.dart · 2026-11-10 · lot 17 (filtre courant par identifiant ; dates)
// Reglages LOCAUX du poste, sans aucun secret (fichier dpw_cfg.json dans le
// dossier de l'application) : environnement, adresse email si l'usager veut
// qu'on la retienne, dossier du trousseau, UID du poste.
// La cle du trousseau n'est JAMAIS ecrite ici ni ailleurs sur disque.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../env.dart';
import 'rand.dart';

class LocalCfg {
  DpwEnv env = DpwEnv.prd;
  String email = '';
  bool keepEmail = false;
  String vaultDir = '';
  String mobU = '';
  /// Langue choisie dans les reglages (fr, de, it, en) ; vide = celle de l'appareil.
  String lang = '';
  /// ANCIEN dernier filtre, en clair (lot 2l) : lu seulement pour etre repris
  /// une fois dans le trousseau (lot 17), puis efface. Plus jamais ecrit.
  String filter = '';
  /// Lot 17 : identifiant du filtre courant (son texte est dans le trousseau).
  String fltId = '';
  /// W7 : afficher les dates de creation et de modification sur les fiches.
  bool showDates = false;
  /// Verrouillage apres N minutes sans activite (lot 2m, 60 par defaut).
  int idleMin = 60;

  static Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File('${d.path}${Platform.pathSeparator}dpw_cfg.json');
  }

  static Future<LocalCfg> load() async {
    final c = LocalCfg();
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) {
          c.env = m['env'] == 'tst' ? DpwEnv.tst : DpwEnv.prd;
          c.email = (m['email'] ?? '').toString();
          c.keepEmail = m['keepEmail'] == true;
          c.vaultDir = (m['vaultDir'] ?? '').toString();
          c.mobU = (m['mobU'] ?? '').toString();
          c.lang = (m['lang'] ?? '').toString();
          c.filter = (m['filter'] ?? '').toString();
          c.fltId = (m['fltId'] ?? '').toString();
          c.showDates = m['showDates'] == true;
          final im = m['idleMin'];
          if (im is int && im >= 1 && im <= 1440) c.idleMin = im;
        }
      }
    } catch (_) {
      // reglages illisibles : on repart des valeurs par defaut
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(c.mobU)) {
      c.mobU = randHex(32);
      await c.save();
    }
    return c;
  }

  Future<void> save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode({
      'env': env == DpwEnv.prd ? 'prd' : 'tst',
      'email': keepEmail ? email : '',
      'keepEmail': keepEmail,
      'vaultDir': vaultDir,
      'mobU': mobU,
      'lang': lang,
      if (filter.isNotEmpty) 'filter': filter,
      'fltId': fltId,
      'showDates': showDates,
      'idleMin': idleMin,
    }));
  }
}
