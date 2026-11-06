// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER env.dart · 2026-11-02 · lot 4c (cle publique de production)
// Environnements du client DpW : Tst et Prd ne different QUE par les adresses
// (principe Tst = Prd). Les adresses sont figees ici, l'usager choisit
// seulement Tst ou Prd. Aucune adresse de remplacement, aucun mode Dev.
enum DpwEnv { tst, prd }

/// Cle Alone (k_Alone_Uc) : ouverture par une app SANS cle privee de site.
const String kAloneUc =
    '9f910f6f83725101eecb01ee034025daba6a2947fe33be4424376e0256c5d46c';

const int kCh4Port = 6404; // attente du GO (TLS par la facade)
const int kCh5Port = 6999; // remise de la cle du trousseau
const int kMovPort = 6998; // transfert entre postes (lot 2)

class EnvCfg {
  const EnvCfg(this.env, this.label, this.api, this.dpwHost, this.sitePub);

  final DpwEnv env;
  final String label;

  /// Qovi : CH1 (https) et CH4 (meme hote, port 6404).
  final String api;

  /// Service DpW : CH5 (6999) et transfert (6998), en TLS par la facade.
  final String dpwHost;

  /// Cle PUBLIQUE du site DpW (whos.SiT_Pub_1/2_Uk). Publique : elle peut
  /// figurer dans le code. Vide = environnement pas encore disponible.
  final String sitePub;

  bool get ready => RegExp(r'^[0-9a-f]{64}$').hasMatch(sitePub);

  static const tst = EnvCfg(DpwEnv.tst, 'Test', 'https://tst.qovi.ch',
      'tst.dpw.qovi.ch',
      '727c0e39942f7221ffa11bef0bfb3bfe08026ff24d611ebc933af0e617e72388');

  // Prod : cle publique du site dpw.qovi.ch en production, transmise par IM
  // le 02.11 (whos.SiT_Pub_1_Uk ; pas de 2e cle).
  static const prd = EnvCfg(DpwEnv.prd, 'Production', 'https://qovi.ch',
      'dpw.qovi.ch',
      'a1c5714e9f3981c0741c5108e639006c24dcba2b5f4d03165e219911be328bfb');

  static EnvCfg of(DpwEnv e) => e == DpwEnv.tst ? tst : prd;
}
