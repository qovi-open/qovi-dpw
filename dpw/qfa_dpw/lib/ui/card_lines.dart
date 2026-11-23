// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER card_lines.dart · 2026-11-20 · lot 24 (W14c : un rond peut passer d'un bord a l'autre)
// Recadrage d'une carte par 4 DROITES (W14b, idee et dessin de Marc 19.11),
// plus facile avec de gros doigts que 4 petits coins :
//  - chaque cote de la carte est une droite prolongee jusqu'au CADRE (l'image
//    moins une marge mx / my, pour que les ronds restent entiers a l'ecran) ;
//    elle porte un rond a chacun de ses deux points de sortie du cadre ;
//  - W14c (lot 24, essai de Marc 20.11 : une carte photographiee de travers
//    bloquait la translation) : un rond n'est PLUS attache a un bord. Sa
//    position est un parametre p sur le POURTOUR du cadre (0..1 haut, 1..2
//    droit, 2..3 bas, 3..4 gauche, dans le sens des aiguilles d'une montre) ;
//  - tirer un rond = il suit le doigt TOUT AUTOUR du cadre (coins compris),
//    l'autre bout reste : la PENTE change ;
//  - tirer le milieu = la droite se deplace PARALLELEMENT a elle-meme ; ses
//    deux ronds se replacent la ou elle croise le cadre, sur n'importe quel bord ;
//  - les coins de la carte = intersections des droites voisines ;
//  - garde-fou (Marc) : un geste qui rendrait le quadrilatere incoherent est
//    refuse, on reste a la DERNIERE POSITION COHERENTE ; refuses aussi : une
//    droite qui ne traverserait plus le cadre (corde < 10 %), ou couchee sur
//    un bord (deux ronds sur le meme bord).
// Tout est en FRACTIONS de l'image (0..1). Fonctions pures, testees.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Indices des droites.
const int kTop = 0, kRight = 1, kBottom = 2, kLeft = 3;

class CardLines {
  CardLines._(this.v, this.mx, this.my);

  /// Depart sur le cadre [f] de la camera (fractions de l'image).
  /// [mx], [my] : marge des ronds par rapport aux bords (fractions).
  factory CardLines.fromFrame(Rect f, double mx, double my) {
    final z = CardLines._(List.filled(8, 0), mx, my);
    double cx(double x) => x.clamp(mx, 1 - mx).toDouble();
    double cy(double y) => y.clamp(my, 1 - my).toDouble();
    final t = cy(f.top), r = cx(f.right), b = cy(f.bottom), l = cx(f.left);
    final c = CardLines._([
      z.paramOf(Offset(mx, t)), z.paramOf(Offset(1 - mx, t)), // haut : gauche, droite
      z.paramOf(Offset(r, my)), z.paramOf(Offset(r, 1 - my)), // droite : haut, bas
      z.paramOf(Offset(mx, b)), z.paramOf(Offset(1 - mx, b)), // bas : gauche, droite
      z.paramOf(Offset(l, my)), z.paramOf(Offset(l, 1 - my)), // gauche : haut, bas
    ], mx, my);
    if (c.corners() != null) return c;
    return CardLines.fromFrame(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8), mx, my); // repli
  }

  /// 8 parametres de POURTOUR (0..4) : [haut g, haut d, droite h, droite b,
  /// bas g, bas d, gauche h, gauche b] (position de depart ; un rond peut
  /// ensuite passer sur un autre bord).
  final List<double> v;
  final double mx, my;

  CardLines copy() => CardLines._(List.of(v), mx, my);

  static bool isHorizontal(int line) => line == kTop || line == kBottom;

  double get _w => 1 - 2 * mx;
  double get _h => 1 - 2 * my;

  /// Point du pourtour pour le parametre [p] (0..4).
  Offset point(double p) {
    var q = p % 4;
    if (q < 0) q += 4;
    if (q < 1) return Offset(mx + q * _w, my);
    if (q < 2) return Offset(1 - mx, my + (q - 1) * _h);
    if (q < 3) return Offset(1 - mx - (q - 2) * _w, 1 - my);
    return Offset(mx, 1 - my - (q - 3) * _h);
  }

  /// Parametre du point du pourtour le plus proche de [o].
  double paramOf(Offset o) {
    final x = o.dx.clamp(mx, 1 - mx).toDouble(), y = o.dy.clamp(my, 1 - my).toDouble();
    final dt = y - my, dr = 1 - mx - x, db = 1 - my - y, dl = x - mx;
    final m = math.min(math.min(dt, dr), math.min(db, dl));
    if (m == dt) return _w <= 0 ? 0 : (x - mx) / _w;
    if (m == dr) return 1 + (_h <= 0 ? 0 : (y - my) / _h);
    if (m == db) return 2 + (_w <= 0 ? 0 : (1 - mx - x) / _w);
    return 3 + (_h <= 0 ? 0 : (1 - my - y) / _h);
  }

  /// Les deux ronds de la droite [line] (fractions de l'image).
  (Offset, Offset) handles(int line) => (point(v[2 * line]), point(v[2 * line + 1]));

  /// Intersection de deux droites ; null si (presque) paralleles.
  static Offset? cross(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d = (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
    if (d.abs() < 1e-9) return null;
    final a = p1.dx * p2.dy - p1.dy * p2.dx, b = p3.dx * p4.dy - p3.dy * p4.dx;
    return Offset((a * (p3.dx - p4.dx) - (p1.dx - p2.dx) * b) / d, (a * (p3.dy - p4.dy) - (p1.dy - p2.dy) * b) / d);
  }

  /// Coins haut-gauche, haut-droit, bas-droit, bas-gauche ; null si le
  /// quadrilatere est incoherent (droites paralleles, coin hors de l'image,
  /// cotes croises, non convexe, ou trop petit).
  List<Offset>? corners() {
    Offset? at(int h, int w) {
      final (a, b) = handles(h);
      final (c, d) = handles(w);
      return cross(a, b, c, d);
    }

    final tl = at(kTop, kLeft), tr = at(kTop, kRight), br = at(kBottom, kRight), bl = at(kBottom, kLeft);
    if (tl == null || tr == null || br == null || bl == null) return null;
    final q = [tl, tr, br, bl];
    for (final p in q) {
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) return null;
    }
    // Haut au-dessus du bas, gauche a gauche de la droite.
    if (!(tl.dy < bl.dy && tr.dy < br.dy && tl.dx < tr.dx && bl.dx < br.dx)) return null;
    // Convexe : les 4 produits vectoriels du meme signe.
    var pos = 0, neg = 0;
    for (var i = 0; i < 4; i++) {
      final a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4];
      final z = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (z > 0) pos++;
      if (z < 0) neg++;
    }
    if (pos != 4 && neg != 4) return null;
    // Pas trop petit (10 % de l'image dans chaque sens).
    if ((tr.dx - tl.dx) < 0.1 || (br.dx - bl.dx) < 0.1 || (bl.dy - tl.dy) < 0.1 || (br.dy - tr.dy) < 0.1) {
      return null;
    }
    return q;
  }

  /// Une droite valable : ses deux ronds assez eloignes et pas couchee sur un bord.
  bool _okLine(Offset a, Offset b) {
    if ((a - b).distance < 0.1) return false;
    const e = 1e-6;
    bool on(double u, double lo, double hi) => (u - lo).abs() < e || (u - hi).abs() < e;
    if ((a.dx - b.dx).abs() < e && on(a.dx, mx, 1 - mx)) return false;
    if ((a.dy - b.dy).abs() < e && on(a.dy, my, 1 - my)) return false;
    return true;
  }

  /// Pente : le rond [end] (0 ou 1) de la droite [line] va au point du
  /// pourtour le plus proche de [pos] (il peut changer de bord). Refuse
  /// (false, rien ne change) si le resultat est incoherent.
  bool moveEnd(int line, int end, Offset pos) {
    final i = 2 * line + end, old = v[i];
    final np = paramOf(pos);
    final other = point(v[2 * line + 1 - end]);
    if (!_okLine(point(np), other)) return false;
    v[i] = np;
    if (corners() != null) return true;
    v[i] = old;
    return false;
  }

  /// La droite passant par [p] de direction [d], coupee par le cadre :
  /// ses deux points de sortie, ou null si elle ne le traverse pas.
  (Offset, Offset)? _clip(Offset p, Offset d) {
    var t0 = double.negativeInfinity, t1 = double.infinity;
    bool axis(double pv, double dv, double lo, double hi) {
      if (dv.abs() < 1e-12) return pv >= lo - 1e-12 && pv <= hi + 1e-12;
      var a = (lo - pv) / dv, b = (hi - pv) / dv;
      if (a > b) (a, b) = (b, a);
      t0 = math.max(t0, a);
      t1 = math.min(t1, b);
      return true;
    }

    if (!axis(p.dx, d.dx, mx, 1 - mx) || !axis(p.dy, d.dy, my, 1 - my)) return null;
    if (t0 > t1 || t0.isInfinite || t1.isInfinite) return null;
    return (p + d * t0, p + d * t1);
  }

  /// Translation parallele de la droite [line] de [delta] (fractions) : ses
  /// ronds se replacent la ou elle croise le cadre, sur n'importe quel bord.
  /// Refusee si elle ne traverse plus le cadre, ou si le resultat est incoherent.
  bool shift(int line, Offset delta) {
    final i = 2 * line, oa = v[i], ob = v[i + 1];
    final (a, b) = handles(line);
    final na = a + delta, nb = b + delta;
    final c = _clip(na, nb - na);
    if (c == null) return false;
    var (p, q) = c;
    // Chaque rond garde son « cote » de la droite : le plus proche de son ancienne place.
    if ((p - na).distance + (q - nb).distance > (q - na).distance + (p - nb).distance) (p, q) = (q, p);
    if (!_okLine(p, q)) return false;
    v[i] = paramOf(p);
    v[i + 1] = paramOf(q);
    if (corners() != null) return true;
    v[i] = oa;
    v[i + 1] = ob;
    return false;
  }
}

/// Distance d'un point a la droite passant par [a] et [b] (meme repere).
double distToLine(Offset p, Offset a, Offset b) {
  final d = b - a;
  final n = d.distance;
  if (n == 0) return (p - a).distance;
  return ((p.dx - a.dx) * d.dy - (p.dy - a.dy) * d.dx).abs() / n;
}

/// true si [p] est a l'interieur du polygone convexe [q] (meme repere).
bool insideQuad(Offset p, List<Offset> q) {
  var pos = 0, neg = 0;
  for (var i = 0; i < q.length; i++) {
    final a = q[i], b = q[(i + 1) % q.length];
    final z = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    if (z > 0) pos++;
    if (z < 0) neg++;
  }
  return pos == 0 || neg == 0;
}
