// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER merge.dart · 2026-11-01 · lot 2h (textes traduits fr/de/it/en)
// Fusion de deux trousseaux (regle B de Marc, 01.11.2026) :
//  - une entree changee d'un seul cote depuis la derniere synchro : on prend
//    le changement ;
//  - changee des DEUX cotes : on garde les deux, la plus recente sous son
//    identifiant, l'autre en copie « (copie du AAAA-MM-JJ HH:MM) » ;
//  - une suppression (trace dans `del`) s'applique de l'autre cote, sauf si
//    l'entree y a ete modifiee APRES la suppression ;
//  - deux entrees au contenu identique (ex. le meme ancien trousseau importe
//    sur deux postes) n'en font plus qu'une ;
//  - les traces de suppression sont gardees 1 an.
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
  VaultData(this.cod, [List<Tomb>? del]) : del = del ?? [];
  final List<Entry> cod;
  final List<Tomb> del;
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
    mod: loser.mod, use: loser.use);

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
      byHash[h] = keep;
    }
  }
  final merged = byHash.values.toList()..sort((x, y) => x.id.compareTo(y.id));
  for (final e in merged) {
    e.syn = e.hash; // synchronisee a cet etat
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
  return MergeResult(VaultData(merged, del), st);
}
