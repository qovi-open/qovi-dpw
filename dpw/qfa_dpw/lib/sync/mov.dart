// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER mov.dart · 2026-11-19 · lot 22 (W14 etape 2 : photos de carte, etapes 6/7, memoire seule cote serveur)
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
//
// PHOTOS DE CARTE (W14 etape 2, lot 22) : chaque bloc porte aussi `img`, la
// liste des photos que l'appareil POSSEDE (chiffree avec le reste par K ; les
// versions 3.5 l'ignorent). Apres la fusion, chacun sait donc ce qui manque a
// l'autre : il le depose (etape 6) et releve ce qui lui manque (etape 7).
// Une photo voyage en morceaux de 256 Ko chiffres par K (AES-GCM, AAD
// "DPWP"+id|c|n) : le serveur, qui n'a pas K, ne les lit pas et ne les garde
// qu'en memoire. Un echec des photos n'annule JAMAIS la synchro des fiches.
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
import '../vault/entry.dart' show kCardId;
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
/// [img] : les photos que cet appareil possede (lot 22), jointes au bloc.
String sealBlob(VaultData d, String k, {Iterable<String>? img}) {
  final nonce = randBytes(12);
  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(hexToBytes(k)), 128, nonce, Uint8List.fromList(_aad)));
  final m = d.toJson();
  if (img != null) m['img'] = img.toSet().toList()..sort();
  final clr = utf8.encode(jsonEncode(m));
  return base64.encode([...nonce, ...gcm.process(Uint8List.fromList(clr))]);
}

/// Dechiffre un bloc ; SyncError si la cle est fausse ou le bloc altere.
VaultData openBlob(String b64, String k) => openBlobImg(b64, k).$1;

/// Le trousseau ET la liste des photos de l'autre (null : version sans photos).
(VaultData, Set<String>?) openBlobImg(String b64, String k) {
  try {
    final b = base64.decode(b64.trim());
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(hexToBytes(k)), 128, b.sublist(0, 12), Uint8List.fromList(_aad)));
    final m = jsonDecode(utf8.decode(gcm.process(b.sublist(12))));
    final d = VaultData.fromJson(m);
    if (d == null) throw SyncError(T.recvInvalid);
    final l = m is Map ? m['img'] : null;
    final img = l is List ? {for (final x in l) if (x is String && kCardId.hasMatch(x)) x} : null;
    return (d, img);
  } on SyncError {
    rethrow;
  } catch (_) {
    throw SyncError(T.recvUnreadable);
  }
}

// ── Photos : fonctions pures (testees) ─────────────────────────────────────
const int kPhotoChunk = 256 * 1024;
const int kPhotoParts = 8; // 2 Mo au plus par photo (borne du serveur : 8)
const int kPhotoMax = kPhotoChunk * kPhotoParts;
const List<int> _aadP = [0x44, 0x50, 0x57, 0x50]; // "DPWP"

Uint8List _aadPart(String id, int c, int n) => Uint8List.fromList([..._aadP, ...utf8.encode('$id|$c|$n')]);

bool isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

/// Une photo en morceaux chiffres par K : trames {"i","c","n","d"}.
List<String> photoFrames(String id, Uint8List jpeg, String k) {
  if (!kCardId.hasMatch(id) || jpeg.isEmpty || jpeg.length > kPhotoMax) return const [];
  final n = (jpeg.length + kPhotoChunk - 1) ~/ kPhotoChunk;
  return [
    for (var c = 0; c < n; c++)
      () {
        final part = jpeg.sublist(c * kPhotoChunk, (c + 1) * kPhotoChunk > jpeg.length ? jpeg.length : (c + 1) * kPhotoChunk);
        final nonce = randBytes(12);
        final gcm = GCMBlockCipher(AESEngine())
          ..init(true, AEADParameters(KeyParameter(hexToBytes(k)), 128, nonce, _aadPart(id, c, n)));
        return jsonEncode({'i': id, 'c': c, 'n': n, 'd': base64.encode([...nonce, ...gcm.process(part)])});
      }()
  ];
}

/// Reassemble les photos recues ; [add] rend (id, JPEG) quand une photo est
/// complete et valide, sinon null. Un morceau faux (cle, contexte) est ignore.
class PhotoJoin {
  PhotoJoin(this.k);
  final String k;
  final Map<String, List<Uint8List?>> _p = {};

  (String, Uint8List)? add(String frame) {
    try {
      final m = jsonDecode(frame);
      if (m is! Map) return null;
      final id = m['i'], c = m['c'], n = m['n'], d = m['d'];
      if (id is! String || !kCardId.hasMatch(id) || c is! int || n is! int) return null;
      if (n < 1 || n > kPhotoParts || c < 0 || c >= n || d is! String) return null;
      final b = base64.decode(d);
      if (b.length < 12 + 16) return null;
      final gcm = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(hexToBytes(k)), 128, b.sublist(0, 12), _aadPart(id, c, n)));
      final part = gcm.process(b.sublist(12));
      final l = _p.putIfAbsent(id, () => List<Uint8List?>.filled(n, null));
      if (l.length != n) return null;
      l[c] = part;
      if (l.any((x) => x == null)) return null;
      _p.remove(id);
      final jpeg = Uint8List.fromList([for (final x in l) ...x!]);
      return (jpeg.length <= kPhotoMax && isJpeg(jpeg)) ? (id, jpeg) : null;
    } catch (_) {
      return null;
    }
  }
}

/// Ce qu'il faut envoyer et recevoir : [used] = photos referencees par le
/// trousseau fusionne, [mine] = presentes ici, [peer] = presentes chez l'autre
/// (null : l'autre n'echange pas de photos).
class PhotoPlan {
  PhotoPlan(this.send, this.get);
  final List<String> send;
  final Set<String> get;
  bool get isEmpty => send.isEmpty && get.isEmpty;

  factory PhotoPlan.of(Set<String> used, Set<String> mine, Set<String>? peer) {
    if (peer == null) return PhotoPlan(const [], const {});
    return PhotoPlan(
        [for (final id in used) if (mine.contains(id) && !peer.contains(id)) id]..sort(),
        {for (final id in used) if (peer.contains(id) && !mine.contains(id)) id});
  }
}

class PhotoResult {
  PhotoResult(this.sent, this.got, this.want, this.failed);
  final int sent, got, want;
  final bool failed;
  bool get complete => !failed && got == want;
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
  bool get cancelled => _cancelled;

  /// Pour l'echange des photos (lot 22), apres la synchro des fiches.
  PhotoSync photos() => PhotoSync(cfg, mobU, sok, _qrc, _k);

  /// Etape 4 : depose LSB + Qrc puis le trousseau de A ([img] : ses photos).
  Future<void> open(VaultData local, {Iterable<String>? img}) async {
    final l = await _Link.open(cfg);
    try {
      final mob = mobU.toLowerCase();
      l.send('4$mobU${g1Seal(_movKey(sok), 'q4|$mob', '$_lsb$_qrc')}');
      _expectOk(await l.next(), sok, 'r4|$mob');
      l.send(sealBlob(local, _k, img: img));
      _expectOk(await l.next(), sok, 'r4|$mob');
    } finally {
      l.close();
    }
  }

  /// Etape 3, relancee toutes les 3 s : le trousseau de S, une fois depose,
  /// et la liste de ses photos.
  Future<(VaultData, Set<String>?)> waitPeer() async {
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
      if (why == null) return openBlobImg(rep, _k);
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
  /// vers A), [img] = ses photos. Renvoie le trousseau de A, que l'appelant
  /// fusionne, la liste des photos de A et l'echange des photos.
  Future<(VaultData, Set<String>?, PhotoSync)> run(String qrRaw, VaultData local,
      {Iterable<String>? img}) async {
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
      final (remote, peerImg) = openBlobImg(blob, k);
      l.send(sealBlob(local, k, img: img));
      _expectOk(await l.next(), sok, 'r5|$mob');
      return (remote, peerImg, PhotoSync(cfg, mobU, sok, qrc, k));
    } finally {
      l.close();
    }
  }
}

// ── Photos : echange apres la synchro des fiches (etapes 6 et 7) ───────────
class PhotoSync {
  PhotoSync(this.cfg, this.mobU, this.sok, this.qrc, this.k);
  final EnvCfg cfg;
  final String mobU, sok, qrc, k;

  /// Depose [plan.send] puis releve [plan.get]. [read] : la photo en clair,
  /// [write] : range une photo recue. Ne leve jamais : rend le bilan.
  Future<PhotoResult> run(
    PhotoPlan plan, {
    required Future<Uint8List?> Function(String id) read,
    required Future<void> Function(String id, Uint8List jpeg) write,
    void Function(int done, int total)? onStep,
    bool Function()? cancelled,
  }) async {
    final total = plan.send.length + plan.get.length;
    var sent = 0, got = 0, step = 0;
    final mob = mobU.toLowerCase();
    void tick() => onStep?.call(++step, total);
    try {
      // Etape 6 : depot (toujours, meme vide : l'autre sait alors que c'est fini).
      final l = await _Link.open(cfg);
      try {
        l.send('6$mobU${g1Seal(_movKey(sok), 'q6|$mob', qrc)}');
        _expectOk(await l.next(), sok, 'r6|$mob');
        for (final id in plan.send) {
          if (cancelled?.call() == true) return PhotoResult(sent, got, plan.get.length, true);
          final jpeg = await read(id);
          if (jpeg != null) {
            for (final f in photoFrames(id, jpeg, k)) {
              l.send(f);
              final r = await l.next();
              if (_refusal(r) != null) throw SyncError(_refusal(r)!);
            }
            sent++;
          }
          tick();
        }
        l.send(jsonEncode({'end': 1}));
        final r = await l.next();
        if (_refusal(r) != null) throw SyncError(_refusal(r)!);
      } finally {
        l.close();
      }
      // Etape 7 : releve, relancee toutes les 2 s, 10 min au plus.
      final join = PhotoJoin(k);
      final want = Set.of(plan.get);
      final end = DateTime.now().add(kSyncWindow);
      while (want.isNotEmpty) {
        if (cancelled?.call() == true || DateTime.now().isAfter(end)) break;
        final l7 = await _Link.open(cfg);
        var n = 0;
        var done = false;
        try {
          l7.send('7$mobU${g1Seal(_movKey(sok), 'q7|$mob', qrc)}');
          final rep = await l7.next();
          final clr = g1Open(_movKey(sok), 'r7|$mob', rep);
          if (clr == null) {
            // echange inconnu : deja clos ou expire, plus rien ne viendra
            if (_refusal(rep) == 'echange') break;
            throw SyncError(_refusal(rep) ?? 'refus');
          }
          final m = jsonDecode(clr);
          n = (m is Map ? m['n'] : null) is int ? m['n'] as int : 0;
          done = m is Map && m['done'] == true;
          for (var i = 0; i < n; i++) {
            final p = join.add(await l7.next());
            if (p != null && want.remove(p.$1)) {
              await write(p.$1, p.$2);
              got++;
              tick();
            }
          }
        } finally {
          l7.close();
        }
        if (done && n == 0) break;
        if (n == 0) await Future<void>.delayed(const Duration(seconds: 2));
      }
      return PhotoResult(sent, got, plan.get.length, false);
    } catch (_) {
      return PhotoResult(sent, got, plan.get.length, true);
    }
  }
}
