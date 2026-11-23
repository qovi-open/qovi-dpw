// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER merge.dart · 2026-11-20 · lot 25 (copie de conflit : apps associees W17)
// Fusion de deux trousseaux (regle B de Marc, 01.11.2026) :
//  - une entree changee d'un seul cote depuis la derniere synchro : on prend
//    le changement ;
//  - changee des DEUX cotes : on garde les deux, la plus recente sous son
//    identifiant, l'autre en copie « (copie du AAAA-MM-JJ HH:MM) » ;
//  - une suppression (trace dans `del`) s'applique de l'autre cote, sauf si
//    l'entree y a ete modifiee APRES la suppression ;
//  - deux entrees au contenu identique (ex. le meme ancien trousseau importe
//    sur deux postes) n'en font plus qu'une ;
//  - les traces de suppression sont gardees 1 an ;
//  - lot 17 : la date de CREATION d'une entree est la plus ANCIENNE connue
//    (une date absente ne remplace jamais une date connue) ;
//  - lot 17 : FILTRES enregistres (W2), dans le trousseau donc chiffres : par
//    filtre, la modification la plus recente gagne ; un filtre detruit l'est
//    partout (trace `fdel`, meme regle que les entrees). Un appareil plus
//    ancien ignore filtres et dates sans rien effacer chez les autres ;
//  - lot 20 (W14) : les references de photos de carte (Entry.crd) font partie
//    de l'empreinte, donc suivent les memes regles ; la copie de conflit garde
//    les photos et les champs inconnus de la version perdante. La fusion ne
//    supprime JAMAIS de fichier photo (seules les actions locales le font).
// La fusion est SYMETRIQUE : merge(a, b) et merge(b, a) donnent le meme
// trousseau, si bien que les deux appareils finissent identiques.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../txt.dart';
import '../vault/entry.dart';

const Duration kTombKeep = Duration(days: 365);

/// Trace d'une entree supprimee.
class Tomb {
  Tomb(this.id, this.t);
  final String id;
  final DateTime t;

  Map<String, dynamic> toJson() => {'id': id, 't': t.toUtc().toIso8601String()};

  static Tomb? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = m['id']?.toString() ?? '';
    final t = DateTime.tryParse(m['t']?.toString() ?? '')?.toUtc();
    return (id.isEmpty || t == null) ? null : Tomb(id, t);
  }
}

/// Contenu complet d'un trousseau : entrees + traces de suppression.
class VaultData {
  VaultData(this.cod, [List<Tomb>? del, List<Flt>? flt, List<Tomb>? fdel])
      : del = del ?? [],
        flt = flt ?? [],
        fdel = fdel ?? [];
  final List<Entry> cod;
  final List<Tomb> del;

  /// Filtres enregistres (lot 17, W2) et leurs traces de suppression.
  final List<Flt> flt;
  final List<Tomb> fdel;

  /// Contenu JSON v3 (commun au fichier et a la synchro).
  Map<String, dynamic> toJson() => {
        'v': 3,
        'cod': [for (final e in cod) e.toJson()],
        'del': [for (final t in del) t.toJson()],
        if (flt.isNotEmpty) 'flt': [for (final f in flt) f.toJson()],
        if (fdel.isNotEmpty) 'fdel': [for (final t in fdel) t.toJson()],
      };

  /// null si [m] n'est pas un trousseau (pas de liste `cod`).
  static VaultData? fromJson(Object? m) {
    if (m is! Map) return null;
    final cod = m['cod'];
    if (cod is! List) return null;
    List<Tomb> tombs(Object? l) => l is List ? l.map(Tomb.fromJson).whereType<Tomb>().toList() : [];
    final flt = m['flt'];
    return VaultData([for (final e in cod) if (e is Map) Entry.fromJson(e)], tombs(m['del']),
        flt is List ? flt.map(Flt.fromJson).whereType<Flt>().toList() : [], tombs(m['fdel']));
  }
}

/// Filtre enregistre (lot 17, W2) : texte, date de modification, dernier usage.
class Flt {
  Flt(this.id, this.txt, this.mod, this.use);
  final String id;
  String txt;
  DateTime mod;
  DateTime use;

  Flt copy() => Flt(id, txt, mod, use);

  Map<String, dynamic> toJson() => {
        'id': id,
        'txt': txt,
        'mod': mod.toUtc().toIso8601String(),
        'use': use.toUtc().toIso8601String(),
      };

  static Flt? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = m['id']?.toString() ?? '';
    final mod = DateTime.tryParse(m['mod']?.toString() ?? '')?.toUtc();
    if (id.isEmpty || mod == null) return null;
    final use = DateTime.tryParse(m['use']?.toString() ?? '')?.toUtc() ?? mod;
    return Flt(id, m['txt']?.toString() ?? '', mod, use);
  }
}

/// Bilan, vu de l'appareil local.
class MergeStats {
  int added = 0, changed = 0, removed = 0, copies = 0;
  bool get nothing => added + changed + removed + copies == 0;
  @override
  String toString() {
    if (nothing) return T.upToDate;
    final p = <String>[];
    if (added > 0) p.add(T.added(added));
    if (changed > 0) p.add(T.changed(changed));
    if (removed > 0) p.add(T.removed(removed));
    if (copies > 0) p.add(T.copies(copies));
    return T.synced(p.join(', '));
  }
}

class MergeResult {
  MergeResult(this.data, this.stats);
  final VaultData data;
  final MergeStats stats;
}

DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// Date de creation la plus ancienne connue (null si aucune).
DateTime? _minCre(DateTime? a, DateTime? b) =>
    a == null ? b : (b == null ? a : (a.isBefore(b) ? a : b));

String _stamp(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}';
}

/// Le plus recent gagne ; a egalite, l'empreinte la plus grande (deterministe).
bool _aWins(Entry a, Entry b) {
  if (a.mod.isAfter(b.mod)) return true;
  if (b.mod.isAfter(a.mod)) return false;
  return a.hash.compareTo(b.hash) >= 0;
}

/// Copie d'une version perdante, avec un identifiant DETERMINISTE (le meme
/// sur les deux appareils, pour qu'ils convergent).
Entry _copyOf(Entry loser) => Entry(
    id: sha256.convert(utf8.encode('${loser.id}|${loser.hash}')).toString().substring(0, 32),
    nam: '${loser.nam} (copie du ${_stamp(loser.mod)})',
    url: loser.url, who: loser.who, pass: loser.pass, note: loser.note,
    mod: loser.mod, use: loser.use, cre: loser.cre,
    crd: List.of(loser.crd), apk: List.of(loser.apk), extra: Map.of(loser.extra));

/// Fusionne [local] et [remote]. [now] : pour l'expiration des traces.
MergeResult mergeVaults(VaultData local, VaultData remote, {DateTime? now}) {
  final t0 = (now ?? DateTime.now()).toUtc();

  // 1. Traces de suppression : union (la plus recente), expirees retirees.
  final tombs = <String, DateTime>{};
  for (final t in [...local.del, ...remote.del]) {
    final cur = tombs[t.id];
    tombs[t.id] = cur == null ? t.t : _max(cur, t.t);
  }
  tombs.removeWhere((_, t) => t0.difference(t) > kTombKeep);

  final la = {for (final e in local.cod) e.id: e};
  final rb = {for (final e in remote.cod) e.id: e};
  final ids = {...la.keys, ...rb.keys}.toList()..sort();
  final out = <Entry>[];
  var copies = 0;

  for (final id in ids) {
    final a = la[id], b = rb[id];
    if (a == null || b == null) {
      final e = (a ?? b)!;
      final dead = tombs[id];
      if (dead != null && !e.mod.isAfter(dead)) continue; // supprimee ailleurs
      out.add(e.copy());
      continue;
    }
    final ha = a.hash, hb = b.hash;
    if (ha == hb) {
      final w = (_aWins(a, b) ? a : b).copy()
        ..mod = _max(a.mod, b.mod)
        ..use = _max(a.use, b.use);
      out.add(w);
      continue;
    }
    final aChanged = ha != a.syn, bChanged = hb != b.syn;
    if (aChanged && !bChanged) {
      out.add(a.copy()..use = _max(a.use, b.use));
    } else if (bChanged && !aChanged) {
      out.add(b.copy()..use = _max(a.use, b.use));
    } else {
      // Change des deux cotes : on garde les deux.
      final aw = _aWins(a, b);
      final win = (aw ? a : b).copy()..use = _max(a.use, b.use);
      out.add(win);
      out.add(_copyOf(aw ? b : a));
      copies++;
    }
    tombs.remove(id); // l'entree existe : sa trace eventuelle ne s'applique plus
  }

  // 2. Contenus identiques sous deux identifiants : on garde le plus petit id.
  final byHash = <String, Entry>{};
  for (final e in out) {
    final h = e.hash;
    final cur = byHash[h];
    if (cur == null) {
      byHash[h] = e;
    } else {
      final keep = cur.id.compareTo(e.id) <= 0 ? cur : e;
      final drop = identical(keep, cur) ? e : cur;
      keep.mod = _max(keep.mod, drop.mod);
      keep.use = _max(keep.use, drop.use);
      keep.cre = _minCre(keep.cre, drop.cre);
      byHash[h] = keep;
    }
  }
  final merged = byHash.values.toList()..sort((x, y) => x.id.compareTo(y.id));
  for (final e in merged) {
    e.syn = e.hash; // synchronisee a cet etat
    e.cre = _minCre(e.cre, _minCre(la[e.id]?.cre, rb[e.id]?.cre));
  }

  // 3. Bilan vu du local.
  final st = MergeStats()..copies = copies;
  final mIds = {for (final e in merged) e.id: e};
  for (final e in merged) {
    final old = la[e.id];
    if (old == null) {
      st.added++;
    } else if (old.hash != e.hash) {
      st.changed++;
    }
  }
  for (final id in la.keys) {
    if (!mIds.containsKey(id)) st.removed++;
  }
  // Les copies creees sont comptees comme doublons, pas comme ajouts.
  st.added = (st.added - copies).clamp(0, 1 << 30);

  final del = [for (final e in tombs.entries) Tomb(e.key, e.value)]
    ..sort((x, y) => x.id.compareTo(y.id));
  final (flt, fdel) = _mergeFilters(local, remote, t0);
  return MergeResult(VaultData(merged, del, flt, fdel), st);
}

/// Filtres (lot 17) : union ; meme id -> la modification la plus recente
/// (a egalite, le texte le plus grand : deterministe) ; dernier usage = max ;
/// un filtre est retire si sa trace est posterieure ou egale a sa modification.
(List<Flt>, List<Tomb>) _mergeFilters(VaultData a, VaultData b, DateTime t0) {
  final tombs = <String, DateTime>{};
  for (final t in [...a.fdel, ...b.fdel]) {
    final cur = tombs[t.id];
    tombs[t.id] = cur == null ? t.t : _max(cur, t.t);
  }
  tombs.removeWhere((_, t) => t0.difference(t) > kTombKeep);
  final all = <String, Flt>{};
  for (final f in [...a.flt, ...b.flt]) {
    final cur = all[f.id];
    if (cur == null) {
      all[f.id] = f.copy();
      continue;
    }
    final fWins = f.mod.isAfter(cur.mod) || (f.mod == cur.mod && f.txt.compareTo(cur.txt) > 0);
    all[f.id] = (fWins ? f : cur).copy()..use = _max(f.use, cur.use);
  }
  final out = <Flt>[];
  for (final f in all.values) {
    final dead = tombs[f.id];
    if (dead != null && !f.mod.isAfter(dead)) continue;
    if (dead != null) tombs.remove(f.id); // recree apres la destruction
    out.add(f);
  }
  out.sort((x, y) => x.id.compareTo(y.id));
  final fdel = [for (final e in tombs.entries) Tomb(e.key, e.value)]..sort((x, y) => x.id.compareTo(y.id));
  return (out, fdel);
}
