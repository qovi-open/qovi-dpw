// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER app_state.dart · 2026-11-06 · lot 15 (un trousseau par environnement ; repartir d'un trousseau vide)
// Etat de l'application. La cle du trousseau vit ICI, en memoire seulement,
// jusqu'au verrouillage ou a la fermeture de l'app.
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/alone.dart';
import '../core/local_cfg.dart';
import '../env.dart';
import '../sync/mov.dart';
import '../txt.dart';
import '../vault/entry.dart';
import '../vault/vault.dart';

enum Screen { login, folder, list, edit, net, sync }

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

class AppState extends ChangeNotifier {
  LocalCfg? cfg;
  String? _sok;
  Vault? vault;
  AloneClient? _cli;

  bool busy = false;
  String status = '';
  String? error;
  String? info;
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
    if (_showSync) return Screen.sync;
    return editing != null ? Screen.edit : Screen.list;
  }

  Future<void> init() async {
    cfg = await LocalCfg.load();
    applyLang(cfg!.lang);
    filter = cfg!.filter;
    _idle ??= Timer.periodic(const Duration(seconds: 20), (_) => checkIdle());
    notifyListeners();
  }

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  // ── Connexion ──────────────────────────────────────────────────────────
  static final _mail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> login(String email, bool keep) async {
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
    });
    final cli = AloneClient(env, c.mobU);
    _cli = cli;
    try {
      _sok = await cli.run(email, (m) => _set(() => status = m));
      await _openVault();
    } on AloneError catch (e) {
      error = e.msg;
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

  /// Dossier PRIVE de l'app (lot 2d, decision de Marc 01.11) : le trousseau vit
  /// sur l'appareil, invisible de l'usager ; les appareils se synchronisent par QR.
  /// Lot 15 (decision de Marc 06.11) : UN TROUSSEAU PAR ENVIRONNEMENT, dans
  /// <localDir>/tst et <localDir>/prd ; changer d'environnement ne rend donc
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
      for (final n in [kVaultV2, kVaultWl]) {
        final src = File('$old${Platform.pathSeparator}$n');
        final dst = File('$d${Platform.pathSeparator}$n');
        if (await src.exists() && !await dst.exists()) await src.copy(dst.path);
      }
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
    final names = [kVaultV2, for (var i = 1; i <= kBackups; i++) '$kVaultV2.bak$i', kVaultWl];
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

  /// Choisit un ancien trousseau WL (_DpW.aes) pour l'importer ensuite.
  Future<void> pickOldVault() async {
    final f = await openFile(acceptedTypeGroups: [
      XTypeGroup(label: T.oldWlType, extensions: const ['aes'])
    ]);
    if (f == null) return;
    try {
      final d = await _localDir();
      await File('$d${Platform.pathSeparator}$kVaultWl').writeAsBytes(await f.readAsBytes(), flush: true);
      _set(() => info = T.oldPicked);
    } catch (e) {
      _set(() => error = T.oldReadFail(e));
    }
  }

  Future<void> _openVault() async {
    try {
      final v = Vault(await _localDir(), _sok!);
      await v.open();
      vault = v;
      if (v.convertedFromWl) info = T.converted;
    } on VaultError catch (e) {
      error = e.msg;
    } catch (e) {
      error = T.openFail(e);
    }
  }

  /// Verrouille : oublie la cle et le contenu du trousseau.
  void lock() {
    _host?.cancel();
    _host = null;
    _showSync = false;
    syncBusy = false;
    syncQr = null;
    _sok = null;
    vault = null;
    editing = null;
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
      await h.open(v.data);
      _set(() {
        syncQr = h.qr;
        syncStatus = T.scanThis;
      });
      final remote = await h.waitPeer();
      if (!identical(_host, h)) return; // remplace entre-temps (code saisi)
      final st = await v.applyRemote(remote);
      _syncDone(st.toString());
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
      final remote = await SyncJoin(env, cfg!.mobU, _sok!).run(code, mine);
      final st = await v.applyRemote(remote);
      _syncDone(st.toString());
    } on SyncError catch (e) {
      _syncFail(e.msg);
    } catch (_) {
      _syncFail(T.syncFail);
    }
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
  /// Entrees visibles : chaque mot du filtre (« A B » = A ET B) doit se
  /// trouver dans le nom ou dans la note, sans tenir compte des majuscules
  /// ni des accents (« cle » trouve « Clé »).
  List<Entry> get visible {
    final l = [...?vault?.entries];
    final words = foldText(filter).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final r = words.isEmpty
        ? l
        : l.where((e) {
            final t = foldText('${e.nam}\n${e.note}');
            return words.every(t.contains);
          }).toList();
    r.sort((a, b) => b.use.compareTo(a.use));
    return r;
  }

  /// Le filtre est memorise a chaque modification (reglages locaux).
  void setFilter(String f) {
    _set(() => filter = f);
    final c = cfg;
    if (c != null && c.filter != f) {
      c.filter = f;
      unawaited(c.save());
    }
  }

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

  void newEntry() => _set(() => editing = Entry(nam: '', pass: Entry.newPassword()));

  void edit(Entry e) => _set(() => editing = e.copy());

  void closeEdit() => _set(() => editing = null);

  Future<void> save(Entry e) async {
    e.mod = DateTime.now().toUtc();
    e.use = e.mod;
    await _guard(() => vault!.upsert(e));
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

  // ── Ancien trousseau WL ──────────────────────────────────────────────
  bool get hasOldVault => vault?.hasWl ?? false;

  /// Importe l'ancien trousseau avec son ancienne cle ; la cle n'est gardee
  /// nulle part (ni en memoire au-dela de cet appel, ni sur disque).
  Future<bool> importOld(String oldKey) async {
    try {
      final (n, del) = await vault!.importWl(oldKey);
      error = null;
      info = T.imported(n, del);
      notifyListeners();
      return true;
    } on VaultError catch (e) {
      _set(() => error = e.msg);
    } catch (_) {
      _set(() => error = T.importFail);
    }
    return false;
  }

  // ── Ecran Reseau ─────────────────────────────────────────────────────
  void showNet(bool v) => _set(() => _showNet = v);

  Future<void> setEnv(DpwEnv e) async {
    if (cfg!.env == e) return;
    cfg!.env = e;
    await cfg!.save();
    lock(); // un trousseau ouvert sous un environnement ne reste pas ouvert sous l'autre
  }

  void dismiss() => _set(() {
        error = null;
        info = null;
      });

  @override
  void dispose() {
    _clip?.cancel();
    super.dispose();
  }
}
