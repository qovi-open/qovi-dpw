// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER style.dart · 2026-11-01 · lot 2i (bouton carre avec image)
// Palette et gros boutons de DpW : rouge DpW sur fond pierre chaude
// (decision de Marc 01.11 : « on essaie le chaleureux et on voit a l'usage »).
// Gros boutons carres a cadre rouge, sans texte, utilisables sans lunettes.
import 'package:flutter/material.dart';

class Dpw {
  static const red = Color(0xFFC8322B);
  static const bg = Color(0xFFF6F1EB);
  static const card = Color(0xFFFFFDFB);
  static const btn = Color(0xFFF3ECE4);
  static const txt = Color(0xFF2B2420);
  static const sub = Color(0xFF8A7A6E);
  static const line = Color(0xFFE6DCD2);
  static const soft = [BoxShadow(color: Color(0x14503220), blurRadius: 10, offset: Offset(0, 3))];

  static const _avatars = [
    Color(0xFFC8322B), Color(0xFFD9822B), Color(0xFF2F855A),
    Color(0xFF6B46C1), Color(0xFF2B6CB0), Color(0xFFB7791F),
  ];

  /// Couleur stable d'une pastille, tiree du nom.
  static Color avatarOf(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _avatars[h % _avatars.length];
  }
}

/// Gros bouton carre : fond pierre, cadre rouge, icone rouge, pas de texte.
class SqBtn extends StatelessWidget {
  const SqBtn({
    super.key,
    required this.icon,
    required this.tip,
    this.onTap,
    this.size = 48,
    this.muted = false,
    this.child,
  });
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final double size;
  final bool muted;
  /// Image a la place de l'icone (SignIn, SignOut).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final col = (muted || onTap == null) ? Dpw.sub : Dpw.red;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(size > 56 ? 18 : 15),
      side: BorderSide(color: muted ? Dpw.line : col, width: 2),
    );
    return Tooltip(
      message: tip,
      child: Material(
        color: Dpw.btn,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Center(child: child ?? Icon(icon, color: col, size: size * 0.5))),
        ),
      ),
    );
  }
}

/// Place vide de la taille d'un bouton (garde l'alignement des colonnes).
class SqGap extends StatelessWidget {
  const SqGap({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}
