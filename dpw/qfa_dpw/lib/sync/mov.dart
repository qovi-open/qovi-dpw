// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER mov.dart · 2026-11-10 · lot 17 (contenu commun VaultData.toJson : filtres et dates)
// Synchro du trousseau entre deux appareils via le service DpW (port 6998).
//
//   A = l'appareil qui AFFICHE le QR (le PC, ou un telephone « afficher mon QR »)
//   S = l'appareil qui SCANNE (un telephone)
//
//   A tire MSB, LSB (2 x 128 bits) et Qrc. Cle de session K = MSB|LSB.
//     A -> serveur  etape 4 : LSB + Qrc (chiffres avec la cle SoK de A),
//                             puis le trousseau de A chiffre avec K
//     QR affiche    "DPWS" + MSB + Qrc  (le MSB ne passe JAMAIS par le serveur)
//     S -> serveur  etape 5 : Qrc ; recoit LSB + trousseau de A, fusionne,
//                             depose SON trousseau (avant fusion) chiffre avec K
//     A -> serveur  etape 3 : recupere le trousseau de S, fusionne
//   La fusion etant symetrique, A et S finissent avec le meme trousseau.
//
// SECURITE : K, MSB, LSB et la cle SoK ne sont jamais journalises ni ecrits ;
// le bloc est chiffre en AES-256-GCM (authentifie, AAD "DPWS").
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fid_cmp/fid_cmp.dart' show ChFraming;
import 'package:pointycastle/export.dart';

import '../core/g1.dart';
import '../core/rand.dart';
import '../env.dart';
import '../txt.dart';
import 'merge.dart';

const String kQrPrefix = 'DPWS';
const int _resOk = 3; // Res_Ok_ic
const Duration kSyncWindow = Duration(minutes: 10);
const List<int> _aad = [0x44, 0x50, 0x57, 0x53]; // "DPWS"

class SyncError implements Exception {
  SyncError(this.msg);
  final String msg;
  @override
  String toString() => msg;
}

// ── Fonctions pures (testees) ──────────────────────────────────────────────

/// Contenu du QR : "DPWS" + MSB(32 hex) + Qrc(32 hex).
String qrText(String msb, String qrc) => '$kQrPrefix$msb$qrc';

/// Lit un QR de synchro : (MSB, Qrc), ou null si ce n'est pas un QR DpW.
(String, String)? parseQr(String raw) {
  final t = raw.trim().toLowerCase();
  final p = kQrPrefix.toLowerCase();
  if (!t.startsWith(p) || t.length != p.length + 64) return null;
  final body = t.substring(p.length);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(body)) return null;
  return (body.substring(0, 32), body.substring(32));
}

/// Chiffre un trousseau avec K (64 hex) : base64(nonce(12) + GCM(JSON)).
String sealBlob(VaultData d, String k) {
  final nonce = randBytes(12);
  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(hexToBytes(k)), 128, nonce, Uint8List.fromList(_aad)));
  final clr = utf8.encode(jsonEncode(d.toJson()));
  return base64.encode([...nonce, ...gcm.process(Uint8List.fromList(clr))]);
}

/// Dechiffre un bloc ; SyncError si la cle est fausse ou le bloc altere.
VaultData openBlob(String b64, String k) {
  try {
    final b = base64.decode(b64.trim());
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(hexToBytes(k)), 128, b.sublist(0, 12), Uint8List.fromList(_aad)));
    final m = jsonDecode(utf8.decode(gcm.process(b.sublist(12))));
    final d = VaultData.fromJson(m);
    if (d == null) throw SyncError(T.recvInvalid);
    return d;
  } on SyncError {
    rethrow;
  } catch (_) {
    throw SyncError(T.recvUnreadable);
  }
}

// ── Connexion : plusieurs trames sur une meme socket ───────────────────────
class _Link {
  _Link(this._s) {
    _s.listen((d) {
      _buf = ChFraming.drain(Uint8List.fromList([..._buf, ...d]), (p) {
        _frames.add(utf8.decode(p, allowMalformed: true));
        _wake();
      });
    }, onDone: () {
      _closed = true;
      _wake();
    }, onError: (_) {
      _closed = true;
      _wake();
    });
  }

  final Socket _s;
  Uint8List _buf = Uint8List(0);
  final List<String> _frames = [];
  bool _closed = false;
  Completer<void>? _w;

  static Future<_Link> open(EnvCfg cfg) async {
    try {
      return _Link(await SecureSocket.connect(cfg.dpwHost, kMovPort,
          timeout: const Duration(seconds: 10)));
    } catch (_) {
      throw SyncError(T.dpwDown(cfg.dpwHost));
    }
  }

  void _wake() {
    final w = _w;
    _w = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  void send(String t) => _s.add(ChFraming.frame(utf8.encode(t)));

  Future<String> next() async {
    final end = DateTime.now().add(const Duration(seconds: 25));
    while (_frames.isEmpty) {
      if (_closed) throw SyncError(T.dpwClosed);
      final left = end.difference(DateTime.now());
      if (left.isNegative) throw SyncError(T.dpwNoReply);
      _w = Completer<void>();
      await _w!.future.timeout(left, onTimeout: () {});
    }
    return _frames.removeAt(0);
  }

  void close() {
    try {
      _s.destroy();
    } catch (_) {}
  }
}

/// Refus en clair du serveur ({"Tip":{"r":1,"s":motif}}) : le motif, sinon null.
String? _refusal(String t) {
  try {
    final m = jsonDecode(t);
    final tip = m is Map ? m['Tip'] : null;
    if (tip is Map && tip['r'] != _resOk) return (tip['s'] ?? 'refus').toString();
  } catch (_) {}
  return null;
}

String _why(String motif) => switch (motif) {
      'transfert' => T.qrUsed,
      'compte' => T.otherAccount,
      'meme appareil' => T.sameDevice,
      'mobile' => T.unknownDevice,
      _ => T.dpwRefusedWhy(motif),
    };

/// Cle G1 de la synchro, derivee de SoK (lot 3a : AES-GCM au lieu d'Uid256).
Uint8List _movKey(String sok) => g1Key(sok, kG1Mov);

/// Accuse chiffre (G1, contexte [aad]), ou refus en clair.
void _expectOk(String rep, String sok, String aad) {
  final clr = g1Open(_movKey(sok), aad, rep);
  if (clr == null) throw SyncError(_why(_refusal(rep) ?? 'refus'));
  final m = jsonDecode(clr);
  final tip = m is Map ? m['Tip'] : null;
  if (tip is! Map || tip['r'] != _resOk) throw SyncError(T.dpwRefused);
}

// ── A : l'appareil qui affiche le QR ───────────────────────────────────────
class SyncHost {
  SyncHost(this.cfg, this.mobU, this.sok);
  final EnvCfg cfg;
  final String mobU, sok;
  final String _msb = randHex(16), _lsb = randHex(16), _qrc = randHex(16);
  bool _cancelled = false;

  String get qr => qrText(_msb, _qrc);
  String get _k => '$_msb$_lsb';
  void cancel() => _cancelled = true;

  /// Etape 4 : depose LSB + Qrc puis le trousseau de A.
  Future<void> open(VaultData local) async {
    final l = await _Link.open(cfg);
    try {
      final mob = mobU.toLowerCase();
      l.send('4$mobU${g1Seal(_movKey(sok), 'q4|$mob', '$_lsb$_qrc')}');
      _expectOk(await l.next(), sok, 'r4|$mob');
      l.send(sealBlob(local, _k));
      _expectOk(await l.next(), sok, 'r4|$mob');
    } finally {
      l.close();
    }
  }

  /// Etape 3, relancee toutes les 3 s : le trousseau de S, une fois depose.
  Future<VaultData> waitPeer() async {
    final end = DateTime.now().add(kSyncWindow);
    while (!_cancelled) {
      if (DateTime.now().isAfter(end)) throw SyncError(T.timeout10);
      final l = await _Link.open(cfg);
      String rep;
      try {
        l.send('3$_qrc');
        rep = await l.next();
      } finally {
        l.close();
      }
      final why = _refusal(rep);
      if (why == null) return openBlob(rep, _k);
      if (why != 'attente') throw SyncError(_why(why));
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw SyncError(T.syncCancelled);
  }
}

// ── S : l'appareil qui scanne ──────────────────────────────────────────────
class SyncJoin {
  SyncJoin(this.cfg, this.mobU, this.sok);
  final EnvCfg cfg;
  final String mobU, sok;

  /// Etape 5. [local] = le trousseau de S AVANT fusion (c'est lui qui part
  /// vers A). Renvoie le trousseau de A, que l'appelant fusionne.
  Future<VaultData> run(String qrRaw, VaultData local) async {
    final q = parseQr(qrRaw);
    if (q == null) throw SyncError(T.notDpwQr);
    final (msb, qrc) = q;
    final l = await _Link.open(cfg);
    try {
      final mob = mobU.toLowerCase();
      l.send('5$mobU${g1Seal(_movKey(sok), 'q5|$mob', qrc)}');
      final rep = await l.next();
      final clr = g1Open(_movKey(sok), 'r5|$mob', rep);
      if (clr == null) throw SyncError(_why(_refusal(rep) ?? 'refus'));
      final m = jsonDecode(clr);
      final lsb = (m is Map ? m['p'] : null)?.toString() ?? '';
      final blob = (m is Map ? m['s'] : null)?.toString() ?? '';
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(lsb) || blob.isEmpty) {
        throw SyncError(T.dpwIncomplete);
      }
      final k = '$msb$lsb';
      final remote = openBlob(blob, k);
      l.send(sealBlob(local, k));
      _expectOk(await l.next(), sok, 'r5|$mob');
      return remote;
    } finally {
      l.close();
    }
  }
}
