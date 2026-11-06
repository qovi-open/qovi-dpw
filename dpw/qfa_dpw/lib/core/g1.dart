// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER g1.dart · 2026-11-02 · lot 3a (CH5 et synchro en AES-GCM)
// Enveloppe G1 : chiffrement AUTHENTIFIE des canaux DpW (CH5 et synchro),
// en remplacement d'Uid256 (AES-CBC + CRC32, qui chiffre sans authentifier).
// Format : "G1" + base64( nonce(12) + AES-256-GCM(clair) + tag(16) ).
//  - cle derivee par usage : HMAC-SHA256(cle de base, etiquette) ;
//  - donnees associees (aad) : le sens et le contexte (ex. "ch5q|<act>"),
//    pour qu'un message ne soit pas rejoue dans un autre sens ou une autre
//    transaction.
// Fichier IDENTIQUE cote client (dpw/qfa_dpw/lib/core/g1.dart) et cote
// service (ser/.../lib/src/dpw_g1.dart) : toute modification se fait des deux.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

const String kG1 = 'G1';
const String kG1Ch5 = 'qovi-dpw-ch5-gcm';
const String kG1Mov = 'qovi-dpw-mov-gcm';

final Random _rnd = Random.secure();

Uint8List _g1Hex(String h) {
  final s = h.replaceAll('-', '').toLowerCase();
  if (s.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(s)) {
    throw const FormatException('hexa invalide');
  }
  return Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}

/// Cle AES-256 derivee d'une cle de base (hexa) pour un usage donne.
Uint8List g1Key(String baseHex, String label) =>
    Uint8List.fromList(Hmac(sha256, _g1Hex(baseHex)).convert(utf8.encode(label)).bytes);

/// Le message est-il au format G1 ?
bool isG1(String s) => s.startsWith(kG1);

/// Chiffre [plain] ; [nonce] seulement pour les tests (sinon aleatoire).
String g1Seal(Uint8List key, String aad, String plain, {Uint8List? nonce}) {
  final n = nonce ?? Uint8List.fromList(List.generate(12, (_) => _rnd.nextInt(256)));
  final c = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, n, Uint8List.fromList(utf8.encode(aad))));
  final ct = c.process(Uint8List.fromList(utf8.encode(plain)));
  return kG1 + base64.encode([...n, ...ct]);
}

/// Dechiffre et VERIFIE ; null si format, cle, contexte ou contenu faux.
String? g1Open(Uint8List key, String aad, String env) {
  if (!isG1(env)) return null;
  try {
    final raw = base64.decode(env.substring(kG1.length));
    if (raw.length < 12 + 16) return null;
    final c = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(key), 128, Uint8List.fromList(raw.sublist(0, 12)), Uint8List.fromList(utf8.encode(aad))));
    return utf8.decode(c.process(Uint8List.fromList(raw.sublist(12))));
  } catch (_) {
    return null;
  }
}
