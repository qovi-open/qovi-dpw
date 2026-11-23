// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER card_cam.dart · 2026-11-20 · lot 24 (W14c : ronds sur tout le pourtour ; lot 23 : W18, W13)
// Prise de vue d'une carte (W14, decisions de Marc 19.11) :
//  1. camera ARRIERE de l'app (plugin camera, deja tire par flutter_zxing) avec
//     un cadre au format carte ISO ID-1 (85,6 x 54 mm, rapport 1,586) : aucune
//     autre app ne voit l'image, rien ne part dans la galerie ;
//  2. le fichier temporaire de la camera est lu puis SUPPRIME aussitot ;
//  3. RECADRAGE par 4 droites (W14b, card_lines.dart : ronds au bout des
//     droites, pente ou translation, garde-fou) ; un toucher a l'interieur
//     ou « Valider » redresse la perspective (copyRectify du paquet
//     image, Dart pur) vers 1200 x 757 px, JPEG qualite 85 (~100-150 Ko,
//     un QR de 15 mm fait ~200 px). L'image produite n'a AUCUNE metadonnee
//     (EXIF, GPS) : elle est recodee depuis les pixels.
// W18 (lot 23, Marc 20.11) : sur PC (Windows, Linux, macOS), pas de camera :
// on CHOISIT une image (JPEG ou PNG, 20 Mo au plus) ou on la GLISSE sur la
// case. DpW travaille sur une COPIE en memoire (le fichier d'origine n'est
// ni modifie ni efface), puis meme recadrage et meme redressement que la
// camera (1200 x 757, JPEG 85 : la regle « un lecteur doit lire le code »).
// Les traitements lourds tournent dans un isolat (compute).
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../txt.dart';
import 'app_state.dart';
import 'card_lines.dart';
import 'style.dart';

/// Rapport largeur / hauteur d'une carte ISO ID-1.
const double kCardRatio = 85.60 / 53.98;

/// Taille de la photo enregistree.
const int kCardW = 1200;
final int kCardH = (kCardW / kCardRatio).round(); // 757

/// Cote le plus long de l'image de travail (losange) : assez pour 1200 px utiles.
const int _kWork = 3000;

/// Largeur du cadre, en fraction de la largeur de l'apercu.
const double _kFrameW = 0.88;

/// Prise de vue possible sur cet appareil (W14 etape 1 : telephone seulement).
bool get canShootCard => Platform.isAndroid || Platform.isIOS;

/// W18 : choix d'une image du disque (PC seulement).
bool get canPickCard => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Une carte peut etre ajoutee sur cet appareil (camera ou image du disque).
bool get canAddCard => canShootCard || canPickCard;

/// Taille maximale d'une image du disque.
const int kPickMax = 20 * 1024 * 1024;

/// Telephone : camera ; PC : image du disque ([raw] = image glissee).
Future<Uint8List?> addCard(BuildContext context, AppState app, {Uint8List? raw}) =>
    canShootCard ? shootCard(context, app) : pickCard(context, app, raw: raw);

/// Cadre de depart pour une image du disque : le plus grand rectangle au
/// format carte, centre, a 92 % (fractions de l'image).
Rect cardFrameFor(int w, int h) {
  if (w <= 0 || h <= 0) return const Rect.fromLTWH(0.04, 0.04, 0.92, 0.92);
  final a = w / h;
  double fw, fh;
  if (a >= kCardRatio) {
    fh = 0.92;
    fw = 0.92 * kCardRatio / a;
  } else {
    fw = 0.92;
    fh = 0.92 * a / kCardRatio;
  }
  return Rect.fromLTWH((1 - fw) / 2, (1 - fh) / 2, fw, fh);
}

/// W18 : choisit (ou recoit, glissee) une image, puis le recadrage.
Future<Uint8List?> pickCard(BuildContext context, AppState app, {Uint8List? raw}) async {
  if (raw == null) {
    final f = await openFile(acceptedTypeGroups: [
      XTypeGroup(label: T.cardImgType, extensions: const ['jpg', 'jpeg', 'png']),
    ]);
    if (f == null) return null;
    if (await f.length() > kPickMax) {
      app.showError(T.cardTooBig);
      return null;
    }
    raw = await f.readAsBytes();
  }
  if (raw.length > kPickMax) {
    app.showError(T.cardTooBig);
    return null;
  }
  final p = await compute(_prepare, raw);
  if (p == null) {
    app.showError(T.cardNotImage);
    return null;
  }
  if (!context.mounted) return null;
  final w = p[1] as int, h = p[2] as int;
  final shot = _Shot(p[0] as Uint8List, w, h, cardFrameFor(w, h));
  final out = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => _CornerPage(app: app, shot: shot), fullscreenDialog: true),
  );
  if (out != null && !_origTold && context.mounted) {
    _origTold = true;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(T.cardOrigLeft), duration: const Duration(seconds: 8)));
  }
  return out;
}

bool _origTold = false;

/// Ouvre la camera puis le losange. Renvoie le JPEG redresse, ou null si
/// l'usager abandonne.
Future<Uint8List?> shootCard(BuildContext context, AppState app) async {
  final shot = await Navigator.of(context).push<_Shot>(
    MaterialPageRoute(builder: (_) => _CamPage(app: app), fullscreenDialog: true),
  );
  if (shot == null || !context.mounted) return null;
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => _CornerPage(app: app, shot: shot), fullscreenDialog: true),
  );
}

/// Photo de travail (orientation appliquee, sans EXIF) + cadre de depart
/// (fractions de l'image).
class _Shot {
  _Shot(this.jpeg, this.w, this.h, this.frame);
  final Uint8List jpeg;
  final int w, h;
  final Rect frame;
}

// ── Isolats ───────────────────────────────────────────────────────────────

/// Decode, applique l'orientation EXIF, reduit a _kWork, recode SANS EXIF.
/// Renvoie [jpeg, largeur, hauteur] ou null.
List<Object>? _prepare(Uint8List raw) {
  final d = img.decodeImage(raw);
  if (d == null) return null;
  var o = img.bakeOrientation(d);
  final long = o.width > o.height ? o.width : o.height;
  if (long > _kWork) {
    o = o.width >= o.height ? img.copyResize(o, width: _kWork) : img.copyResize(o, height: _kWork);
  }
  return [img.encodeJpg(o, quality: 92), o.width, o.height];
}

/// Redresse le quadrilatere [q] (8 valeurs en PIXELS : haut-gauche,
/// haut-droit, bas-droit, bas-gauche) vers kCardW x kCardH, JPEG 85.
Uint8List? _rectify(List<Object> a) {
  final d = img.decodeJpg(a[0] as Uint8List);
  if (d == null) return null;
  final q = [for (final v in a[1] as List) (v as num).toDouble()];
  final out = img.copyRectify(
    d,
    topLeft: img.Point(q[0], q[1]),
    topRight: img.Point(q[2], q[3]),
    bottomRight: img.Point(q[4], q[5]),
    bottomLeft: img.Point(q[6], q[7]),
    interpolation: img.Interpolation.linear,
    toImage: img.Image(width: kCardW, height: kCardH),
  );
  return img.encodeJpg(out, quality: 85);
}

/// Pour les tests : redressement direct (sans isolat).
@visibleForTesting
Uint8List? rectifyForTest(Uint8List jpeg, List<double> q) => _rectify([jpeg, q]);

/// W13 (lot 23) : toute l'app est en portrait sur telephone (main.dart) ;
/// la camera et le recadrage le restent, et en sortant on NE libere PLUS
/// l'orientation.
void _portrait(bool on) {
  if (!canShootCard) return;
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
}

/// Ferme la page si le trousseau se verrouille pendant qu'elle est ouverte,
/// ou des que l'app passe en arriere-plan (telephone mis en veille, autre
/// app) : une carte affichee ne reapparait jamais au reveil (essai de Marc
/// 19.11). Compte aussi les touchers comme activite.
class CardGuard extends StatefulWidget {
  const CardGuard({super.key, required this.app, required this.child});
  final AppState app;
  final Widget child;
  @override
  State<CardGuard> createState() => _CardGuardState();
}

class _CardGuardState extends State<CardGuard> with WidgetsBindingObserver {
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_check);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(_check);
    super.dispose();
  }

  /// Veille ou autre app : on ferme (« inactive » seul, ex. demande de
  /// permission de la camera, ne ferme pas).
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) _close();
  }

  void _check() {
    if (!widget.app.unlocked) _close();
  }

  void _close() {
    if (_gone) return;
    _gone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => widget.app.activity(),
        child: widget.child,
      );
}

// ── 1. Camera avec cadre ──────────────────────────────────────────────────
class _CamPage extends StatefulWidget {
  const _CamPage({required this.app});
  final AppState app;
  @override
  State<_CamPage> createState() => _CamPageState();
}

class _CamPageState extends State<_CamPage> {
  CameraController? _ctl;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _portrait(true);
    _start();
  }

  Future<void> _start() async {
    try {
      final all = await availableCameras();
      final back = all.where((c) => c.lensDirection == CameraLensDirection.back);
      if (all.isEmpty) throw StateError(T.camNone);
      final c = CameraController(back.isNotEmpty ? back.first : all.first, ResolutionPreset.ultraHigh,
          enableAudio: false);
      await c.initialize();
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
        await c.setFlashMode(FlashMode.off);
      } catch (_) {
        // reglages facultatifs
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctl = c);
    } catch (e) {
      if (mounted) setState(() => _err = T.camFail(e));
    }
  }

  @override
  void dispose() {
    _ctl?.dispose();
    _portrait(false);
    super.dispose();
  }

  /// Cadre en fractions de l'apercu (portrait : hauteur = largeur x rapport).
  Rect _frame(double previewAspect) {
    final fh = _kFrameW / kCardRatio * previewAspect; // previewAspect = l / h
    return Rect.fromLTWH((1 - _kFrameW) / 2, (1 - fh) / 2, _kFrameW, fh);
  }

  Future<void> _shoot() async {
    final c = _ctl;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    String? path;
    try {
      final x = await c.takePicture();
      path = x.path;
      final raw = await x.readAsBytes();
      final r = await compute(_prepare, raw);
      if (r == null) throw StateError(T.cardUnreadable);
      final aspect = 1 / c.value.aspectRatio; // apercu portrait : largeur / hauteur
      if (mounted) {
        Navigator.of(context).pop(_Shot(r[0] as Uint8List, r[1] as int, r[2] as int, _frame(aspect)));
      }
    } catch (e) {
      if (mounted) setState(() => _err = T.camFail(e));
    } finally {
      // Le fichier de la camera (en clair, dans le cache) disparait TOUT DE SUITE.
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctl;
    return CardGuard(
      app: widget.app,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(children: [
                SqBtn(icon: Icons.arrow_back_ios_new, tip: T.back, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(child: Text(T.camHint, style: const TextStyle(color: Colors.white, fontSize: 16))),
              ]),
            ),
            Expanded(
              child: Center(
                child: _err != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)))
                    : (c == null || !c.value.isInitialized)
                        ? const CircularProgressIndicator(color: Dpw.red)
                        : CameraPreview(
                            c,
                            child: LayoutBuilder(builder: (context, box) {
                              final f = _frame(box.maxWidth / box.maxHeight);
                              return CustomPaint(size: Size.infinite, painter: _FramePainter(f));
                            }),
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: _busy
                  ? const SizedBox(height: 84, child: Center(child: CircularProgressIndicator(color: Dpw.red)))
                  : SqBtn(icon: Icons.camera_alt_outlined, tip: T.camShoot, size: 84, onTap: c == null ? null : _shoot),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Assombrit autour du cadre et le dessine en rouge DpW.
class _FramePainter extends CustomPainter {
  _FramePainter(this.f);
  final Rect f;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(f.left * s.width, f.top * s.height, f.width * s.width, f.height * s.height);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
    final outside = Path()
      ..addRect(Offset.zero & s)
      ..addRRect(rr)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = const Color(0x88000000));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Dpw.red);
  }

  @override
  bool shouldRepaint(_FramePainter o) => o.f != f;
}

// ── 2. Recadrage par 4 droites (W14b), puis redressement ────────────────
class _CornerPage extends StatefulWidget {
  const _CornerPage({required this.app, required this.shot});
  final AppState app;
  final _Shot shot;
  @override
  State<_CornerPage> createState() => _CornerPageState();
}

class _CornerPageState extends State<_CornerPage> {
  static const double _r = 18; // rayon d'un rond
  static const double _grabEnd = 44; // prise d'un rond (px)
  static const double _grabLine = 36; // prise d'une droite (px)

  CardLines? _l; // cree a la 1re mise en page (les marges dependent de la taille)
  int? _line; // droite tenue
  int? _end; // rond tenu (null = droite entiere, translation)
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _portrait(true);
  }

  @override
  void dispose() {
    _portrait(false);
    super.dispose();
  }

  /// Zone ou l'image est affichee (BoxFit.contain) dans [box].
  Rect _area(Size box) {
    final s = widget.shot;
    final k = (box.width / s.w) < (box.height / s.h) ? box.width / s.w : box.height / s.h;
    final w = s.w * k, h = s.h * k;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Offset _toScreen(Offset f, Rect a) => Offset(a.left + f.dx * a.width, a.top + f.dy * a.height);

  Offset _toFrac(Offset p, Rect a) => Offset((p.dx - a.left) / a.width, (p.dy - a.top) / a.height);

  CardLines _lines(Rect a) =>
      _l ??= CardLines.fromFrame(widget.shot.frame, (_r + 6) / a.width, (_r + 6) / a.height);

  void _start(Offset p, Rect a) {
    final l = _lines(a);
    _line = null;
    _end = null;
    // 1. Un rond (bout de droite) : la pente changera.
    var bd = _grabEnd * _grabEnd;
    for (var i = 0; i < 4; i++) {
      final (h0, h1) = l.handles(i);
      for (final (e, h) in [(0, h0), (1, h1)]) {
        final d = (_toScreen(h, a) - p).distanceSquared;
        if (d < bd) {
          bd = d;
          _line = i;
          _end = e;
        }
      }
    }
    if (_line != null) return;
    // 2. Sinon, la droite la plus proche : elle se deplacera parallelement.
    var bl = _grabLine;
    for (var i = 0; i < 4; i++) {
      final (h0, h1) = l.handles(i);
      final d = distToLine(p, _toScreen(h0, a), _toScreen(h1, a));
      if (d < bl) {
        bl = d;
        _line = i;
      }
    }
  }

  void _move(DragUpdateDetails d, Rect a) {
    final i = _line, l = _l;
    if (i == null || l == null) return;
    final e = _end;
    setState(() {
      if (e != null) {
        // W14c : le rond suit le doigt tout autour du cadre (garde-fou dans moveEnd).
        l.moveEnd(i, e, _toFrac(d.localPosition, a));
      } else {
        // W14c : translation libre, les ronds se replacent sur le cadre.
        l.shift(i, Offset(d.delta.dx / a.width, d.delta.dy / a.height));
      }
    });
  }

  /// Un toucher bref A L'INTERIEUR du quadrilatere = Valider (W14b).
  void _tap(Offset p, Rect a) {
    final q = _l?.corners();
    if (q == null) return;
    if (insideQuad(p, [for (final c in q) _toScreen(c, a)])) _ok();
  }

  Future<void> _ok() async {
    final q0 = _l?.corners();
    if (_busy || q0 == null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final s = widget.shot;
    final q = <double>[for (final o in q0) ...[o.dx * s.w, o.dy * s.h]];
    try {
      final out = await compute(_rectify, <Object>[s.jpeg, q]);
      if (out == null) throw StateError(T.cardUnreadable);
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      if (mounted) setState(() => _err = T.camFail(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardGuard(
      app: widget.app,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(children: [
                SqBtn(icon: Icons.arrow_back_ios_new, tip: T.back, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(child: Text(T.linesHint, style: const TextStyle(color: Colors.white, fontSize: 15))),
              ]),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final a = _area(box.biggest);
                final l = _lines(a);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _tap(d.localPosition, a),
                  onPanStart: (d) => _start(d.localPosition, a),
                  onPanUpdate: (d) => _move(d, a),
                  onPanEnd: (_) => setState(() {
                    _line = null;
                    _end = null;
                  }),
                  child: Stack(children: [
                    Positioned.fromRect(
                        rect: a, child: Image.memory(widget.shot.jpeg, fit: BoxFit.fill, gaplessPlayback: true)),
                    Positioned.fill(
                      child: CustomPaint(painter: _LinesPainter(l, a, _line, _r)),
                    ),
                  ]),
                );
              }),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_err!, style: const TextStyle(color: Colors.white)),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: _busy
                  ? const SizedBox(height: 84, child: Center(child: CircularProgressIndicator(color: Dpw.red)))
                  : SqBtn(icon: Icons.check, tip: T.cornersOk, size: 84, onTap: _ok),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Les 4 droites prolongees jusqu'aux bords de l'image, leurs 8 ronds, et la
/// carte (quadrilatere) legerement eclaircie. La droite tenue est epaissie.
class _LinesPainter extends CustomPainter {
  _LinesPainter(this.l, this.a, this.held, this.r) : v = List.of(l.v);
  final CardLines l;
  final Rect a;
  final int? held;
  final double r;
  final List<double> v; // pour shouldRepaint

  Offset _s(Offset f) => Offset(a.left + f.dx * a.width, a.top + f.dy * a.height);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(a);
    final q = l.corners();
    if (q != null) {
      final card = Path()..addPolygon([for (final c in q) _s(c)], true);
      final outside = Path()
        ..addRect(a)
        ..addPath(card, Offset.zero)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(outside, Paint()..color = const Color(0x77000000));
    }
    for (var i = 0; i < 4; i++) {
      final (h0, h1) = l.handles(i);
      final p0 = _s(h0), p1 = _s(h1);
      final d = p1 - p0;
      // Prolongee bien au-dela de l'image : le clip la coupe au bord.
      final k = 4 * (a.width + a.height) / (d.distance == 0 ? 1 : d.distance);
      canvas.drawLine(
          p0 - d * k,
          p1 + d * k,
          Paint()
            ..strokeWidth = held == i ? 5 : 3
            ..color = Dpw.red);
    }
    canvas.restore();
    final fill = Paint()..color = const Color(0x99FFFFFF);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Dpw.red;
    for (var i = 0; i < 4; i++) {
      final (h0, h1) = l.handles(i);
      for (final h in [h0, h1]) {
        canvas.drawCircle(_s(h), r, fill);
        canvas.drawCircle(_s(h), r, ring);
      }
    }
  }

  @override
  bool shouldRepaint(_LinesPainter o) => o.held != held || o.a != a || o.v.join(',') != v.join(',');
}
