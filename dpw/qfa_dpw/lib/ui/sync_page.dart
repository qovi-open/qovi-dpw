// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER sync_page.dart · 2026-11-06 · lot 14 (scan : toute l'image analysee, sans cadre trompeur)
// Ecran « Synchroniser » : une zone (QR affiche ou camera) et des gros boutons
// dessines, sans texte (planche validee par Marc le 01.11).
//  - Envoyer  : cet appareil AFFICHE le QR (le PC n'a que ce bouton).
//  - Recevoir : cet appareil SCANNE le QR de l'autre (telephone seulement).
// Rien ne demarre tout seul : la zone reste vide jusqu'a l'appui.
// (Sous le capot, la synchro va toujours dans les deux sens.)
// Lot 13 : un QR lu n'est plus jamais ignore en silence : trousseau ferme ou
// echange deja en cours -> message ; apres un echec, le scanner se rearme ;
// le journal Android (balise flutter) trace chaque lecture par sa LONGUEUR
// seulement (le contenu est une cle de rendez-vous : jamais journalise), et
// toutes les 30 images sans QR lisible, une ligne « rien de lisible ».
// Lot 14 (cause trouvee le 06.11) : par defaut flutter_zxing n'analyse qu'un
// carre au CENTRE de l'image camera (cropPercent 0.5) mais dessine son cadre
// rouge ailleurs : l'usager visait le cadre, le decodeur regardait dessous.
// Toute l'image est donc analysee (cropPercent 1.0) et le cadre est retire.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../txt.dart';
import 'app_state.dart';
import 'style.dart';

bool get _hasCamera => Platform.isAndroid || Platform.isIOS;

enum _Mode { none, show, scan }

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.app});
  final AppState app;
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  _Mode _mode = _Mode.none;
  bool _scanned = false;
  int _misses = 0;

  void _send() {
    if (widget.app.syncBusy) return;
    setState(() => _mode = _Mode.show);
    widget.app.syncShowQr();
  }

  void _receive() {
    if (widget.app.syncBusy) return;
    setState(() {
      _mode = _Mode.scan;
      _scanned = false;
      _misses = 0;
    });
    debugPrint('DpW scan : scanner ouvert');
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onScan(String? v) async {
    if (v == null || v.isEmpty) return;
    if (_scanned) {
      debugPrint('DpW scan : QR lu (${v.length} car.) ignore, echange deja lance');
      return;
    }
    _scanned = true;
    debugPrint('DpW scan : QR lu (${v.length} car.)');
    final app = widget.app;
    if (!app.unlocked) {
      debugPrint('DpW scan : refuse, trousseau ferme');
      _say(T.syncFail);
      _scanned = false;
      return;
    }
    if (app.syncBusy) {
      debugPrint('DpW scan : refuse, echange deja en cours');
      _say(T.syncSwap);
      _scanned = false;
      return;
    }
    await app.syncWithCode(v);
    debugPrint('DpW scan : echange termine (${app.error == null ? 'ok' : 'echec'})');
    // Apres un succes la page se ferme ; apres un echec, le scanner se rearme.
    if (mounted) setState(() => _scanned = false);
  }

  void _onMiss(Code c) {
    _misses++;
    if (_misses % 30 == 0) {
      debugPrint('DpW scan : $_misses images sans QR lisible${c.error == null ? '' : ' (${c.error})'}');
    }
  }

  Widget _zone() {
    final app = widget.app;
    if (app.syncQr != null) {
      return Center(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(data: app.syncQr!, size: 240),
        ),
      );
    }
    if (app.syncBusy) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: Dpw.red),
        if (app.syncStatus.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(app.syncStatus, textAlign: TextAlign.center, style: const TextStyle(color: Dpw.sub)),
        ],
      ]);
    }
    if (_mode == _Mode.scan && _hasCamera) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        // Scanner libre (flutter_zxing, MIT, sur zxing-cpp Apache 2.0) : pas de
        // Google ML Kit, licence compatible avec la GPL (decision de Marc 02.11).
        child: ReaderWidget(
          codeFormat: Format.qrCode,
          showGallery: false,
          showToggleCamera: false,
          showFlashlight: false,
          onScan: (Code c) => _onScan(c.isValid ? c.text : null),
          onScanFailure: _onMiss,
          cropPercent: 1.0,
          showScannerOverlay: false,
        ),
      );
    }
    return const SizedBox.expand();
  }

  @override
  Widget build(BuildContext context) {
    final send = _BigBtn(
      tip: T.send,
      onTap: _send,
      children: [
        Icon(_hasCamera ? Icons.phone_android : Icons.desktop_windows_outlined, size: 54, color: Dpw.red),
        const Icon(Icons.qr_code_2, size: 40, color: Dpw.red),
        const Icon(Icons.east, size: 36, color: Dpw.red),
      ],
    );
    final receive = _BigBtn(
      tip: T.receive,
      onTap: _receive,
      children: const [
        Icon(Icons.east, size: 36, color: Dpw.red),
        Icon(Icons.qr_code_scanner, size: 46, color: Dpw.red),
        Icon(Icons.phone_android, size: 54, color: Dpw.red),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Column(children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Dpw.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Dpw.line, width: 2),
            ),
            child: _zone(),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 130,
          child: Row(children: [
            Expanded(child: send),
            if (_hasCamera) ...[const SizedBox(width: 12), Expanded(child: receive)],
          ]),
        ),
      ]),
    );
  }
}

/// Gros bouton dessine (icones seules), fond pierre, cadre rouge.
class _BigBtn extends StatelessWidget {
  const _BigBtn({required this.tip, required this.onTap, required this.children});
  final String tip;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: Dpw.red, width: 2),
    );
    return Tooltip(
      message: tip,
      child: Material(
        color: Dpw.btn,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: children)),
        ),
      ),
    );
  }
}
