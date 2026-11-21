// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER alone.dart · 2026-11-16 · lot 18 (refus de Qovi : texte du message par numero, MoB.4)
// Parcours d'ouverture du trousseau, repris du test_alone_client.dart valide
// le 29.10 (A1 + A2) :
//   1. CH1  GET <api>/RST/SiT_1_Edr?P=...  (cle Alone + cle PUBLIQUE du site)
//      g.u = identifiant de la transaction, tire par DpW et retrouve dans
//      les reponses de Qovi.
//   1b. (Android, lot 10 ; lot 12 : seulement APRES l'envoi de i:2 sur CH4,
//      sinon DpW peut etre endormi avant la demande de vote et Qovi
//      s'ouvre sans rien a valider) DpW ouvre <api>/app/auth?act=<g.u> : Android passe
//      la main a l'app Qovi (ou a la page qui invite a l'installer). C'est Qovi
//      qui fait la bascule ; apres le vote, Qovi rouvre DpW par le lien
//      verifie https://<site DpW>/qovi-retour (AndroidManifest + assetlinks
//      du site). DpW ne lit rien au retour : il attend le GO comme avant.
//      Si l'ouverture echoue, rien ne change : la notification reveille Qovi.
//      Lot 11 : pendant que Qovi est devant, Android endort DpW et sa
//      connexion CH4 peut mourir sans bruit (le GO part dans le vide). Au
//      retour au premier plan, DpW ferme donc lui-meme CH4 : la boucle se
//      reconnecte aussitot par i:1 SEUL et le serveur renvoie le GO deja donne.
//   2. CH4  TLS <hote api>:6404, attente du GO valide sur le mobile (130 s),
//           en G1 (lot 4b) : la cle Prv_NaP ne circule plus, seule son
//           empreinte (kid) part en tete de la 1re trame. Si le canal est
//           coupe pendant l'attente (appli Qovi ouverte sur le meme
//           telephone), DpW se reconnecte et renvoie i:1 SEUL : le serveur
//           renvoie alors le GO deja donne (jamais i:2, qui relancerait le vote).
//   3. CH5  TLS <dpwHost>:6999, Act + G1(x) (AES-256-GCM, cle derivee de Ch5.U,
//           lot 3a) -> cle du trousseau
// SECURITE : la cle du trousseau (SoK.U) et Ch5.U ne sont jamais journalisees
// ni affichees ; seuls des messages generiques remontent a l'ecran. Le lien
// vers Qovi ne porte que g.u (identifiant de transaction, pas un secret) ;
// l'adresse de retour vit cote Qovi (fiche du site) et n'est jamais envoyee.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fid_cmp/fid_cmp.dart' show ChFraming;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:url_launcher/url_launcher.dart';

import '../env.dart';
import '../txt.dart';
import 'g1.dart';
import 'rand.dart';

const int _resKo = 1; // Res_Ko_ic
const int _resEx = 5; // Res_Ex_ic

class AloneError implements Exception {
  AloneError(this.msg);
  final String msg;
  @override
  String toString() => msg;
}

typedef StepCb = void Function(String msg);

// ── CH4 « G1 » (format publie par TLP le 02.11, vecteurs dans les tests) ──
const String kG1Ch4 = 'qovi-ch4-gcm';
const String _kCh4Kid = 'qovi-ch4-kid';

/// Empreinte de la transaction (32 hexa) : remplace la cle Prv_NaP en clair.
String ch4Kid(String nap) => g1Key(nap, _kCh4Kid)
    .sublist(0, 16)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// 1re trame d'une connexion CH4 : kid + G1(i:1).
String ch4First(Uint8List k, String kid, {Uint8List? nonce}) =>
    kid + g1Seal(k, 'ch4q|$kid', jsonEncode({'g': {}, 'c': {'i': 1}}), nonce: nonce);

/// Trame suivante (vote demande) : G1(i:2).
String ch4Vote(Uint8List k, String kid) =>
    g1Seal(k, 'ch4q|$kid', jsonEncode({'g': {}, 'c': {'i': 2}}));

/// Reponse du serveur ; null si pas G1, mauvaise cle ou message altere.
String? ch4Open(Uint8List k, String kid, String env) => g1Open(k, 'ch4r|$kid', env);

/// Lien d'ouverture de Qovi pour la transaction [act] (lot 10).
Uri qoviAuthUri(String api, String act) =>
    Uri.parse(api).replace(path: '/app/auth', queryParameters: {'act': act});

enum _Ch4End { go, refused, broken }

class AloneClient {
  AloneClient(this.cfg, this.mobU);

  final EnvCfg cfg;

  /// UID permanent du poste (64 hexa), tire au premier lancement. Pas un secret.
  final String mobU;

  static const Duration _delai = Duration(seconds: 10);
  Socket? _ch4;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _ch4?.destroy();
  }

  /// Renvoie la cle du trousseau (64 hexa). [share] = SoK.b (cle partagee par
  /// les postes du compte), oui par defaut.
  Future<String> run(String email, StepCb step, {bool share = true}) async {
    if (!cfg.ready) {
      throw AloneError(T.envNotReady(cfg.label));
    }
    step(T.stepOpen);
    final (nap, act) = await _open(email);
    if (_cancelled) throw AloneError(T.cancelled);
    step(T.stepValidate);
    final go = await _waitGo(nap, act);
    step(T.stepReceived);
    return _ch5(go.$1, go.$2, share);
  }

  // ── 1. CH1 : ouverture Alone ────────────────────────────────────────────
  /// Rend (Prv_NaP, g.u) : g.u est tire ici et identifie la transaction.
  Future<(String, String)> _open(String email) async {
    final act = randUuid();
    final x = {
      'g': {
        'u': act,
        'p': {'e': email, 'r': 'Ouverture du trousseau DpW'},
      },
      'c': {
        'Key': {'U': kAloneUc},
        'SaM': {'U': cfg.sitePub},
      },
    };
    final p = base64Url.encode(utf8.encode(jsonEncode(x)));
    final base = Uri.parse(cfg.api);
    final uri = base.replace(path: '/RST/SiT_1_Edr', query: 'P=$p');
    final http = HttpClient()..connectionTimeout = _delai;
    String body;
    try {
      final req = await http.getUrl(uri).timeout(_delai);
      final res = await req.close().timeout(_delai);
      body = await res.transform(utf8.decoder).join().timeout(_delai);
    } catch (_) {
      throw AloneError(T.qoviDown(base.host));
    } finally {
      http.close(force: true);
    }
    Map<String, dynamic> d;
    try {
      d = jsonDecode(utf8.decode(base64.decode(base64.normalize(body.trim()))))
          as Map<String, dynamic>;
    } catch (_) {
      throw AloneError(T.qoviBad);
    }
    final a = d['a'];
    final chx = a is Map ? a['ChX'] : null;
    final prv = chx is Map ? chx['Prv'] : null;
    final nap = prv is Map ? prv['u'] : null;
    if (nap is! String || nap.isEmpty) {
      throw AloneError(_tipText(d, T.qoviRefused));
    }
    return (nap, act);
  }

  // ── 1b. Bascule vers Qovi (Android seulement, lot 10) ──────────────────
  /// Ouvre Qovi sur la transaction ; tout echec est silencieux (la
  /// notification de Qovi reste le chemin de secours).
  Future<void> _toQovi(String act) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await launchUrl(qoviAuthUri(cfg.api, act), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── 2. CH4 : attente du GO (G1, reconnexion automatique) ───────────────
  Future<(String, String)> _waitGo(String nap, String act) async {
    final host = Uri.parse(cfg.api).host;
    final kid = ch4Kid(nap);
    final k = g1Key(nap, kG1Ch4);
    final fin = DateTime.now().add(const Duration(seconds: 130));
    // Lot 11 : au retour au premier plan (Android), CH4 est ferme volontairement
    // pour forcer la reconnexion i:1 (le GO a pu partir sur une connexion morte).
    final retour = (Platform.isAndroid || Platform.isIOS)
        ? AppLifecycleListener(onResume: () => _ch4?.destroy())
        : null;
    try {
      return await _waitLoop(host, kid, k, fin, act);
    } finally {
      retour?.dispose();
    }
  }

  Future<(String, String)> _waitLoop(
      String host, String kid, Uint8List k, DateTime fin, String act) async {
    var vote = true; // seule la 1re connexion demande le vote (i:2)
    var essai = 0;
    while (true) {
      if (_cancelled) throw AloneError(T.cancelled);
      final reste = fin.difference(DateTime.now());
      if (reste <= Duration.zero) throw AloneError(T.noApproval);
      // la bascule vers Qovi ne part qu'avec la demande de vote (1re connexion)
      final r = await _ch4Once(host, kid, k, vote, reste, essai == 0,
          onVote: vote ? () => _toQovi(act) : null);
      switch (r.$1) {
        case _Ch4End.go:
          return r.$2!;
        case _Ch4End.refused:
          throw AloneError(r.$3!);
        case _Ch4End.broken:
          if (_cancelled) throw AloneError(T.cancelled);
          vote = false;
          essai++;
          // petite attente croissante (1, 2, 3 s max) : le temps que le
          // reseau revienne quand l'app repasse au premier plan
          await Future<void>.delayed(Duration(seconds: essai < 3 ? essai : 3));
      }
    }
  }

  /// Une connexion CH4. Rend (go, (act, ch5U), _) ou (refused, _, message)
  /// ou (broken, _, _) si le canal tombe ou n'a pas pu s'ouvrir (sauf au tout
  /// premier essai, ou c'est une erreur franche).
  Future<(_Ch4End, (String, String)?, String?)> _ch4Once(String host, String kid,
      Uint8List k, bool vote, Duration reste, bool premier,
      {Future<void> Function()? onVote}) async {
    final Socket s;
    try {
      s = await SecureSocket.connect(host, kCh4Port, timeout: _delai);
    } catch (_) {
      if (premier) throw AloneError(T.ch4Down('$host:$kCh4Port'));
      return (_Ch4End.broken, null, null);
    }
    _ch4 = s;
    final done = Completer<(_Ch4End, (String, String)?, String?)>();
    void end((_Ch4End, (String, String)?, String?) v) {
      if (!done.isCompleted) done.complete(v);
    }

    var buf = Uint8List(0);
    s.listen((data) {
      buf = ChFraming.drain(Uint8List.fromList([...buf, ...data]), (payload) {
        final clr = ch4Open(k, kid, utf8.decode(payload, allowMalformed: true));
        if (clr == null) return; // non G1 ou altere : ignore
        final Object? m;
        try {
          m = jsonDecode(clr);
        } catch (_) {
          return;
        }
        if (m is! Map) return;
        final a = m['a'];
        final c5 = a is Map ? a['Ch5'] : null;
        final ch5 = (c5 is Map ? c5['U'] : null)?.toString().toLowerCase() ?? '';
        final g = m['g'];
        final act = (g is Map ? g['u'] : null)?.toString() ?? '';
        if (RegExp(r'^[0-9a-f]{64}$').hasMatch(ch5) && act.isNotEmpty) {
          end((_Ch4End.go, (act, ch5), null));
        } else {
          final tip = m['Tip'];
          final r = tip is Map ? tip['r'] : null;
          if (r == _resKo || r == _resEx) {
            end((_Ch4End.refused, null, _tipText(m, T.reqRefused)));
          }
        }
      });
    }, onError: (_) => end((_Ch4End.broken, null, null)),
        onDone: () => end((_Ch4End.broken, null, null)));

    try {
      s.add(ChFraming.frame(utf8.encode(ch4First(k, kid))));
      if (vote) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!done.isCompleted) {
          s.add(ChFraming.frame(utf8.encode(ch4Vote(k, kid))));
          await s.flush(); // la demande de vote est partie avant toute bascule
          if (onVote != null) await onVote();
        }
      }
      return await done.future.timeout(reste, onTimeout: () => (_Ch4End.broken, null, null));
    } catch (_) {
      return (_Ch4End.broken, null, null);
    } finally {
      s.destroy();
      _ch4 = null;
    }
  }

  // ── 3. CH5 : remise de la cle du trousseau ──────────────────────────────
  Future<String> _ch5(String act, String ch5U, bool share) async {
    final Socket s;
    try {
      s = await SecureSocket.connect(cfg.dpwHost, kCh5Port, timeout: _delai);
    } catch (_) {
      throw AloneError(T.dpwDown(cfg.dpwHost));
    }
    try {
      final x = {
        'g': {'u': act},
        'c': {
          'Mob': {'U': mobU},
          'SoK': {'b': share},
        },
      };
      final act32 = act.replaceAll('-', '').toLowerCase();
      final k = g1Key(ch5U, kG1Ch5);
      s.add(ChFraming.frame(utf8.encode(act32 + g1Seal(k, 'ch5q|$act32', jsonEncode(x)))));
      final rep = await oneFrame(s, const Duration(seconds: 60));
      if (rep == null) throw AloneError(T.dpwNoReply);
      final clr = g1Open(k, 'ch5r|$act32', rep);
      if (clr == null) throw AloneError(_refus(rep));
      final m = jsonDecode(clr);
      final a = m is Map ? m['a'] : null;
      final sk = a is Map ? a['SoK'] : null;
      final sok = (sk is Map ? sk['U'] : null)?.toString().toLowerCase() ?? '';
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sok)) {
        throw AloneError(T.keyMissing);
      }
      return sok;
    } finally {
      s.destroy();
    }
  }

  /// Lit UNE trame (4 octets de longueur + charge) ; null si rien ou delai.
  static Future<String?> oneFrame(Socket s, Duration t) async {
    final c = Completer<String?>();
    var buf = Uint8List(0);
    final sub = s.listen((d) {
      buf = ChFraming.drain(Uint8List.fromList([...buf, ...d]), (p) {
        if (!c.isCompleted) c.complete(utf8.decode(p, allowMalformed: true));
      });
    }, onDone: () {
      if (!c.isCompleted) c.complete(null);
    }, onError: (_) {
      if (!c.isCompleted) c.complete(null);
    });
    try {
      return await c.future.timeout(t, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  static String _tipText(Map m, String fallback) => tipText(m, fallback);

  /// Texte d'un refus (Tip) de Qovi, sur CH1 comme sur CH4. Un numero connu
  /// (Tip.t[0], ex. 441) donne son texte dans la langue de DpW, avec %Waits
  /// remplace par la valeur recue ; sinon le texte Tip.s, sinon le numero
  /// (un refus n'est jamais masque). Lot 18 (MoB.4).
  static String tipText(Map m, String fallback) {
    final tip = m['Tip'];
    if (tip is! Map) return '$fallback.';
    final t0 = tip['t'];
    if (t0 is List && t0.isNotEmpty) {
      final n = int.tryParse('${t0.first}');
      final known = n == null ? null : T.tip(n, _tipVar(t0, '%Waits'));
      if (known != null) return known;
    }
    final s = tip['s'];
    if (s is String && s.isNotEmpty && s.length < 200) return '$fallback : $s';
    final t = tip['t'];
    if (t is List && t.isNotEmpty) return '$fallback (${T.message(t.first)}).';
    return '$fallback.';
  }

  /// Valeur qui suit [name] dans Tip.t (paires '%Nom', valeur) ; vide si
  /// absente. Nettoyee : sans caracteres de controle, 16 caracteres au plus.
  static String _tipVar(List t, String name) {
    for (var i = 1; i + 1 < t.length; i++) {
      if (t[i] == name) {
        final v = '${t[i + 1] ?? ''}'.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
        return v.length > 16 ? '' : v;
      }
    }
    return '';
  }

  static String _refus(String rep) {
    try {
      final m = jsonDecode(rep);
      final tip = m is Map ? m['Tip'] : null;
      final s = tip is Map ? tip['s'] : null;
      if (s is String && s.length < 40) return T.dpwRefusedWhy(s);
    } catch (_) {}
    return T.dpwRefused;
  }
}
