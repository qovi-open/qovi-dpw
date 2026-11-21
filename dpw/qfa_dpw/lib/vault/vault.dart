// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER vault.dart · 2026-11-10 · lot 17 (filtres chiffres ; dates de creation)
// Le trousseau sur disque, dans le dossier choisi par l'usager (Dropbox...).
//
//   _DpW_v2.aes  format v2 : "DPW2" + nonce(12) + AES-256-GCM(JSON) + tag(16)
//                cle = HMAC-SHA256(SoK.U, "qovi-dpw-vault-v2") ; "DPW2" en AAD.
//                GCM est authentifie : un fichier modifie ou une mauvaise cle
//                est REFUSE (le format WL, CBC + CRC32, ne le detectait pas).
//                Contenu JSON v3 (lot 2) : {"v":3,"cod":[...],"del":[{id,t}]}
//                (traces de suppression pour la synchro) ; un contenu v2 (sans
//                "del") se lit tel quel et sera reecrit en v3.
//   _DpW.aes     ancien format WL (Uid256 = CBC + CRC32), LU seulement, JAMAIS
//                modifie. S'il est seul et lisible avec la cle du compte, il est
//                converti en v2. Sinon il s'importe avec son ANCIENNE cle
//                (importWl), saisie une fois et jamais conservee. Apres un
//                import reussi, l'ancien fichier et TOUTES ses copies WL
//                (_DpW+.aes, _DpW++.aes...) sont supprimes : leur cle figure
//                dans le code WL du depot, ils ne doivent plus exister.
//
// Regles :
//  - un fichier illisible n'est JAMAIS ecrase (on s'arrete avec une erreur) ;
//  - ecriture atomique (fichier .tmp puis renommage) ;
//  - 3 sauvegardes au plus : _DpW_v2.aes.bak1 (la plus recente) a .bak3 ;
//  - avant chaque ecriture, le fichier est relu s'il a change sur disque
//    (autre poste) et la modification est appliquee par identifiant d'entree.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fid_cmp/fid_cmp.dart' show Uid256Crypto;
import 'package:pointycastle/export.dart';

import '../core/rand.dart';
import '../sync/merge.dart';
import '../txt.dart';
import 'entry.dart';

const String kVaultV2 = '_DpW_v2.aes';
const String kVaultWl = '_DpW.aes';
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

/// Ancien trousseau WL : texte base64 Uid256(JSON {"Cod":[...]}, SoK.U).
List<Entry> decodeWl(String text, String sokU) {
  final clr = wlDecrypt(text, sokU);
  if (clr == null) {
    throw VaultError(T.oldWrongKey);
  }
  final m = jsonDecode(clr);
  final cod = m is Map ? m['Cod'] : null;
  final items = cod is List ? cod : (cod is Map ? cod.values.toList() : const []);
  return [for (final e in items) if (e is Map) Entry.fromWl(e)];
}

/// Dechiffrement FIDELE de UID256_Decode_b (WL) pour l'ancien trousseau
/// (lot 2j, echec d'import du vrai trousseau de Marc le 01.11). Deux ecarts
/// avec Uid256Crypto.decode (fid_cmp, non modifie : partage par d'autres) :
///  1. WL travaille en « ANSI chaine » : le clair n'est pas forcement de
///     l'UTF-8 (accents, apostrophes typographiques en Windows-1252). Le
///     controle porte donc sur les OCTETS, puis le texte est lu en UTF-8,
///     sinon en Windows-1252.
///  2. Si le CRC32 ne correspond pas, WL accepte un hachage Murmur3 32 bits
///     en hexa (BufferVersHexa(HashChaine(HA_MURMUR_3_32, Dec_s))).
/// Format : base64( IV(16) + AES-256-CBC/PKCS7( chk(8) + clair ) ).
String? wlDecrypt(String b64, String keyHex) {
  try {
    final key = hexToBytes(keyHex.replaceAll('-', ''));
    if (key.length != 32) return null;
    final raw = base64.decode(b64.replaceAll(RegExp(r'\s'), ''));
    if (raw.length < 32) return null;
    final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(false,
          PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), raw.sublist(0, 16)), null));
    final got = c.process(Uint8List.fromList(raw.sublist(16)));
    if (got.length < 8) return null;
    final chk = String.fromCharCodes(got.sublist(0, 8)).toLowerCase();
    final dec = got.sublist(8);
    final mm = wlMurmur3(dec);
    final ok = chk == Uid256Crypto.crc32Hex(dec) ||
        chk == _hex32(mm, bigEndian: true) ||
        chk == _hex32(mm, bigEndian: false);
    String txt;
    try {
      txt = utf8.decode(dec);
    } on FormatException {
      txt = cp1252Decode(dec);
    }
    if (ok) return txt;
    // Diagnostic du 01.11 sur le vrai trousseau de Marc : la cle ouvre le
    // fichier (padding AES correct, clair JSON) mais les 8 premiers octets ne
    // sont ni le CRC32 ni le Murmur3 du clair. Tant que la procedure WL qui
    // ecrit ce controle n'est pas connue, on accepte un clair qui est un JSON
    // de trousseau ({"Cod":...}) : avec une mauvaise cle, le padding passe
    // rarement (1 fois sur 256 environ) et le JSON jamais.
    try {
      final m = jsonDecode(txt);
      if (m is Map && m.containsKey('Cod')) return txt;
    } catch (_) {}
    return null;
  } catch (_) {
    return null;
  }
}

String _hex32(int v, {required bool bigEndian}) {
  final b = [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
  final o = bigEndian ? b : b.reversed;
  return o.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

/// MurmurHash3 x86 32 bits, graine 0 (HA_MURMUR_3_32 de WL).
int wlMurmur3(List<int> d) {
  const c1 = 0xcc9e2d51, c2 = 0x1b873593, m32 = 0xffffffff;
  int rotl(int x, int r) => ((x << r) | (x >> (32 - r))) & m32;
  int mul(int a, int b) => (a * b) & m32;
  var h = 0;
  final n = d.length ~/ 4;
  for (var i = 0; i < n; i++) {
    var k = d[4 * i] | (d[4 * i + 1] << 8) | (d[4 * i + 2] << 16) | (d[4 * i + 3] << 24);
    k = mul(rotl(mul(k, c1), 15), c2);
    h ^= k;
    h = (mul(rotl(h, 13), 5) + 0xe6546b64) & m32;
  }
  var k = 0;
  for (var j = d.length - 1; j >= 4 * n; j--) {
    k = (k << 8) | d[j];
  }
  if (d.length > 4 * n) {
    k = mul(rotl(mul(k, c1), 15), c2);
    h ^= k;
  }
  h ^= d.length;
  h ^= h >> 16;
  h = mul(h, 0x85ebca6b);
  h ^= h >> 13;
  h = mul(h, 0xc2b2ae35);
  h ^= h >> 16;
  return h;
}

/// Windows-1252 (« ANSI » de WL) vers texte.
String cp1252Decode(List<int> b) {
  const hi = [
    0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
    0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
  ];
  return String.fromCharCodes(b.map((x) => x >= 0x80 && x < 0xA0 ? hi[x - 0x80] : x));
}

class Vault {
  Vault(this.dir, String sokU)
      : _key = vaultKey(sokU),
        _sokU = sokU;

  final String dir;
  final Uint8List _key;
  final String _sokU; // en memoire seulement, utile a la seule lecture WL
  List<Entry> entries = [];
  List<Tomb> tombs = [];

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

  /// true si le trousseau vient d'etre converti depuis l'ancien format WL.
  bool convertedFromWl = false;

  File get file => File('$dir${Platform.pathSeparator}$kVaultV2');
  File get _wlFile => File('$dir${Platform.pathSeparator}$kVaultWl');

  Future<void> open() async {
    if (await file.exists()) {
      final b = await file.readAsBytes();
      _take(decodeVault(b, _key));
      _lastHash = _hash(b);
      if (_fillCre()) await _write();
      return;
    }
    entries = [];
    if (await _wlFile.exists()) {
      try {
        entries = decodeWl(await _wlFile.readAsString(), _sokU);
        convertedFromWl = true;
        _fillCre();
      } on VaultError {
        // Ancien trousseau chiffre avec une autre cle : on ouvre un trousseau
        // v2 vide, l'ancien s'importera avec son ancienne cle (importWl).
      }
    }
    await _write();
  }

  /// true si un ancien trousseau WL (_DpW.aes) est present dans le dossier.
  bool get hasWl => _wlFile.existsSync();

  /// Importe l'ancien trousseau WL avec son ANCIENNE cle (64 hexa, tirets
  /// et espaces toleres). La cle n'est ni conservee ni journalisee. Les
  /// entrees deja presentes a l'identique ne sont pas dupliquees.
  /// Une fois le trousseau v2 ecrit, l'ancien fichier et toutes ses copies
  /// WL sont supprimes. Renvoie (entrees ajoutees, fichiers supprimes).
  Future<(int, int)> importWl(String oldKey) async {
    final k = oldKey.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(k)) {
      throw VaultError(T.oldKey64);
    }
    if (!await _wlFile.exists()) {
      throw VaultError(T.noOld(kVaultWl));
    }
    final List<Entry> old;
    try {
      old = decodeWl(await _wlFile.readAsString(), k);
    } on VaultError {
      throw VaultError(T.oldKeyBad);
    }
    var added = 0;
    await _mutate((l) {
      for (final e in old) {
        final dup = l.any((x) =>
            x.nam == e.nam && x.url == e.url && x.who == e.who && x.pass == e.pass);
        if (!dup) {
          l.add(e);
          added++;
        }
      }
    });
    // Le v2 est ecrit (sinon _mutate a leve une erreur) : l'ancien peut partir.
    return (added, await _deleteWlFiles());
  }

  /// Ancien trousseau WL et ses copies : _DpW.aes, _DpW+.aes, _DpW++.aes...
  static final RegExp _wlName = RegExp(r'^_DpW\+*\.aes$');

  Future<int> _deleteWlFiles() async {
    var n = 0;
    await for (final f in Directory(dir).list(followLinks: false)) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (_wlName.hasMatch(name)) {
        await f.delete();
        n++;
      }
    }
    return n;
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

  Future<void> upsert(Entry e) => _mutate((l) {
        final i = l.indexWhere((x) => x.id == e.id);
        if (i < 0) {
          l.add(e.copy());
        } else {
          l[i] = e.copy();
        }
      });

  /// Supprime et garde une trace datee, pour que la synchro propage la suppression.
  Future<void> delete(String id) => _mutate((l) {
        l.removeWhere((x) => x.id == id);
        tombs.removeWhere((t) => t.id == id);
        tombs.add(Tomb(id, DateTime.now().toUtc()));
      });

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
