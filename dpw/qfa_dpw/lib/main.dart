// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER main.dart · 2026-11-01 · lot 2n (fermeture immediate de la fenetre)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/app_state.dart';
import 'ui/pages.dart';
import 'ui/style.dart';

/// Taille de la fenetre WL (360 x 580) : meme ratio qu'un telephone.
const double kRatio = 360 / 580;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(400, 400 / kRatio),
      minimumSize: Size(330, 330 / kRatio),
      center: true,
      title: 'Qovi DpW',
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.setAspectRatio(kRatio);
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(_CloseGuard(app));
  }
  runApp(DpwApp(app: app));
  await app.init();
}

/// A la fermeture : la fenetre disparait TOUT DE SUITE (lot 2n : elle mettait
/// ~3 s a se fermer), puis on efface le mot de passe copie s'il est encore
/// dans le presse-papiers, et on termine (la cle du trousseau disparait avec
/// l'app).
class _CloseGuard with WindowListener {
  _CloseGuard(this.app);
  final AppState app;

  @override
  void onWindowClose() async {
    try {
      await windowManager.hide();
      await app.clearClipboard().timeout(const Duration(seconds: 2));
    } catch (_) {
      // fermeture quoi qu'il arrive
    } finally {
      await windowManager.destroy();
    }
  }
}

class DpwApp extends StatelessWidget {
  const DpwApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qovi DpW',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Dpw.red, primary: Dpw.red, surface: Dpw.bg),
        scaffoldBackgroundColor: Dpw.bg,
        appBarTheme: const AppBarTheme(
            backgroundColor: Dpw.bg, foregroundColor: Dpw.txt, elevation: 0, scrolledUnderElevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Dpw.card,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Dpw.line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Dpw.line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Dpw.red, width: 2)),
        ),
      ),
      home: Shell(app: app),
    );
  }
}
