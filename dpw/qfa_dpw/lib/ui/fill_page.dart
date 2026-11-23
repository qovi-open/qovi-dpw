// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER fill_page.dart · 2026-11-20 · lot 26 (W17 : derniere fiche choisie en tete, 2 min)
// Remplissage automatique Android (W17, decisions de Marc 20.11) : Android a
// ouvert DpW depuis le champ d'une autre app (« Remplir avec DpW »). Apres la
// validation Qovi habituelle si le trousseau etait verrouille, cette page
// montre d'abord les fiches qui correspondent a l'app ou au site, puis les
// autres (filtre). Un toucher sur une fiche : l'utilisateur et le mot de
// passe partent vers l'app (un champ vide = ""), DpW se retire. Rien ne
// part sans ce toucher. « Retenir pour cette app » associe la fiche au
// paquet (champ apk, synchronise) pour la trouver directement la fois suivante.
import 'package:flutter/material.dart';

import '../core/fill_match.dart';
import '../txt.dart';
import '../vault/entry.dart';
import 'app_state.dart';
import 'style.dart';

class FillPage extends StatefulWidget {
  const FillPage({super.key, required this.app});
  final AppState app;
  @override
  State<FillPage> createState() => _FillPageState();
}

class _FillPageState extends State<FillPage> {
  final _q = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _pick(Entry e) async {
    final app = widget.app, f = app.fill;
    if (f == null || _busy) return;
    var remember = false;
    if (f.pkg.isNotEmpty && f.web.isEmpty && !e.apk.contains(f.pkg)) {
      final r = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(T.fillRemember),
          content: Text(T.fillRememberAsk(e.nam, f.pkg)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(T.no)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(T.yes)),
          ],
        ),
      );
      if (r == null || !mounted) return; // fermee sans choix : on reste ici
      remember = r;
    }
    setState(() => _busy = true);
    await app.fillWith(e, remember: remember);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, f = app.fill;
    if (f == null) return const SizedBox.shrink();
    final all = [...?app.vault?.entries];
    final q = _q.text;
    final hits = q.trim().isEmpty ? fillMatches(all, web: f.web, pkg: f.pkg) : <Entry>[];
    // Lot 26 : la fiche choisie juste avant (site en deux pages) passe en tete.
    final rid = q.trim().isEmpty ? app.recentFill(f) : null;
    if (rid != null) {
      final r = all.where((e) => e.id == rid).firstOrNull;
      if (r != null) {
        hits.remove(r);
        hits.insert(0, r);
      }
    }
    final rest = [
      for (final e in all)
        if (!hits.contains(e) && matchFilter(q, '${e.nam}\n${e.url}\n${e.note}')) e
    ]..sort((a, b) => a.nam.toLowerCase().compareTo(b.nam.toLowerCase()));
    Widget tile(Entry e, bool hit) => ListTile(
          leading: Icon(hit ? Icons.star : Icons.key_outlined, color: hit ? Dpw.red : Dpw.sub),
          title: Text(e.nam.isEmpty ? '—' : e.nam, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: e.who.isEmpty ? null : Text(e.who),
          onTap: _busy ? null : () => _pick(e),
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(children: [
          SqBtn(icon: Icons.arrow_back_ios_new, tip: T.back, onTap: _busy ? null : app.fillCancel),
          const SizedBox(width: 10),
          Expanded(
            child: Text(T.fillFor(f.web.isNotEmpty ? f.web : f.pkg),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: TextField(
          controller: _q,
          style: const TextStyle(fontSize: 17),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search, color: Dpw.sub)),
          onChanged: (_) => setState(() {}),
        ),
      ),
      if (hits.isEmpty && q.trim().isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(T.fillNoMatch, style: const TextStyle(color: Dpw.sub)),
        ),
      Expanded(
        child: ListView(children: [
          for (final e in hits) tile(e, true),
          if (hits.isNotEmpty && rest.isNotEmpty) const Divider(),
          for (final e in rest) tile(e, false),
        ]),
      ),
    ]);
  }
}
