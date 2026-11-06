// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER wl_probe.dart · 2026-11-01 · diagnostic import WL
// Diagnostic de l'ancien trousseau WL (_DpW.aes), SANS l'app : essaie la cle
// sous plusieurs formes (WL peut transformer Key_Uk avant DecrypteStandard)
// et dit, pour chacune, ou ca casse : padding AES, controle CRC32/Murmur3,
// encodage du texte. N'affiche AUCUN contenu du trousseau ni la cle.
// Usage : dart run tool/wl_probe.dart /tmp/dpw_wl.aes
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

Uint8List _hex(String h) =>
    Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

Uint8List _guidSwap(Uint8List k) {
  final o = Uint8List.fromList(k);
  for (var b = 0; b < k.length; b += 16) {
    for (final (s, n) in [(0, 4), (4, 2), (6, 2)]) {
      for (var i = 0; i < n; i++) {
        o[b + s + i] = k[b + s + n - 1 - i];
      }
    }
  }
  return o;
}

String _crc32(List<int> d) {
  var c = 0xffffffff;
  for (final b in d) {
    c ^= b;
    for (var j = 0; j < 8; j++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xedb88320 : c >> 1;
    }
  }
  return ((c ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
}

int _mm3(List<int> d) {
  const c1 = 0xcc9e2d51, c2 = 0x1b873593, m = 0xffffffff;
  int rl(int x, int r) => ((x << r) | (x >> (32 - r))) & m;
  int mu(int a, int b) => (a * b) & m;
  var h = 0;
  final n = d.length ~/ 4;
  for (var i = 0; i < n; i++) {
    var k = d[4 * i] | (d[4 * i + 1] << 8) | (d[4 * i + 2] << 16) | (d[4 * i + 3] << 24);
    h ^= mu(rl(mu(k, c1), 15), c2);
    h = (mu(rl(h, 13), 5) + 0xe6546b64) & m;
  }
  var k = 0;
  for (var j = d.length - 1; j >= 4 * n; j--) {
    k = (k << 8) | d[j];
  }
  if (d.length > 4 * n) h ^= mu(rl(mu(k, c1), 15), c2);
  h ^= d.length;
  h ^= h >> 16;
  h = mu(h, 0x85ebca6b);
  h ^= h >> 13;
  h = mu(h, 0xc2b2ae35);
  return h ^ (h >> 16);
}

String _h32(int v, bool be) {
  final b = [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
  return (be ? b : b.reversed).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

void _try(String name, Uint8List key, Uint8List iv, Uint8List ct) {
  stdout.write('- ${name.padRight(28)} : ');
  Uint8List got;
  try {
    final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(false, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null));
    got = c.process(ct);
  } catch (_) {
    stdout.writeln('padding invalide (cle fausse sous cette forme)');
    return;
  }
  if (got.length < 8) {
    stdout.writeln('padding OK mais trop court');
    return;
  }
  final chk = got.sublist(0, 8);
  final printable = chk.every((b) => b >= 0x20 && b < 0x7f);
  final chkS = printable ? ascii.decode(chk).toLowerCase() : '(non imprimable)';
  final dec = got.sublist(8);
  final mm = _mm3(dec);
  final crc = chkS == _crc32(dec);
  final mur = chkS == _h32(mm, true) || chkS == _h32(mm, false);
  var utf = true;
  try {
    utf8.decode(dec);
  } catch (_) {
    utf = false;
  }
  final hi = dec.where((b) => b >= 0x80).length;
  stdout.writeln('PADDING OK ; controle ${crc ? "CRC32 OK" : mur ? "MURMUR3 OK" : "FAUX (8 premiers : $chkS)"} ; '
      '${dec.length} octets, ${utf ? "UTF-8 valide" : "PAS UTF-8"}, $hi octets >= 0x80, '
      'commence par ${dec.isNotEmpty && dec[0] == 0x7b ? "{" : "autre chose"}');
}

void main(List<String> a) {
  final f = File(a.isEmpty ? '/tmp/dpw_wl.aes' : a.first);
  final raw = base64.decode(f.readAsStringSync().replaceAll(RegExp(r'\s'), ''));
  stdout.writeln('Fichier : ${raw.length} octets apres base64 ; '
      '${raw.length % 16 == 0 ? "multiple de 16 : OK pour IV + CBC" : "PAS multiple de 16"}');
  stdout.write('Ancienne cle (64 hexa ; la saisie ne s affiche pas) : ');
  stdin.echoMode = false;
  final k = (stdin.readLineSync() ?? '').replaceAll(RegExp(r'[\s-]'), '');
  stdin.echoMode = true;
  stdout.writeln();
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(k)) {
    stdout.writeln('Cle : ${k.length} caracteres apres retrait des espaces et tirets, pas 64 hexa : arret.');
    return;
  }
  final kb = _hex(k.toLowerCase());
  final iv = Uint8List.fromList(raw.sublist(0, 16));
  final ct = Uint8List.fromList(raw.sublist(16));
  final v = <String, Uint8List>{
    'telle quelle': kb,
    'GUID (ordre Windows)': _guidSwap(kb),
    'octets inverses': Uint8List.fromList(kb.reversed.toList()),
    'SHA-256 du texte minuscule': Uint8List.fromList(sha256.convert(ascii.encode(k.toLowerCase())).bytes),
    'SHA-256 du texte MAJUSCULE': Uint8List.fromList(sha256.convert(ascii.encode(k.toUpperCase())).bytes),
    '32 premiers car. du texte': Uint8List.fromList(ascii.encode(k.toLowerCase()).sublist(0, 32)),
  };
  stdout.writeln('Avec IV en tete du fichier :');
  v.forEach((n, key) => _try(n, key, iv, ct));
  stdout.writeln('Sans IV (IV nul, tout le fichier chiffre) :');
  _try('telle quelle', kb, Uint8List(16), Uint8List.fromList(raw));
  _try('GUID (ordre Windows)', _guidSwap(kb), Uint8List(16), Uint8List.fromList(raw));
}
