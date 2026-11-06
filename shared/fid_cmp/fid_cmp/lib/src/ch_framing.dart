// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// ch_framing.dart — Framing partagé CH3/CH4/CH5 : 4 octets big-endian
// (longueur) + payload (Divergence 11, RoadLog 09.07.2026). Jusqu'ici
// dupliqué en dur dans t_ch4_x.dart et test_ch4_client.dart — centralisé ici
// pour que le futur client CH3/CH4 mobile (mob/qfa_mob) n'ait pas à le
// réécrire une 3e fois.

import 'dart:typed_data';

class ChFraming {
  /// Encode un payload (bytes UTF-8 déjà encodés) en trame préfixée-longueur.
  static Uint8List frame(List<int> payloadBytes) {
    final header = ByteData(4)..setUint32(0, payloadBytes.length, Endian.big);
    final out = Uint8List(4 + payloadBytes.length)
      ..setRange(0, 4, header.buffer.asUint8List())
      ..setRange(4, 4 + payloadBytes.length, payloadBytes);
    return out;
  }

  /// Extrait toutes les trames complètes disponibles dans `buffer` (accumulé
  /// depuis un flux Socket) et renvoie les octets restants (trame partielle).
  /// `onFrame` est appelé pour chaque trame complète, dans l'ordre.
  static Uint8List drain(
    Uint8List buffer,
    void Function(Uint8List payload) onFrame,
  ) {
    var bytes = buffer;
    while (bytes.length >= 4) {
      final len = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
      if (bytes.length < 4 + len) break; // trame incomplète, attend la suite
      onFrame(bytes.sublist(4, 4 + len));
      bytes = bytes.sublist(4 + len);
    }
    return bytes;
  }
}
