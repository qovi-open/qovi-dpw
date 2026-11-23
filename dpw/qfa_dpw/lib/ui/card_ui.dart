// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER card_ui.dart · 2026-11-20 · lot 23 (W18 : case « dossier » et glisser-deposer sur PC)
// Affichage des photos de carte (W14, maquette validee par Marc 19.11) :
//  - FICHE : une ligne « 💳 [recto] [verso] ». Case vide = icone camera (un
//    clic prend la photo de cette face) ; case pleine = vignette (un clic
//    l'affiche en grand, avec « Reprendre » et « Supprimer »). La case verso
//    n'apparait qu'une fois le recto pris : pas d'espace vide dans la fiche.
//  - LISTE : bouton 💳 (seulement si la fiche a une carte) = vue rapide,
//    recto en haut, verso en bas, luminosite au maximum ; un clic sur une face
//    l'affiche en plein ecran, tournee de 90° (pour un lecteur de QR).
//  - PC (W18, lot 23) : la case vide est un DOSSIER (choisir une image) et
//    accepte une image GLISSEE dessus (desktop_drop) ; meme recadrage ensuite.
//  - Photo absente de cet appareil (prise sur un autre, synchro etape 1) :
//    icone « nuage barre », rien n'est perdu.
// Les photos dechiffrees ne vivent qu'en memoire, le temps de l'affichage.
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../txt.dart';
import '../vault/entry.dart';
import 'app_state.dart';
import 'card_cam.dart';
import 'style.dart';

// ── Luminosite au maximum pendant l'affichage (Android, MainActivity.kt) ──
class _Bright {
  static const _ch = MethodChannel('dpw/screen');
  static int _n = 0;

  static void on() {
    if (++_n == 1) _set(true);
  }

  static void off() {
    if (_n == 0) return;
    if (--_n == 0) _set(false);
  }

  static void _set(bool v) {
    if (!Platform.isAndroid) return;
    _ch.invokeMethod<void>('bright', v).catchError((_) {});
  }
}

/// Une face de la carte, dechiffree a l'affichage.
class CardImg extends StatefulWidget {
  const CardImg({super.key, required this.app, required this.id, this.fit = BoxFit.cover, this.small = false});
  final AppState app;
  final String id;
  final BoxFit fit;
  final bool small;
  @override
  State<CardImg> createState() => _CardImgState();
}

class _CardImgState extends State<CardImg> {
  late Future<Uint8List?> _f;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  @override
  void didUpdateWidget(CardImg old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _f = _load();
  }

  Future<Uint8List?> _load() async => widget.app.vault?.cards.get(widget.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final b = s.data;
        if (b != null) return Image.memory(b, fit: widget.fit, gaplessPlayback: true);
        final here = widget.app.vault?.cards.has(widget.id) ?? false;
        final ic = Icon(here ? Icons.broken_image_outlined : Icons.cloud_off_outlined,
            color: Dpw.sub, size: widget.small ? 24 : 48);
        if (widget.small) return Center(child: ic);
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ic,
            const SizedBox(height: 8),
            Text(here ? T.cardUnreadable : T.cardElsewhere,
                textAlign: TextAlign.center, style: const TextStyle(color: Dpw.sub)),
          ]),
        );
      },
    );
  }
}

/// Cadre arrondi au format carte.
Widget _framed(Widget child, {double radius = 12}) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Dpw.card,
          border: Border.all(color: Dpw.line),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: AspectRatio(aspectRatio: kCardRatio, child: child),
      ),
    );

// ── Ligne « Carte » de la fiche ───────────────────────────────────────────
/// [ids] : references actuelles (recto, verso). [onChanged] recoit la
/// nouvelle liste ; [onCreated] chaque photo NOUVELLE (pour la retirer si
/// la fiche n'est pas enregistree).
class CardRow extends StatelessWidget {
  const CardRow({
    super.key,
    required this.app,
    required this.ids,
    required this.size,
    required this.lead,
    required this.onChanged,
    required this.onCreated,
  });
  final AppState app;
  final List<String> ids;
  final double size;
  final Widget lead;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<String> onCreated;

  /// La ligne n'a de sens que si on peut photographier, ou s'il y a deja une carte.
  static bool visible(List<String> ids) => ids.isNotEmpty || canAddCard;

  Future<void> _shoot(BuildContext context, int face, {Uint8List? raw}) async {
    final v = app.vault;
    final jpeg = await addCard(context, app, raw: raw);
    if (jpeg == null || v == null) return;
    try {
      final id = await v.cards.put(jpeg);
      onCreated(id);
      final l = List.of(ids);
      if (face < l.length) {
        l[face] = id;
      } else {
        l.add(id);
      }
      onChanged(l);
    } catch (e) {
      app.showError(T.cardSaveFail(e));
    }
  }

  Future<void> _open(BuildContext context, int face) async {
    final r = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _FacePage(app: app, id: ids[face], editable: true)),
    );
    if (!context.mounted) return;
    if (r == 'retake') {
      await _shoot(context, face);
    } else if (r == 'delete') {
      onChanged(List.of(ids)..removeAt(face));
    }
  }

  Widget _slot(BuildContext context, int face) {
    if (face < ids.length) {
      return SizedBox(
        height: size,
        width: size * kCardRatio,
        child: Material(
          color: Dpw.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Dpw.red, width: 2)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(context, face),
            child: Tooltip(
              message: face == 0 ? T.cardFront : T.cardBack,
              child: CardImg(app: app, id: ids[face], small: true),
            ),
          ),
        ),
      );
    }
    final btn = SqBtn(
      icon: canShootCard ? Icons.photo_camera_outlined : Icons.folder_open_outlined,
      tip: canShootCard
          ? (face == 0 ? T.cardShootFront : T.cardShootBack)
          : (face == 0 ? T.cardPickFront : T.cardPickBack),
      size: size,
      onTap: () => _shoot(context, face),
    );
    if (!canPickCard) return btn;
    // W18 : une image glissee sur la case (premier fichier seulement).
    return DropTarget(
      onDragDone: (d) async {
        if (d.files.isEmpty) return;
        final f = d.files.first;
        try {
          if (await f.length() > kPickMax) {
            app.showError(T.cardTooBig);
            return;
          }
          final raw = await f.readAsBytes();
          if (context.mounted) await _shoot(context, face, raw: raw);
        } catch (_) {
          app.showError(T.cardNotImage);
        }
      },
      child: btn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = <Widget>[];
    for (var face = 0; face < kCardFaces; face++) {
      final filled = face < ids.length;
      // Case vide : seulement la suivante a remplir, et si on peut en ajouter.
      if (!filled && (face > ids.length || !canAddCard)) continue;
      slots
        ..add(const SizedBox(width: 8))
        ..add(_slot(context, face));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [lead, ...slots]),
    );
  }
}

// ── Une face en grand (depuis la fiche) ───────────────────────────────────
class _FacePage extends StatefulWidget {
  const _FacePage({required this.app, required this.id, required this.editable});
  final AppState app;
  final String id;
  final bool editable;
  @override
  State<_FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<_FacePage> {
  @override
  void initState() {
    super.initState();
    _Bright.on();
  }

  @override
  void dispose() {
    _Bright.off();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(T.cardDelAsk),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(T.no)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(T.delete)),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop('delete');
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return CardGuard(
      app: app,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(children: [
              Row(children: [
                SqBtn(icon: Icons.arrow_back_ios_new, tip: T.back, size: 56, onTap: () => Navigator.of(context).pop()),
                const Spacer(),
                if (widget.editable && canAddCard) ...[
                  SqBtn(
                      icon: canShootCard ? Icons.photo_camera_outlined : Icons.folder_open_outlined,
                      tip: T.cardRetake,
                      size: 56,
                      onTap: () => Navigator.of(context).pop('retake')),
                  const SizedBox(width: 10),
                ],
                if (widget.editable) SqBtn(icon: Icons.delete_outline, tip: T.cardDelete, size: 56, onTap: _delete),
              ]),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => openFullFace(context, app, widget.id),
                child: _framed(CardImg(app: app, id: widget.id)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Vue rapide depuis la liste : recto en haut, verso en bas ─────────────
Future<void> showCardQuick(BuildContext context, AppState app, Entry e) => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => _QuickPage(app: app, e: e)),
    );

class _QuickPage extends StatefulWidget {
  const _QuickPage({required this.app, required this.e});
  final AppState app;
  final Entry e;
  @override
  State<_QuickPage> createState() => _QuickPageState();
}

class _QuickPageState extends State<_QuickPage> {
  @override
  void initState() {
    super.initState();
    _Bright.on();
  }

  @override
  void dispose() {
    _Bright.off();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, e = widget.e;
    return CardGuard(
      app: app,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(children: [
              Row(children: [
                SqBtn(icon: Icons.arrow_back_ios_new, tip: T.back, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.nam.isEmpty ? T.noName : e.nam,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Dpw.txt)),
                ),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(children: [
                  for (final id in e.crd) ...[
                    GestureDetector(
                      onTap: () => openFullFace(context, app, id),
                      child: _framed(CardImg(app: app, id: id)),
                    ),
                    const SizedBox(height: 16),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Plein ecran, tourne de 90° (pour un lecteur de QR) ───────────────────
Future<void> openFullFace(BuildContext context, AppState app, String id) => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => _FullPage(app: app, id: id), fullscreenDialog: true),
    );

class _FullPage extends StatefulWidget {
  const _FullPage({required this.app, required this.id});
  final AppState app;
  final String id;
  @override
  State<_FullPage> createState() => _FullPageState();
}

class _FullPageState extends State<_FullPage> {
  @override
  void initState() {
    super.initState();
    _Bright.on();
  }

  @override
  void dispose() {
    _Bright.off();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CardGuard(
      app: widget.app,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: SafeArea(
            child: Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AspectRatio(
                    aspectRatio: kCardRatio,
                    child: CardImg(app: widget.app, id: widget.id, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
