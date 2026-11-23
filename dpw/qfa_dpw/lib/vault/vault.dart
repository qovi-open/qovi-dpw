// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER vault.dart · 2026-11-20 · lot 27 (ancien format WL retire ; lot 20 : W14 photos de carte)
// Le trousseau sur disque, dans le dossier choisi par l'usager (Dropbox...).
//
//   _DpW_v2.aes  format v2 : "DPW2" + nonce(12) + AES-256-GCM(JSON) + tag(16)
//                cle = HMAC-SHA256(SoK.U, "qovi-dpw-vault-v2") ; "DPW2" en AAD.
//                GCM est authentifie : un fichier modifie ou une mauvaise cle
//                est REFUSE (le format WL, CBC + CRC32, ne le detectait pas).
//                Contenu JSON v3 (lot 2) : {"v":3,"cod":[...],"del":[{id,t}]}
//                (traces de suppression pour la synchro) ; un contenu v2 (sans
//                "del") se lit tel quel et sera reecrit en v3.
//   _DpW.aes     ancien format WL : plus lu depuis le lot 27 (decision de Marc
//                20.11, plus personne n'en a). Un tel fichier est ignore, ni
//                lu ni efface.
//
// Regles :
//  - un fichier illisible n'est JAMAIS ecrase (on s'arrete avec une erreur) ;
//  - ecriture atomique (fichier .tmp puis renommage) ;
//  - 3 sauvegardes au plus : _DpW_v2.aes.bak1 (la plus recente) a .bak3 ;
//  - avant chaque ecriture, le fichier est relu s'il a change sur disque
//    (autre poste) et la modification est appliquee par identifiant d'entree ;
//  - W14 (lot 20) : les photos de carte sont dans _DpW_img/ (card_store.dart).
//    Un fichier photo n'est supprime que par une action LOCALE (photo
//    remplacee ou retiree a l'enregistrement, fiche supprimee) et seulement
//    si plus AUCUNE fiche n'y fait reference ; jamais par la synchro.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../core/rand.dart';
import '../sync/merge.dart';
import '../txt.dart';
import 'card_store.dart';
import 'entry.dart';

const String kVaultV2 = '_DpW_v2.aes';
const int kBackups = 3;
const List<int> _magic = [0x44, 0x50, 0x57, 0x32]; // "DPW2"

class VaultError implements Exception {
  VaultError(this.msg);
  final String msg;
  @override
  String toString() => msg;
}

Uint8List vaultKey(String sokU) => Uint8List.fromList(
    Hmac(sha256, hexToBytes(sokU)).convert(utf8.encode('qovi-dpw-vault-v2')).bytes);

Uint8List encodeV2(List<Entry> list, Uint8List key) => encodeVault(VaultData(list), key);

Uint8List encodeVault(VaultData d, Uint8List key) {
  final nonce = randBytes(12);
  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List.fromList(_magic)));
  final clr = utf8.encode(jsonEncode(d.toJson()));
  final ct = gcm.process(Uint8List.fromList(clr));
  return Uint8List.fromList([..._magic, ...nonce, ...ct]);
}

List<Entry> decodeV2(Uint8List b, Uint8List key) => decodeVault(b, key).cod;

VaultData decodeVault(Uint8List b, Uint8List key) {
  if (b.length < 4 + 12 + 16 ||
      b[0] != _magic[0] || b[1] != _magic[1] || b[2] != _magic[2] || b[3] != _magic[3]) {
    throw VaultError(T.notV2);
  }
  final Uint8List clr;
  try {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(key), 128, b.sublist(4, 16), Uint8List.fromList(_magic)));
    clr = gcm.process(b.sublist(16));
  } catch (_) {
    throw VaultError(T.wrongKey);
  }
  final d = VaultData.fromJson(jsonDecode(utf8.decode(clr)));
  if (d == null) throw VaultError(T.badContent);
  return d;
}

class Vault {
  Vault(this.dir, String sokU)
      : _key = vaultKey(sokU),
        cards = CardStore(dir, sokU);

  final String dir;
  final Uint8List _key;
  List<Entry> entries = [];
  List<Tomb> tombs = [];

  /// W14 (lot 20) : photos de carte chiffrees, a cote du trousseau.
  final CardStore cards;

  /// Filtres enregistres (lot 17, W2) : chiffres avec le trousseau.
  List<Flt> filters = [];
  List<Tomb> ftombs = [];
  String? _lastHash;

  /// Le trousseau complet (entrees, filtres, traces), pour la synchro.
  VaultData get data => VaultData([for (final e in entries) e.copy()], List.of(tombs),
      [for (final f in filters) f.copy()], List.of(ftombs));

  void _take(VaultData d) {
    entries = d.cod;
    tombs = d.del;
    filters = d.flt;
    ftombs = d.fdel;
  }

  /// W7 (lot 17, regle de Marc) : une entree sans date de creation recoit
  /// « aujourd'hui moins 5 jours », UNE fois (puis c'est enregistre).
  bool _fillCre() {
    var n = false;
    final d = DateTime.now().toUtc().subtract(const Duration(days: 5));
    for (final e in entries) {
      if (e.cre == null) {
        e.cre = d;
        n = true;
      }
    }
    return n;
  }

  File get file => File('$dir${Platform.pathSeparator}$kVaultV2');

  Future<void> open() async {
    if (await file.exists()) {
      final b = await file.readAsBytes();
      _take(decodeVault(b, _key));
      _lastHash = _hash(b);
      if (_fillCre()) await _write();
      return;
    }
    entries = [];
    await _write();
  }

  /// Relit le fichier s'il a change sur disque. true si la liste a change.
  Future<bool> reloadIfChanged() async {
    if (!await file.exists()) return false;
    final b = await file.readAsBytes();
    final h = _hash(b);
    if (h == _lastHash) return false;
    _take(decodeVault(b, _key));
    _lastHash = h;
    return true;
  }

  Future<void> upsert(Entry e) async {
    final before = <String>[];
    await _mutate((l) {
      final i = l.indexWhere((x) => x.id == e.id);
      if (i < 0) {
        l.add(e.copy());
      } else {
        before.addAll(l[i].crd);
        l[i] = e.copy();
      }
    });
    // W14 : photos remplacees ou retirees de CETTE fiche, sur cet appareil.
    await dropIfOrphan(before.where((x) => !e.crd.contains(x)));
  }

  /// Supprime et garde une trace datee, pour que la synchro propage la suppression.
  Future<void> delete(String id) async {
    final gone = <String>[];
    await _mutate((l) {
      for (final x in l) {
        if (x.id == id) gone.addAll(x.crd);
      }
      l.removeWhere((x) => x.id == id);
      tombs.removeWhere((t) => t.id == id);
      tombs.add(Tomb(id, DateTime.now().toUtc()));
    });
    await dropIfOrphan(gone); // W14 : la fiche est supprimee ICI
  }

  /// W14 (lot 20) : supprime les fichiers photo que plus aucune fiche ne
  /// reference (une copie de conflit peut partager les photos de l'originale).
  /// Appele SEULEMENT apres une action locale, jamais apres une synchro.
  Future<void> dropIfOrphan(Iterable<String> ids) async {
    final used = {for (final e in entries) ...e.crd};
    for (final id in ids.toSet()) {
      if (!used.contains(id)) await cards.drop(id);
    }
  }

  /// Fusionne le trousseau recu d'un autre appareil et l'enregistre.
  Future<MergeStats> applyRemote(VaultData remote) async {
    await reloadIfChanged();
    final r = mergeVaults(data, remote);
    _take(r.data);
    _fillCre();
    await _write();
    return r.stats;
  }

  Future<void> touch(String id) => _mutate((l) {
        for (final x in l) {
          if (x.id == id) x.use = DateTime.now().toUtc();
        }
      });

  // ── Filtres enregistres (lot 17, W2) ───────────────────────────────────
  /// Cree ou remplace un filtre.
  Future<void> putFilter(Flt f) async {
    await reloadIfChanged();
    filters.removeWhere((x) => x.id == f.id);
    filters.add(f.copy());
    await _write();
  }

  /// Detruit un filtre et garde une trace datee (synchro).
  Future<void> dropFilter(String id) async {
    await reloadIfChanged();
    filters.removeWhere((x) => x.id == id);
    ftombs.removeWhere((t) => t.id == id);
    ftombs.add(Tomb(id, DateTime.now().toUtc()));
    await _write();
  }

  Future<void> _mutate(void Function(List<Entry>) change) async {
    await reloadIfChanged();
    change(entries);
    await _write();
  }

  Future<void> _write() async {
    final bytes = encodeVault(VaultData(entries, tombs, filters, ftombs), _key);
    await Directory(dir).create(recursive: true);
    if (await file.exists()) await _rotate();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    _lastHash = _hash(bytes);
  }

  Future<void> _rotate() async {
    for (var i = kBackups; i >= 1; i--) {
      final src = i == 1 ? file : File('${file.path}.bak${i - 1}');
      if (await src.exists()) await src.copy('${file.path}.bak$i');
    }
  }

  static String _hash(List<int> b) => sha256.convert(b).toString();
}
