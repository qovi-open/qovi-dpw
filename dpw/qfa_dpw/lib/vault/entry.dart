// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER entry.dart · 2026-11-20 · lot 27 (lecture WL retiree ; lot 25 : W17 apps Android)
// Une entree du trousseau. Champs repris du WL (Nam/Whe/Who/Pass/Cmt/Mod/Use)
// + un identifiant stable [id] qui permet de fusionner les modifications
// faites sur deux postes (fichier partage par Dropbox).
//
// W14 (lot 20, decisions de Marc 19.11) : photo de carte, recto et verso.
//  - La fiche ne porte que des REFERENCES ([crd] : 0, 1 ou 2 identifiants de
//    32 hexa, recto puis verso). Elles voyagent avec la synchro.
//  - Les photos elles-memes sont des fichiers chiffres a cote du trousseau
//    (vault/card_store.dart) et ne passent JAMAIS par la synchro (etape 1).
//    L'etape 2 transportera les fichiers manquants par identifiant, sans
//    changer ce format.
//  - W17 (lot 25) : [apk] = noms de paquets Android associes a la fiche par
//    « Retenir pour cette app » (remplissage automatique). Voyagent avec la
//    synchro ; absents = format inchange.
//  - Champs INCONNUS (ecrits par une version plus recente) : gardes tels quels
//    et renvoyes a l'identique, pour qu'une version plus ancienne n'efface
//    plus rien chez les autres.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/rand.dart';

/// Identifiant d'une photo de carte : 32 hexa minuscules. Toute autre valeur
/// recue (synchro, fichier) est ignoree : elle sert a construire un chemin.
final RegExp kCardId = RegExp(r'^[0-9a-f]{32}$');

/// Nombre de faces d'une carte (recto, verso).
const int kCardFaces = 2;

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
    this.cre,
    List<String>? crd,
    List<String>? apk,
    Map<String, dynamic>? extra,
  })  : id = id ?? randHex(16),
        apk = cleanApks(apk ?? const []),
        mod = mod ?? DateTime.now().toUtc(),
        use = use ?? DateTime.now().toUtc(),
        crd = cleanCards(crd ?? const []),
        extra = extra ?? <String, dynamic>{};

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

  /// W7 (lot 17) : date de CREATION, en UTC (affichee en heure locale).
  /// null = inconnue (entree d'avant le lot 17, ou recue d'un appareil plus
  /// ancien) : le trousseau la fixe une fois a « aujourd'hui moins 5 jours ».
  DateTime? cre;

  /// W14 (lot 20) : references des photos de la carte, recto puis verso.
  List<String> crd;

  /// W17 (lot 25) : paquets Android associes (ex. com.ubs.mobile).
  List<String> apk;

  /// Champs inconnus de cette version, renvoyes tels quels (lot 20).
  Map<String, dynamic> extra;

  static const Set<String> _known = {
    'id', 'nam', 'url', 'who', 'pass', 'note', 'mod', 'use', 'syn', 'cre', 'crd', 'apk', //
  };

  /// Garde seulement des identifiants valides, sans doublon, 2 au plus.
  static List<String> cleanCards(Iterable<Object?> l) {
    final out = <String>[];
    for (final v in l) {
      final s = v?.toString() ?? '';
      if (kCardId.hasMatch(s) && !out.contains(s)) out.add(s);
      if (out.length == kCardFaces) break;
    }
    return out;
  }

  /// Nom de paquet Android valable : lettres, chiffres, _ et points, 2 segments au moins.
  static final RegExp kApk = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');

  /// Garde des noms de paquets valables, sans doublon, 8 au plus.
  static List<String> cleanApks(Iterable<Object?> l) {
    final out = <String>[];
    for (final v in l) {
      final s = v?.toString() ?? '';
      if (s.length <= 200 && kApk.hasMatch(s) && !out.contains(s)) out.add(s);
      if (out.length == 8) break;
    }
    return out;
  }

  /// Empreinte du contenu (hors dates) : nom, adresse, identifiant, mot de
  /// passe, note, et (lot 20) les references de la carte s'il y en a. Sans
  /// carte, l'empreinte est EXACTEMENT celle des versions precedentes.
  String get hash => sha256
      .convert(utf8.encode(jsonEncode([
        nam, url, who, pass, note, if (crd.isNotEmpty) crd.join(','), //
        if (apk.isNotEmpty) 'apk:${apk.join(',')}',
      ])))
      .toString();

  Entry copy() => Entry(
      id: id, nam: nam, url: url, who: who, pass: pass, note: note, mod: mod, use: use, syn: syn, cre: cre,
      crd: List.of(crd), apk: List.of(apk), extra: Map.of(extra));

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'nam': nam,
        'url': url,
        'who': who,
        'pass': pass,
        'note': note,
        'mod': mod.toUtc().toIso8601String(),
        'use': use.toUtc().toIso8601String(),
        if (syn.isNotEmpty) 'syn': syn,
        if (cre != null) 'cre': cre!.toUtc().toIso8601String(),
        if (crd.isNotEmpty) 'crd': List.of(crd),
        if (apk.isNotEmpty) 'apk': List.of(apk),
      };

  static Entry fromJson(Map m) {
    final c = m['crd'], k = m['apk'];
    return Entry(
      id: _s(m['id']).isEmpty ? null : _s(m['id']),
      nam: _s(m['nam']),
      url: _s(m['url']),
      who: _s(m['who']),
      pass: _s(m['pass']),
      note: _s(m['note']),
      mod: DateTime.tryParse(_s(m['mod']))?.toUtc(),
      use: DateTime.tryParse(_s(m['use']))?.toUtc(),
      syn: _s(m['syn']),
      cre: DateTime.tryParse(_s(m['cre']))?.toUtc(),
      crd: c is List ? cleanCards(c) : const [],
      apk: k is List ? cleanApks(k) : const [],
      extra: {
        for (final e in m.entries)
          if (e.key is String && !_known.contains(e.key)) e.key as String: e.value,
      },
    );
  }

  /// Nouveau mot de passe, meme regle que le WL : 128 bits en hexa + "@Ab0"
  /// (le suffixe satisfait les sites qui exigent majuscule, chiffre, signe).
  static String newPassword() => '${randHex(16)}@Ab0';

  static String _s(Object? v) => v == null ? '' : v.toString();
}
