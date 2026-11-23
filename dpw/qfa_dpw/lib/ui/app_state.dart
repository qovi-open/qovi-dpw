// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER app_state.dart · 2026-11-20 · lot 31 (575 : bouton aussi sur iPhone ; lot 30 : lien de la demande a venir ; lot 29)
// Etat de l'application. La cle du trousseau vit ICI, en memoire seulement,
// jusqu'au verrouillage ou a la fermeture de l'app.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/alone.dart';
import '../core/rand.dart';
import '../core/local_cfg.dart';
import '../env.dart';
import '../sync/merge.dart';
import '../sync/mov.dart';
import '../txt.dart';
import '../vault/entry.dart';
import '../vault/vault.dart';

enum Screen { login, folder, list, edit, net, sync, fill }

/// W17 (lot 25) : demande de remplissage venue d'une autre app (Android).
class FillReq {
  FillReq(this.web, this.pkg);
  final String web, pkg;
}

/// Minuscules sans accents, pour le filtre.
String foldText(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// Filtre de la liste (lot 17, W3) : chaque mot doit se trouver dans [text]
/// (« A B » = A ET B, dans n'importe quel ordre) ; un mot precede de « - »
/// EXCLUT les fiches qui le contiennent. Sans majuscules ni accents.
bool matchFilter(String filter, String text) {
  final t = foldText(text);
  for (final w in foldText(filter).split(RegExp(r'\s+'))) {
    if (w.isEmpty || w == '-') continue;
    if (w.startsWith('-')) {
      if (t.contains(w.substring(1))) return false;
    } else if (!t.contains(w)) {
      return false;
    }
  }
  return true;
}

class AppState extends ChangeNotifier {
  LocalCfg? cfg;
  String? _sok;
  Vault? vault;
  AloneClient? _cli;

  bool busy = false;
  String status = '';
  String? error;
  String? info;

  /// Lot 28 (essai de Marc 20.11) : refus 575 sur Android avec Qovi installe
  /// sur ce telephone -> bouton « Ouvrir Qovi, puis reessayer ».
  bool qoviHelp = false;
  bool _retryOnResume = false;
  String? _preAct; // lot 30 : identifiant de la demande deja annoncee a Qovi
  static const _qoviCh = MethodChannel('dpw/qovi');
  String filter = '';
  Entry? editing;
  bool _showNet = false;

  // Synchronisation par QR (lot 2)
  bool _showSync = false;
  SyncHost? _host;
  bool syncBusy = false;
  String syncStatus = '';
  String? syncQr;

  Timer? _clip;
  String? _clipValue;

  EnvCfg get env => EnvCfg.of(cfg?.env ?? DpwEnv.prd);
  bool get unlocked => vault != null;

  Screen get screen {
    if (_showNet) return Screen.net;
    if (vault == null) return _sok != null ? Screen.folder : Screen.login;
    if (fill != null) return Screen.fill; // W17 : apres la validation Qovi
    if (_showSync) return Screen.sync;
    return editing != null ? Screen.edit : Screen.list;
  }

  Future<void> init() async {
    cfg = await LocalCfg.load();
    applyLang(cfg!.lang);
    _idle ??= Timer.periodic(const Duration(seconds: 20), (_) => checkIdle());
    _initFill();
    notifyListeners();
  }

  // ── W17 (lot 25) : remplissage automatique Android ─────────────────────
  // Le service Android (DpwAutofillService.kt) ouvre DpW avec le domaine du
  // site ou le paquet de l'app ; la fiche choisie repart par ce canal. Le
  // mot de passe ne quitte DpW qu'apres le toucher de l'usager sur la fiche.
  static const _fillCh = MethodChannel('dpw/autofill');
  FillReq? fill;

  void _initFill() {
    if (!Platform.isAndroid) return;
    _fillCh.setMethodCallHandler((c) async {
      if (c.method == 'request') _setFill(c.arguments);
      return null;
    });
    _fillCh.invokeMethod<Object?>('pending').then(_setFill, onError: (_) {});
  }

  void _setFill(Object? a) {
    if (a is! Map) return;
    String clean(Object? v) {
      final t = '${v ?? ''}'.trim();
      return t.length > 253 ? t.substring(0, 253) : t;
    }

    _set(() {
      fill = FillReq(clean(a['web']), clean(a['pkg']));
      _showNet = false; // lot 26 : la page des reglages ne passe plus devant (essai de Marc)
    });
  }

  // Lot 26 (Marc 20.11) : sites en deux pages (email puis mot de passe) :
  // la fiche choisie juste avant pour le meme site ou la meme app revient en
  // tete pendant 2 minutes. En memoire seulement, oubliee au verrouillage.
  String? _lastFillId;
  String _lastFillKey = '';
  DateTime? _lastFillAt;

  static String _fillKey(FillReq f) => f.web.isNotEmpty ? 'w:${f.web}' : 'p:${f.pkg}';

  /// Identifiant de la fiche choisie il y a moins de 2 min pour [f], sinon null.
  String? recentFill(FillReq f) {
    final at = _lastFillAt;
    if (at == null || _lastFillId == null || _lastFillKey != _fillKey(f)) return null;
    return DateTime.now().difference(at) < const Duration(minutes: 2) ? _lastFillId : null;
  }

  /// La fiche [e] part vers l'app ; [remember] l'associe au paquet de l'app.
  Future<void> fillWith(Entry e, {bool remember = false}) async {
    final f = fill;
    if (f == null) return;
    if (remember && f.pkg.isNotEmpty && !e.apk.contains(f.pkg) && vault != null) {
      final c = e.copy()
        ..apk = Entry.cleanApks([...e.apk, f.pkg])
        ..mod = DateTime.now().toUtc();
      await _guard(() => vault!.upsert(c));
    }
    _lastFillId = e.id;
    _lastFillKey = _fillKey(f);
    _lastFillAt = DateTime.now();
    try {
      await _fillCh.invokeMethod<void>('fill', {'who': e.who, 'pass': e.pass});
    } catch (_) {
      // l'app d'origine a disparu : rien a remplir
    }
    _set(() => fill = null);
  }

  Future<void> fillCancel() async {
    try {
      await _fillCh.invokeMethod<void>('cancel');
    } catch (_) {}
    _set(() => fill = null);
  }

  /// Ouvre la page Android « service de saisie automatique ».
  Future<void> openFillSettings() async {
    try {
      await _fillCh.invokeMethod<void>('settings');
    } catch (_) {}
  }

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  // ── Connexion ──────────────────────────────────────────────────────────
  static final _mail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> login(String email, bool keep, {String? act}) async {
    final c = cfg!;
    email = email.trim();
    if (!_mail.hasMatch(email)) {
      _set(() => error = T.badEmail);
      return;
    }
    c
      ..keepEmail = keep
      ..email = email;
    await c.save();
    _set(() {
      busy = true;
      error = null;
      info = null;
      status = '';
      qoviHelp = false;
    });
    final cli = AloneClient(env, c.mobU);
    _cli = cli;
    try {
      _sok = await cli.run(email, (m) => _set(() => status = m), preset: act);
      await _openVault();
    } on AloneError catch (e) {
      error = e.msg;
      // Lot 31 (DpW.12, Marc 20.11) : sur iPhone, DpW ne peut pas savoir si Qovi
      // est installe : bouton toujours propose (lien https : Qovi s'il est la,
      // sinon la page de qovi.ch qui propose de l'installer).
      if (e.tip == 575) qoviHelp = Platform.isIOS || await _qoviHere();
    } catch (_) {
      error = T.loginFailed;
    } finally {
      _cli = null;
      busy = false;
      status = '';
      notifyListeners();
    }
  }

  void cancelLogin() => _cli?.cancel();

  /// Lot 28 : Qovi est-il installe sur ce telephone ? (Android seulement ;
  /// sur iPhone, DpW ne peut pas le savoir sans schema d'adresse de Qovi.)
  Future<bool> _qoviHere() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _qoviCh.invokeMethod<bool>('has') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Lot 28 : ouvre Qovi (pour qu'il se connecte) ; au retour dans DpW, le
  /// login est relance une fois, tout seul (onResume).
  /// Lot 29 (essai de Marc 20.11 : il fallait revenir a la main) : DpW relance
  /// lui-meme le login 3 s apres, en arriere-plan ; Qovi est alors en ligne,
  /// la demande de vote lui arrive et son retour automatique ramene a DpW.
  /// Si Android a endormi DpW entre-temps, onResume reste le filet.
  /// Lot 30 (essai de Marc 20.11 : pas de retour Qovi -> DpW) : relance en
  /// arriere-plan, DpW ne peut plus ouvrir Qovi sur la demande ; or Qovi ne
  /// revient a l'app que si le lien de CETTE demande lui est arrive (#ret2).
  /// DpW tire donc l'identifiant (g.u) maintenant, ouvre Qovi par le lien
  /// `/app/auth?act=<g.u>` (au premier plan, permis), puis relance avec ce g.u.
  Future<void> openQoviRetry() async {
    var ok = false;
    final act = randUuid();
    try {
      ok = await launchUrl(qoviAuthUri(env.api, act), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      try {
        ok = await _qoviCh.invokeMethod<bool>('open') ?? false;
      } catch (_) {}
    }
    _preAct = ok ? act : null;
    _set(() {
      qoviHelp = false;
      if (ok) {
        _retryOnResume = true;
        error = null;
      }
    });
    if (ok) {
      Timer(const Duration(seconds: 3), () {
        if (!_retryOnResume) return; // deja relance au retour
        _retryOnResume = false;
        final c = cfg;
        if (c == null || busy || unlocked || c.email.isEmpty) return;
        unawaited(login(c.email, true, act: _takeAct()));
      });
    }
  }

  /// Retour au premier plan : relance du login demandee par openQoviRetry.
  void onResume() {
    if (!_retryOnResume) return;
    _retryOnResume = false;
    final c = cfg;
    if (c == null || busy || unlocked || c.email.isEmpty) return;
    unawaited(login(c.email, true, act: _takeAct())); // comme le bouton de la page de connexion
  }

  /// L'identifiant annonce a Qovi ne sert qu'une fois.
  String? _takeAct() {
    final a = _preAct;
    _preAct = null;
    return a;
  }

  /// Dossier PRIVE de l'app (lot 2d, decision de Marc 01.11) : le trousseau vit
  /// sur l'appareil, invisible de l'usager ; les appareils se synchronisent par QR.
  /// Lot 15 (decision de Marc 06.11) : UN TROUSSEAU PAR ENVIRONNEMENT, dans
  /// `localDir/tst` et `localDir/prd` ; changer d'environnement ne rend donc
  /// plus le trousseau de l'autre illisible. [localDir] est le dossier de base.
  String? localDir;

  Future<String> _localDir() async {
    final sep = Platform.pathSeparator;
    final base = localDir ?? '${(await getApplicationSupportDirectory()).path}${sep}vault';
    localDir = base;
    final d = '$base$sep${cfg!.env == DpwEnv.tst ? 'tst' : 'prd'}';
    await Directory(d).create(recursive: true);
    await _takeRootVault(base, d);
    // Reprise unique de l'ancien dossier choisi a la main (lot 1, ex. Dropbox).
    final old = cfg!.vaultDir;
    if (old.isNotEmpty && old != d) {
      final src = File('$old${Platform.pathSeparator}$kVaultV2');
      final dst = File('$d${Platform.pathSeparator}$kVaultV2');
      if (await src.exists() && !await dst.exists()) await src.copy(dst.path);
      cfg!.vaultDir = '';
      await cfg!.save();
      info = T.movedLocal;
    }
    return d;
  }

  /// Lot 15 : reprise UNIQUE du trousseau commun d'avant (un seul dossier
  /// pour Test et Production) : il est DEPLACE (pas copie) dans le dossier de
  /// l'environnement selectionne a ce moment, avec ses sauvegardes. Rien ne
  /// bouge si ce dossier a deja son trousseau.
  Future<void> _takeRootVault(String base, String d) async {
    final sep = Platform.pathSeparator;
    if (await File('$d$sep$kVaultV2').exists()) return;
    final names = [kVaultV2, for (var i = 1; i <= kBackups; i++) '$kVaultV2.bak$i'];
    for (final n in names) {
      final src = File('$base$sep$n');
      if (await src.exists() && !await File('$d$sep$n').exists()) await src.rename('$d$sep$n');
    }
  }

  /// Lot 15 (decision de Marc 06.11) : le trousseau ne s'ouvre pas avec la cle
  /// que le serveur donne pour ce compte. DpW ne devine rien et ne repare rien :
  /// l'usager choisit de repartir d'un trousseau vide (ici) ou de verrouiller et
  /// laisser tel quel. Le fichier illisible n'est NI efface NI rouvert : il est
  /// renomme « …illisible-AAAAMMJJ-HHMMSS » (avec ses sauvegardes), puis un
  /// trousseau vide est cree avec la cle actuelle du compte.
  Future<void> resetVault() async {
    if (_sok == null || vault != null) return;
    try {
      final sep = Platform.pathSeparator;
      final d = await _localDir();
      final t = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final tag = 'illisible-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
      for (final n in [kVaultV2, for (var i = 1; i <= kBackups; i++) '$kVaultV2.bak$i']) {
        final f = File('$d$sep$n');
        if (await f.exists()) await f.rename('$d$sep$n.$tag');
      }
    } catch (e) {
      _set(() => error = T.openFail(e));
      return;
    }
    error = null;
    info = null;
    await _openVault();
    if (vault != null && error == null) info = T.freshDone;
    notifyListeners();
  }

  Future<void> _openVault() async {
    try {
      final v = Vault(await _localDir(), _sok!);
      await v.open();
      vault = v;
      await _initFilters();
    } on VaultError catch (e) {
      error = e.msg;
    } catch (e) {
      error = T.openFail(e);
    }
  }

  /// Verrouille : oublie la cle et le contenu du trousseau.
  void lock() {
    unawaited(_commit()); // filtre en cours de frappe : enregistre avant d'oublier la cle
    _lastFillId = null; // lot 26 : la derniere fiche choisie est oubliee
    _lastFillAt = null;
    _host?.cancel();
    _host = null;
    _showSync = false;
    syncBusy = false;
    syncQr = null;
    _sok = null;
    vault = null;
    editing = null;
    curFlt = null;
    filter = '';
    sortBy = '';
    // W14 (lot 20) : les photos de carte dechiffrees ne restent pas en memoire.
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } catch (_) {
      // pas de moteur graphique (tests) : rien a effacer
    }
    notifyListeners();
  }


  // ── Synchronisation par QR (lot 2) ───────────────────────────────────
  void openSync() => _set(() {
        _showSync = true;
        syncQr = null;
        syncStatus = '';
        error = null;
        info = null;
      });

  void closeSync() {
    _host?.cancel();
    _host = null;
    _set(() {
      _showSync = false;
      syncBusy = false;
      syncQr = null;
      syncStatus = '';
    });
  }

  /// Cet appareil AFFICHE le QR (A) : depose son trousseau, attend l'autre.
  Future<void> syncShowQr() async {
    final v = vault;
    if (v == null || _sok == null || syncBusy) return;
    final h = SyncHost(env, cfg!.mobU, _sok!);
    _host = h;
    _set(() {
      syncBusy = true;
      error = null;
      syncStatus = T.syncPrep;
    });
    try {
      await v.reloadIfChanged();
      await h.open(v.data, img: _myImg(v));
      _set(() {
        syncQr = h.qr;
        syncStatus = T.scanThis;
      });
      final (remote, peerImg) = await h.waitPeer();
      if (!identical(_host, h)) return; // remplace entre-temps (code saisi)
      final st = await v.applyRemote(remote);
      _set(() => syncQr = null);
      final ph = await _photos(v, h.photos(), peerImg, () => !identical(_host, h) || h.cancelled);
      if (!identical(_host, h)) return;
      _syncDone('$st$ph');
    } on SyncError catch (e) {
      if (identical(_host, h)) _syncFail(e.msg);
    } catch (_) {
      if (identical(_host, h)) _syncFail(T.syncFail);
    }
  }

  /// Cet appareil a SCANNE (ou saisi) le QR de l'autre (S).
  Future<void> syncWithCode(String code) async {
    // Un code saisi remplace un QR en cours d'affichage sur cet appareil.
    if (_host != null) {
      _host!.cancel();
      _host = null;
      syncBusy = false;
    }
    final v = vault;
    if (v == null || _sok == null || syncBusy) return;
    _set(() {
      syncBusy = true;
      error = null;
      syncQr = null;
      syncStatus = T.syncSwap;
    });
    try {
      await v.reloadIfChanged();
      final mine = v.data; // AVANT fusion : c'est lui qui part vers l'autre
      final (remote, peerImg, ps) =
          await SyncJoin(env, cfg!.mobU, _sok!).run(code, mine, img: _myImg(v));
      final st = await v.applyRemote(remote);
      final ph = await _photos(v, ps, peerImg, () => !_showSync);
      _syncDone('$st$ph');
    } on SyncError catch (e) {
      _syncFail(e.msg);
    } catch (_) {
      _syncFail(T.syncFail);
    }
  }

  /// Photos referencees par le trousseau et presentes sur cet appareil.
  Set<String> _myImg(Vault v) =>
      {for (final e in v.entries) for (final id in e.crd) if (v.cards.has(id)) id};

  /// W14 etape 2 (lot 22) : apres la fusion, echange des photos manquantes.
  /// Rend le complement du message de fin ('' si rien a signaler). Un echec
  /// n'annule jamais la synchro des fiches, deja enregistree.
  Future<String> _photos(Vault v, PhotoSync ps, Set<String>? peer, bool Function() stop) async {
    final used = {for (final e in v.entries) ...e.crd};
    final plan = PhotoPlan.of(used, {for (final id in used) if (v.cards.has(id)) id}, peer);
    if (plan.isEmpty) return '';
    _set(() => syncStatus = T.photosStep(0, plan.send.length + plan.get.length));
    final r = await ps.run(plan,
        read: v.cards.get,
        write: v.cards.putAs,
        onStep: (d, t) => _set(() => syncStatus = T.photosStep(d, t)),
        cancelled: stop);
    if (r.got > 0) PaintingBinding.instance.imageCache.clear();
    if (r.complete) return '\n${T.photosOk(r.sent, r.got)}';
    return '\n${T.photosFail}';
  }

  void _syncDone(String msg) {
    _host = null;
    _set(() {
      _showSync = false;
      syncBusy = false;
      syncQr = null;
      syncStatus = '';
      info = msg;
    });
  }

  void _syncFail(String msg) {
    _host = null;
    if (!_showSync) return; // ecran deja ferme par l'usager : rien a signaler
    _set(() {
      syncBusy = false;
      syncQr = null;
      syncStatus = '';
      error = msg;
    });
  }

  // ── Liste et fiches ──────────────────────────────────────────────────
  /// Entrees visibles : voir [matchFilter] (lot 17 : « -mot » exclut).
  /// Tri : dernier usage ; ou, dates affichees (W7), la date choisie.
  List<Entry> get visible {
    final r = [for (final e in [...?vault?.entries]) if (matchFilter(filter, '${e.nam}\n${e.note}')) e];
    final far = DateTime.utc(1970);
    if (showDates && sortBy == 'cre') {
      r.sort((a, b) => (a.cre ?? far).compareTo(b.cre ?? far));
    } else if (showDates && sortBy == 'mod') {
      r.sort((a, b) => a.mod.compareTo(b.mod));
    } else {
      r.sort((a, b) => b.use.compareTo(a.use));
      return r;
    }
    return sortDesc ? r.reversed.toList() : r;
  }

  // ── Filtres enregistres (lot 17, W2/W3) ──────────────────────────────
  // Chiffres DANS le trousseau (synchronises) ; les reglages locaux ne gardent
  // que l'identifiant du filtre courant, jamais son texte.
  String? curFlt;
  Timer? _fltSave;

  /// Menu : du plus recemment modifie au plus ancien.
  List<Flt> get filters => [...?vault?.filters]..sort((a, b) => b.mod.compareTo(a.mod));

  Flt? _flt(String? id) {
    for (final f in vault?.filters ?? const <Flt>[]) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Apres l'ouverture du trousseau : reprise unique de l'ancien filtre (en
  /// clair dans les reglages) puis retour au filtre courant.
  Future<void> _initFilters() async {
    final v = vault, c = cfg;
    if (v == null || c == null) return;
    final old = c.filter.trim();
    if (old.isNotEmpty) {
      var f = v.filters.where((x) => x.txt == old).firstOrNull;
      if (f == null) {
        final now = DateTime.now().toUtc();
        f = Flt(randHex(16), old, now, now);
        await _guard(() => v.putFilter(f!));
      }
      c.fltId = f.id;
      c.filter = '';
      await c.save();
    }
    final f = _flt(c.fltId);
    curFlt = f?.id;
    filter = f?.txt ?? '';
  }

  /// Taper dans le champ : brouillon seulement, la liste se filtre mais
  /// aucun filtre enregistre ne change (retour de Marc 10.11 : sinon le +
  /// retombait sur le filtre courant). Entree ou + enregistrent.
  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }

  Future<void> _commit() async {
    _fltSave?.cancel();
    _fltSave = null;
    final v = vault, cur = _flt(curFlt);
    if (v != null && cur != null) await _guard(() => v.putFilter(cur));
  }

  Future<void> _setCur(Flt? f) async {
    curFlt = f?.id;
    filter = f?.txt ?? '';
    final c = cfg;
    if (c != null && c.fltId != (f?.id ?? '')) {
      c.fltId = f?.id ?? '';
      await c.save();
    }
  }

  /// Clic dans le menu : ce filtre s'applique tout de suite.
  Future<void> applyFilter(String id) async {
    await _commit();
    final f = _flt(id);
    if (f == null) return;
    f.use = DateTime.now().toUtc();
    await _guard(() => vault!.putFilter(f));
    await _setCur(_flt(id));
    notifyListeners();
  }

  /// + : enregistre le texte comme filtre (s'il existe deja, il devient courant).
  Future<void> addFilter() async {
    await _commit();
    final t = filter.trim();
    if (t.isEmpty || vault == null) return;
    final same = vault!.filters.where((x) => x.txt.trim() == t).firstOrNull;
    if (same != null) return applyFilter(same.id);
    final now = DateTime.now().toUtc();
    final f = Flt(randHex(16), t, now, now);
    await _guard(() => vault!.putFilter(f));
    await _setCur(_flt(f.id));
    notifyListeners();
  }

  /// Entree : le texte remplace celui du filtre courant ; sans filtre
  /// courant, il devient un nouveau filtre (comme +).
  Future<void> submitFilter() async {
    final cur = _flt(curFlt), t = filter.trim();
    if (cur == null) return addFilter();
    if (t.isEmpty || vault == null) return;
    final same = vault!.filters.where((x) => x.id != cur.id && x.txt.trim() == t).firstOrNull;
    if (same != null) return applyFilter(same.id);
    if (cur.txt.trim() != t) {
      cur
        ..txt = t
        ..mod = DateTime.now().toUtc();
    }
    await _setCur(cur);
    await _commit();
    notifyListeners();
  }

  /// Le dernier filtre utilise, hors [except].
  Flt? _lastUsed({String? except}) {
    Flt? best;
    for (final f in vault?.filters ?? const <Flt>[]) {
      if (f.id == except) continue;
      if (best == null || f.use.isAfter(best.use)) best = f;
    }
    return best;
  }

  /// Effacer : quitte le filtre courant et reprend le dernier filtre utilise
  /// (s'il n'y en a pas : champ vide, toutes les fiches).
  Future<void> clearFilter() async {
    await _commit();
    final p = _lastUsed(except: curFlt);
    if (p != null) return applyFilter(p.id);
    await _setCur(null);
    notifyListeners();
  }

  /// − : detruit le filtre courant (partout, par la synchro), puis comme Effacer.
  Future<void> deleteFilter() async {
    final id = curFlt;
    if (id == null || vault == null) return;
    _fltSave?.cancel();
    await _guard(() => vault!.dropFilter(id));
    curFlt = null;
    final p = _lastUsed();
    if (p != null) return applyFilter(p.id);
    await _setCur(null);
    notifyListeners();
  }

  // ── Dates (W7) ───────────────────────────────────────────────────────
  bool get showDates => cfg?.showDates ?? false;
  String sortBy = '';
  bool sortDesc = true;

  Future<void> setShowDates(bool v) async {
    cfg!.showDates = v;
    if (!v) sortBy = '';
    await cfg!.save();
    notifyListeners();
  }

  /// Clic sur une date : tri par cette date ; second clic : ordre inverse.
  void sortOn(String key) => _set(() {
        if (sortBy == key) {
          sortDesc = !sortDesc;
        } else {
          sortBy = key;
          sortDesc = true;
        }
      });

  // ── Verrouillage apres inactivite (lot 2m) ────────────────────────────
  // Passe le delai sans touche, clic ni defilement, le trousseau se verrouille
  // (cle et clair effaces de la memoire, presse-papiers vide) et l'app revient
  // a l'ecran de connexion. 60 min par defaut, reglable (decision de Marc 01.11).
  DateTime _last = DateTime.now();
  Timer? _idle;

  /// Toute action de l'usager remet le compteur a zero (sans redessiner).
  void activity() => _last = DateTime.now();

  /// Appele toutes les 20 s, et au retour de l'app au premier plan.
  void checkIdle() {
    if (!unlocked || syncBusy) return;
    final m = cfg?.idleMin ?? 60;
    if (DateTime.now().difference(_last) >= Duration(minutes: m)) {
      unawaited(clearClipboard());
      lock();
    }
  }

  Future<void> setIdle(int min) async {
    cfg!.idleMin = min;
    activity();
    await cfg!.save();
    notifyListeners();
  }

  /// Langue choisie dans les reglages ('' = celle de l'appareil).
  Future<void> setLang(String code) async {
    cfg!.lang = code;
    applyLang(code);
    await cfg!.save();
    notifyListeners();
  }

  /// L'adresse est toujours retenue (lot 2i) ; ce bouton l'oublie.
  Future<void> forgetEmail() async {
    cfg!
      ..email = ''
      ..keepEmail = false;
    await cfg!.save();
    notifyListeners();
  }

  /// Rend l'information en attente et l'efface sans redessiner : l'ecran
  /// l'affiche une fois dans une bulle (lot 2g, plus de ligne de journal).
  String? takeInfo() {
    final i = info;
    info = null;
    return i;
  }

  void newEntry() =>
      _set(() => editing = Entry(nam: '', pass: Entry.newPassword(), cre: DateTime.now().toUtc()));

  void edit(Entry e) => _set(() => editing = e.copy());

  void closeEdit() => _set(() => editing = null);

  Future<void> save(Entry e) async {
    final isNew = !(vault?.entries.any((x) => x.id == e.id) ?? false);
    e.mod = DateTime.now().toUtc();
    e.use = e.mod;
    await _guard(() => vault!.upsert(e));
    // W19 (Marc 20.11) : apres la CREATION d'une fiche, le filtre prend son
    // nom (brouillon : aucun filtre enregistre ne change ; ⌫ le quitte).
    if (isNew && error == null && e.nam.trim().isNotEmpty) filter = e.nam.trim();
    editing = null;
    notifyListeners();
  }

  Future<void> remove(Entry e) async {
    await _guard(() => vault!.delete(e.id));
    editing = null;
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
      error = null;
    } on VaultError catch (e) {
      error = e.msg;
    } catch (e) {
      error = T.saveFail(e);
    }
  }

  // ── Presse-papiers : un mot de passe copie est efface apres 30 s ─────
  Future<void> copyWho(Entry e) async {
    await Clipboard.setData(ClipboardData(text: e.who));
    await _guard(() => vault!.touch(e.id));
    _set(() => info = T.whoCopied);
  }

  Future<void> copyPass(Entry e) async {
    await Clipboard.setData(ClipboardData(text: e.pass));
    _clipValue = e.pass;
    _clip?.cancel();
    _clip = Timer(const Duration(seconds: 30), clearClipboard);
    await _guard(() => vault!.touch(e.id));
    _set(() => info = T.passCopied);
  }

  /// Efface le presse-papiers s'il contient encore le mot de passe copie.
  Future<void> clearClipboard() async {
    _clip?.cancel();
    final v = _clipValue;
    _clipValue = null;
    if (v == null) return;
    final cur = await Clipboard.getData(Clipboard.kTextPlain);
    if (cur?.text == v) await Clipboard.setData(const ClipboardData(text: ''));
  }

  /// Ouvre l'adresse dans le navigateur : http et https seulement.
  Future<void> openUrl(Entry e) async {
    final u = Uri.tryParse(e.url.trim());
    if (u == null || (u.scheme != 'https' && u.scheme != 'http') || u.host.isEmpty) {
      _set(() => info = T.noUrl);
      return;
    }
    await _guard(() => vault!.touch(e.id));
    await launchUrl(u, mode: LaunchMode.externalApplication);
    notifyListeners();
  }

  // ── Ecran Reseau ─────────────────────────────────────────────────────
  void showNet(bool v) => _set(() => _showNet = v);

  Future<void> setEnv(DpwEnv e) async {
    if (cfg!.env == e) return;
    cfg!.env = e;
    await cfg!.save();
    lock(); // un trousseau ouvert sous un environnement ne reste pas ouvert sous l'autre
  }

  /// W14 (lot 20) : erreur affichee dans le bandeau (ex. photo non enregistree).
  void showError(String m) => _set(() => error = m);

  void dismiss() => _set(() {
        error = null;
        info = null;
        qoviHelp = false;
      });

  @override
  void dispose() {
    _clip?.cancel();
    super.dispose();
  }
}
