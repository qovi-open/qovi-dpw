// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER card_store.dart · 2026-11-19 · lot 22 (W14 etape 2 : putAs, photo recue par la synchro)
// Les photos de carte (W14, decisions de Marc 19.11). Une photo = un fichier
// dans le dossier du trousseau :
//
//   _DpW_img/<id>.aes   "DPWI" + nonce(12) + AES-256-GCM(JPEG) + tag(16)
//                       cle = HMAC-SHA256(SoK.U, "qovi-dpw-img-v1") (separee de
//                       celle du trousseau) ; AAD = "DPWI" + id : un fichier
//                       renomme ou echange est REFUSE.
//
// Regles :
//  - l'identifiant (32 hexa, kCardId) est VERIFIE avant de construire un
//    chemin : une reference recue par la synchro ne peut pas sortir du dossier ;
//  - ecriture atomique (.tmp puis renommage) ;
//  - etape 2 (lot 22) : une photo recue par la synchro est rangee sous SON
//    identifiant (putAs), rechiffree avec la cle photo de CET appareil ;
//  - un fichier n'est supprime que par une action LOCALE (photo remplacee ou
//    retiree, fiche supprimee), jamais a la suite d'une synchro (Vault).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../core/rand.dart';
import 'entry.dart';

const String kCardDir = '_DpW_img';
const List<int> _magic = [0x44, 0x50, 0x57, 0x49]; // "DPWI"

Uint8List cardKey(String sokU) => Uint8List.fromList(
    Hmac(sha256, hexToBytes(sokU)).convert(utf8.encode('qovi-dpw-img-v1')).bytes);

Uint8List _aad(String id) => Uint8List.fromList([..._magic, ...utf8.encode(id)]);

/// Chiffre une photo pour l'identifiant [id] (fonction pure, testee).
Uint8List sealCard(Uint8List jpeg, String id, Uint8List key) {
  final nonce = randBytes(12);
  final gcm = GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(key), 128, nonce, _aad(id)));
  return Uint8List.fromList([..._magic, ...nonce, ...gcm.process(jpeg)]);
}

/// Dechiffre ; null si le fichier n'est pas une photo DpW, a ete modifie,
/// echange avec un autre identifiant, ou si la cle est fausse.
Uint8List? openCard(Uint8List b, String id, Uint8List key) {
  if (b.length < 4 + 12 + 16) return null;
  for (var i = 0; i < 4; i++) {
    if (b[i] != _magic[i]) return null;
  }
  try {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, b.sublist(4, 16), _aad(id)));
    return gcm.process(b.sublist(16));
  } catch (_) {
    return null;
  }
}

class CardStore {
  CardStore(String vaultDir, String sokU)
      : dir = '$vaultDir${Platform.pathSeparator}$kCardDir',
        _key = cardKey(sokU);

  final String dir;
  final Uint8List _key;

  File _file(String id) {
    if (!kCardId.hasMatch(id)) throw ArgumentError('identifiant de photo invalide');
    return File('$dir${Platform.pathSeparator}$id.aes');
  }

  /// true si le fichier de cette photo est present sur cet appareil.
  bool has(String id) => kCardId.hasMatch(id) && _file(id).existsSync();

  /// Enregistre une photo (JPEG) et renvoie son nouvel identifiant.
  Future<String> put(Uint8List jpeg) async {
    final id = randHex(16);
    final f = _file(id);
    await Directory(dir).create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(sealCard(jpeg, id, _key), flush: true);
    await tmp.rename(f.path);
    return id;
  }

  /// Range une photo recue par la synchro sous son identifiant (lot 22).
  /// Ne remplace jamais un fichier deja present.
  Future<void> putAs(String id, Uint8List jpeg) async {
    final f = _file(id);
    if (await f.exists()) return;
    await Directory(dir).create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(sealCard(jpeg, id, _key), flush: true);
    await tmp.rename(f.path);
  }

  /// La photo en clair, ou null si absente de cet appareil ou illisible.
  Future<Uint8List?> get(String id) async {
    if (!kCardId.hasMatch(id)) return null;
    final f = _file(id);
    if (!await f.exists()) return null;
    return openCard(await f.readAsBytes(), id, _key);
  }

  /// Supprime le fichier (sans erreur s'il n'existe pas).
  Future<void> drop(String id) async {
    if (!kCardId.hasMatch(id)) return;
    final f = _file(id);
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // un fichier qui reste n'est pas grave : il est chiffre
    }
  }
}
