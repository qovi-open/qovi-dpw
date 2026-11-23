// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER fill_match.dart · 2026-11-20 · lot 25 (W17 : fiches qui correspondent a une app ou a un site)
// Remplissage automatique Android (W17, decisions de Marc 20.11) : Android
// donne le DOMAINE du site (navigateur) ou le PAQUET de l'app ; DpW range en
// tete les fiches qui correspondent. Fonctions pures, testees.
//  - site : hote de l'url de la fiche = domaine, ou l'un est sous-domaine de
//    l'autre (score 3) ; meme domaine sur les 2 derniers niveaux (score 2) ;
//  - app : paquet retenu dans la fiche (« Retenir pour cette app », score 4) ;
//    sinon un morceau significatif du paquet (ubs dans com.ubs.mobile) dans
//    l'hote ou le nom de la fiche (score 1).
import '../vault/entry.dart';

/// Hote d'une url (minuscules, sans « www. ») ; '' si illisible.
String hostOf(String url) {
  var u = url.trim().toLowerCase();
  if (u.isEmpty) return '';
  if (!u.contains('://')) u = 'https://$u';
  final h = Uri.tryParse(u)?.host ?? '';
  return h.startsWith('www.') ? h.substring(4) : h;
}

String _base(String host) {
  final p = host.split('.');
  return p.length <= 2 ? host : p.sublist(p.length - 2).join('.');
}

const Set<String> _noise = {
  'com', 'ch', 'org', 'net', 'android', 'app', 'apps', 'mobile', 'mobil', 'de', 'fr', 'it', 'en', 'www', //
  'client', 'prod', 'release', 'google', 'banking', 'bank', 'online', 'official', 'free', 'pro', 'lite',
};

/// Morceaux significatifs d'un nom de paquet.
List<String> apkTokens(String pkg) =>
    [for (final t in pkg.toLowerCase().split(RegExp(r'[._]'))) if (t.length >= 3 && !_noise.contains(t)) t];

/// Score d'une fiche pour [web] (domaine) et/ou [pkg] (paquet) ; 0 = aucun lien.
int fillScore(Entry e, {String web = '', String pkg = ''}) {
  var best = 0;
  final w = hostOf(web), h = hostOf(e.url);
  if (w.isNotEmpty && h.isNotEmpty) {
    if (h == w || w.endsWith('.$h') || h.endsWith('.$w')) {
      best = 3;
    } else if (_base(h) == _base(w)) {
      best = 2;
    }
  }
  if (pkg.isNotEmpty) {
    if (e.apk.contains(pkg)) return 4;
    if (best == 0) {
      final hay = '${h.replaceAll('.', ' ')} ${e.nam.toLowerCase()}';
      for (final t in apkTokens(pkg)) {
        if (hay.contains(t)) {
          best = 1;
          break;
        }
      }
    }
  }
  return best;
}

/// Les fiches qui correspondent, meilleures d'abord (puis la plus utilisee).
List<Entry> fillMatches(Iterable<Entry> all, {String web = '', String pkg = ''}) {
  final s = <Entry, int>{};
  for (final e in all) {
    final v = fillScore(e, web: web, pkg: pkg);
    if (v > 0) s[e] = v;
  }
  return s.keys.toList()
    ..sort((a, b) {
      final d = s[b]! - s[a]!;
      return d != 0 ? d : b.use.compareTo(a.use);
    });
}
