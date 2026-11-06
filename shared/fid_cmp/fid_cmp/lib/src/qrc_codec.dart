// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// qrc_codec.dart — Portage de QRcode_Gen_s64() (WL, Fid_QRC.txt) et
// _QRs_b() (WL, _Ch3.txt). Encode/décode le blob "Qrc.x64" transmis dans
// les messages CH2/CH3 — contient le niveau d'identification exigé côté
// mobile (Qrc_i), le type de traitement (Qrc_k) et la référence de
// transaction (Qrc_us = keys.Prv_Fid_uk). Chiffré avec whos.Prv_UsR_Uk (clé
// privée de l'UTILISATEUR, pas du mobile — n'importe quel mobile appairé
// au même Who peut donc décoder, c'est le but : Key_ts contient une entrée
// par email appairé, pas par mobile).
//
// Partagé entre ser (encode) et mob (decode) pour que les deux bouts du
// protocole restent obligatoirement synchronisés (un seul endroit à faire
// évoluer si le format du blob change).
//
// DIVERGENCE (simplification actée avec Marc, 13.07.2026) : WL encode
// historiquement `keys.UsR_Ident_i3` (choix de l'utilisateur, si le site
// le permettait via SiT_Ident_4b). Cette liberté utilisateur disparaît —
// seul `keys.SiT_Ident_i3` (imposé par le site) compte désormais. Ce
// module encode directement l'entier `identI3` fourni par l'appelant,
// sans savoir d'où il vient côté DB.
//
// DIVERGENCE (scope du jour, 13.07.2026) : la vérification anti-rejeu de
// `Prv_Fid_uk` côté serveur au moment du vote (keys.Prv_Fid_uk + expiration
// Prv_Act_tk, voir s_Clic_Up_x.txt) n'est PAS encore portée — seule la
// génération/transmission l'est. Le champ est bien regénéré à chaque
// demande (rotation), mais rien ne vérifie encore qu'il n'est pas rejoué.
// Prochaine session dédiée à cette protection.

import 'uid256_crypto.dart';

class QrcDecoded {
  final int identI3; // 1=Bouton, 2=PIN, 3=Bio (voir mob_ident_cst.dart, qfa_mob)
  final int keyI3; // k_Login_ic / k_Pairing_ic / k_Alone_ic (fid_cst_pub.dart)
  final String prvFidUk; // keys.Prv_Fid_uk — 32 car. hex, sans tirets
  const QrcDecoded(this.identI3, this.keyI3, this.prvFidUk);
}

/// Équivalent QRcode_Gen_s64() — encode côté serveur.
/// [prvFidUk] : keys.Prv_Fid_uk, avec ou sans tirets (retirés ici, comme le
/// `Replace(keys.Prv_Fid_uk,"-","")` WL).
String qrcEncode({
  required int identI3,
  required int keyI3,
  required String prvFidUk,
  required String prvUsRUk,
}) {
  final qrS = String.fromCharCode(identI3 + 32) +
      String.fromCharCode(keyI3 + 32) +
      prvFidUk.replaceAll('-', '');
  return Uid256Crypto.encode(qrS, prvUsRUk);
}

/// Équivalent _QRs_b() — décode côté mobile, en essayant chaque clé de
/// Key_ts jusqu'à ce qu'une fonctionne (une par email appairé sur ce
/// mobile). Retourne (résultat, clé qui a marché) — la clé est à remonter
/// en tête de trousseau par l'appelant via `MobKeyring.markUsed()`, comme
/// le fait _QRs_b ("dernière clé utilisée toujours en tête de liste").
///
/// Retourne null si aucune clé ne décode. Pas de distinction d'erreur —
/// voir Marc, 13.07.2026 : "si un MoB ne peut pas décoder il n'a pas
/// besoin de savoir".
(QrcDecoded, String)? qrcDecode(String qrcX64, List<String> keyTs) {
  for (final k in keyTs) {
    final dec = Uid256Crypto.decode(qrcX64, k);
    if (dec != null && dec.length >= 34) {
      final identI3 = dec.codeUnitAt(0) - 32;
      final keyI3 = dec.codeUnitAt(1) - 32;
      final prvFidUk = dec.substring(2, 34);
      return (QrcDecoded(identI3, keyI3, prvFidUk), k);
    }
  }
  return null;
}
