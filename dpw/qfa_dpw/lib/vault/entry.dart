// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER entry.dart · 2026-11-01 · lot 2 (syn : empreinte a la derniere synchro)
// Une entree du trousseau. Champs repris du WL (Nam/Whe/Who/Pass/Cmt/Mod/Use)
// + un identifiant stable [id] qui permet de fusionner les modifications
// faites sur deux postes (fichier partage par Dropbox).
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/rand.dart';

class Entry {
  Entry({
    String? id,
    this.nam = '',
    this.url = '',
    this.who = '',
    this.pass = '',
    this.note = '',
    DateTime? mod,
    DateTime? use,
    this.syn = '',
  })  : id = id ?? randHex(16),
        mod = mod ?? DateTime.now().toUtc(),
        use = use ?? DateTime.now().toUtc();

  final String id;
  String nam;
  String url;
  String who;
  String pass;
  String note;
  DateTime mod;
  DateTime use;

  /// Empreinte du contenu lors de la derniere synchro ('' = jamais synchronisee).
  /// Sert a savoir, a la fusion, quel cote a change depuis.
  String syn;

  /// Empreinte du contenu (hors dates) : nom, adresse, identifiant, mot de passe, note.
  String get hash => sha256
      .convert(utf8.encode(jsonEncode([nam, url, who, pass, note])))
      .toString();

  Entry copy() => Entry(
      id: id, nam: nam, url: url, who: who, pass: pass, note: note, mod: mod, use: use, syn: syn);

  Map<String, dynamic> toJson() => {
        'id': id,
        'nam': nam,
        'url': url,
        'who': who,
        'pass': pass,
        'note': note,
        'mod': mod.toUtc().toIso8601String(),
        'use': use.toUtc().toIso8601String(),
        if (syn.isNotEmpty) 'syn': syn,
      };

  static Entry fromJson(Map m) => Entry(
        id: _s(m['id']).isEmpty ? null : _s(m['id']),
        nam: _s(m['nam']),
        url: _s(m['url']),
        who: _s(m['who']),
        pass: _s(m['pass']),
        note: _s(m['note']),
        mod: DateTime.tryParse(_s(m['mod']))?.toUtc(),
        use: DateTime.tryParse(_s(m['use']))?.toUtc(),
        syn: _s(m['syn']),
      );

  /// Entree d'un trousseau WL : {"Nam":{"s":..},"Whe":{"s"},"Who":{"s"},
  /// "Pass":{"s"},"Cmt":{"s"},"Mod":{"t"},"Use":{"t"}}.
  static Entry fromWl(Map m) => Entry(
        nam: _wl(m, 'Nam', 's'),
        url: _wl(m, 'Whe', 's'),
        who: _wl(m, 'Who', 's'),
        pass: _wl(m, 'Pass', 's'),
        note: _wl(m, 'Cmt', 's'),
        mod: wlTime(_wl(m, 'Mod', 't')),
        use: wlTime(_wl(m, 'Use', 't')),
      );

  /// Nouveau mot de passe, meme regle que le WL : 128 bits en hexa + "@Ab0"
  /// (le suffixe satisfait les sites qui exigent majuscule, chiffre, signe).
  static String newPassword() => '${randHex(16)}@Ab0';

  static String _s(Object? v) => v == null ? '' : v.toString();

  static String _wl(Map m, String k, String f) {
    final v = m[k];
    return v is Map ? _s(v[f]) : _s(v);
  }

  /// Date WL : chiffres AAAAMMJJHHMMSS[...] (separateurs quelconques), en UTC.
  static DateTime wlTime(String s) {
    final d = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length < 14) return DateTime.utc(2000);
    return DateTime.utc(
        int.parse(d.substring(0, 4)),
        int.parse(d.substring(4, 6)),
        int.parse(d.substring(6, 8)),
        int.parse(d.substring(8, 10)),
        int.parse(d.substring(10, 12)),
        int.parse(d.substring(12, 14)));
  }
}
