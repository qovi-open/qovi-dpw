// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER main.dart · 2026-11-20 · lot 23 (W13 : portrait sur telephone)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'core/win_pos.dart';
import 'ui/app_state.dart';
import 'ui/pages.dart';
import 'ui/style.dart';

/// Taille de la fenetre WL (360 x 580) : sert seulement a la PREMIERE ouverture.
/// W6 (Marc 06.11) : le ratio n'est plus impose, l'usager redimensionne librement.
const double kRatio = 360 / 580;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  // W13 (Marc 19.11) : sur telephone, l'app reste en portrait. La vue plein
  // ecran d'une carte tourne l'IMAGE (RotatedBox), pas l'ecran.
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    // W4 : reprendre la place de la derniere fermeture, si elle est visible.
    final saved = await WinPos.load();
    final Rect? pos = (saved != null && await WinPos.visible(saved)) ? saved : null;
    final Offset? at = pos?.topLeft;
    final opts = WindowOptions(
      size: pos?.size ?? const Size(400, 400 / kRatio),
      minimumSize: const Size(330, 480),
      center: at == null,
      title: 'Qovi DpW',
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      if (at != null) await windowManager.setPosition(at);
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
      // W4 : retenir la place avant de cacher la fenetre.
      await WinPos.save(await windowManager.getBounds()).timeout(const Duration(seconds: 1));
    } catch (_) {
      // la place n'est pas essentielle
    }
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
