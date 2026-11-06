// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER g1.dart · 2026-11-02 · CH4 G1 (enveloppe commune CH3/CH4/CH5)
// Enveloppe G1 : chiffrement AUTHENTIFIE (AES-256-GCM) commun aux canaux
// CH3, CH4 et CH5. Reprise A L'IDENTIQUE du format d'OfL (dpw_g1.dart, lot 3a,
// CH5 et synchro DpW) : memes octets, memes vecteurs.
//
//   Format : "G1" + base64( nonce(12) + AES-256-GCM(clair) + tag(16) )
//   Cle    : HMAC-SHA256(cle de base, etiquette d'usage)  -> 32 octets,
//            quelle que soit la taille de la cle de base (128 ou 256 bits).
//   AAD    : sens + contexte, ex. "ch4q|<kid>" (vers le serveur) et
//            "ch4r|<kid>" (vers le client) : un message ne se rejoue ni dans
//            l'autre sens, ni dans une autre transaction, ni sur un autre canal.
//
// REGLE commune aux canaux : la 1re trame porte en clair un IDENTIFIANT PUBLIC,
// jamais la cle. CH3 = mobs.Pub_Mob_Uk, CH5 = Act. CH4 = empreinte de
// keys.Prv_NaP_uk (ch4Kid), stockee dans keys.Prv_NaP_Kid_uk.
//
// Classe a methodes statiques (pas de fonctions globales) : pas de collision
// avec les copies d'OfL (g1Key, g1Seal...) dans un fichier qui importe les deux.
// Ne depend que de pointycastle (comme le reste de fid_cmp).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class G1 {
  static const String prefix = 'G1';

  // Etiquettes d'usage (derivation de cle). Ne JAMAIS reutiliser une etiquette
  // pour un autre usage.
  static const String lblCh3 = 'qovi-ch3-gcm';
  static const String lblCh4 = 'qovi-ch4-gcm';
  static const String lblCh4Kid = 'qovi-ch4-kid';
  static const String lblCh5 = 'qovi-dpw-ch5-gcm'; // = kG1Ch5 d'OfL
  static const String lblMov = 'qovi-dpw-mov-gcm'; // = kG1Mov d'OfL

  static final Random _rnd = Random.secure();

  /// Hexa (avec ou sans tirets) -> octets. FormatException si invalide.
  static Uint8List hex(String h) {
    final s = h.replaceAll('-', '').toLowerCase();
    if (s.isEmpty || s.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(s)) {
      throw const FormatException('hexa invalide');
    }
    return Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)
    ]);
  }

  static String toHex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// "0011..ff" (32 hexa) -> "00112233-4455-6677-8899-aabbccddeeff".
  static String dash(String h32) {
    final h = h32.replaceAll('-', '').toLowerCase();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20, 32)}';
  }

  /// Vrai si [s] = 32 caracteres hexa exactement (identifiant de 128 bits).
  static bool isHex32(String s) => RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(s);

  static Uint8List _hmac(Uint8List k, String label) {
    final m = HMac(SHA256Digest(), 64)..init(KeyParameter(k));
    return m.process(Uint8List.fromList(utf8.encode(label)));
  }

  /// Cle AES-256 derivee d'une cle de base (hexa) pour un usage.
  static Uint8List key(String baseHex, String label) => _hmac(hex(baseHex), label);

  /// CH4 : identifiant public de la transaction = 16 premiers octets de
  /// HMAC-SHA256(Prv_NaP_u, "qovi-ch4-kid"), en 32 hexa minuscules.
  /// Ne revele rien de la cle ; calcule a l'identique par le client et le serveur.
  static String ch4Kid(String napU) => toHex(_hmac(hex(napU), lblCh4Kid).sublist(0, 16));

  static bool isG1(String s) => s.startsWith(prefix);

  /// Chiffre [plain] ; [nonce] seulement pour les tests (sinon aleatoire).
  static String seal(Uint8List key, String aad, String plain, {Uint8List? nonce}) {
    final n = nonce ?? Uint8List.fromList(List.generate(12, (_) => _rnd.nextInt(256)));
    final c = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, n, Uint8List.fromList(utf8.encode(aad))));
    final ct = c.process(Uint8List.fromList(utf8.encode(plain)));
    return prefix + base64.encode([...n, ...ct]);
  }

  /// Dechiffre et VERIFIE ; null si format, cle, contexte ou contenu faux.
  static String? open(Uint8List key, String aad, String env) {
    if (!isG1(env)) return null;
    try {
      final raw = base64.decode(env.substring(prefix.length));
      if (raw.length < 12 + 16) return null;
      final c = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128,
            Uint8List.fromList(raw.sublist(0, 12)), Uint8List.fromList(utf8.encode(aad))));
      return utf8.decode(c.process(Uint8List.fromList(raw.sublist(12))));
    } catch (_) {
      return null;
    }
  }
}
