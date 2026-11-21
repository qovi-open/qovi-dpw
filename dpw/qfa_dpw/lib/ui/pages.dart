// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER pages.dart · 2026-11-18 · lot 19 (W12 : version en bas des reglages)
// Les ecrans. Meme code pour Windows et Android : la fenetre Windows a le
// ratio d'un telephone, donc aucune mise en page "bureau" a part.
// Planche v3 validee par Marc le 01.11 :
//  - en-tete : boutons encadres (retour, SignOut) ; « Qovi DpW » NON encadre,
//    un simple appui ouvre les reglages ; petit carre orange = environnement Test ;
//  - accueil : ⟳ et + en haut a droite ; ✕ encadre a droite de la recherche ;
//  - fiche : textes et boutons plus grands, 🗑 et ✓ en haut a droite, la note
//    descend jusqu'en bas de l'ecran ;
//  - connexion : gros bouton SignIn, adresse toujours retenue, ✕ pour l'oublier ;
//  - reglages : choix de la langue (FR, DE, IT, EN).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../env.dart';
import '../txt.dart';
import '../version.dart';
import '../vault/entry.dart';
import 'app_state.dart';
import 'logo.dart';
import 'style.dart';
import 'sync_page.dart';

const double _kHead = 48;

class Shell extends StatefulWidget {
  const Shell({super.key, required this.app});
  final AppState app;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.addListener(_onApp);
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    app.removeListener(_onApp);
    super.dispose();
  }

  /// Toute touche compte comme activite (verrouillage apres inactivite).
  bool _onKey(KeyEvent e) {
    app.activity();
    return false;
  }

  /// Au retour au premier plan (telephone), le delai a pu passer en arriere-plan.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) app.checkIdle();
  }

  /// Une information (copie faite, synchro terminee…) s'affiche une fois
  /// dans une bulle en bas de l'ecran, puis disparait.
  void _onApp() {
    if (app.info == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = app.takeInfo();
      if (i == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(i),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3 + i.length ~/ 40),
        ));
    });
  }

  /// En-tete commun (la fiche a le sien, avec 🗑 et ✓).
  Widget _header() {
    final s = app.screen;
    final home = s == Screen.list || s == Screen.login;
    final Widget? left = switch (s) {
      Screen.list => SqBtn(icon: Icons.logout, tip: T.lock, onTap: app.lock, child: const SignOutImg(size: 32)),
      Screen.sync => SqBtn(icon: Icons.arrow_back_ios_new, tip: T.back, onTap: app.closeSync),
      Screen.net => SqBtn(icon: Icons.arrow_back_ios_new, tip: T.back, onTap: () => app.showNet(false)),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SizedBox(
        height: _kHead,
        child: Row(children: [
          if (left != null) ...[left, const SizedBox(width: 10)],
          if (home) _Brand(app: app),
          const Spacer(),
          if (s == Screen.list) ...[
            SqBtn(icon: Icons.sync, tip: T.sync, onTap: app.openSync),
            const SizedBox(width: 10),
            SqBtn(icon: Icons.add, tip: T.newKey, onTap: app.newEntry),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.cfg == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final Widget body = switch (app.screen) {
          Screen.login => LoginPage(app: app),
          Screen.folder => FolderPage(app: app),
          Screen.list => ListPage(app: app),
          Screen.edit => EditPage(key: ValueKey(app.editing!.id), app: app, entry: app.editing!),
          Screen.net => NetPage(app: app),
          Screen.sync => SyncPage(app: app),
        };
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => app.activity(),
          onPointerSignal: (_) => app.activity(),
          child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              if (app.screen != Screen.edit) _header(),
              if (app.error != null) _Banner(text: app.error!, onClose: app.dismiss),
              Expanded(child: body),
            ]),
          ),
        ),
        );
      },
    );
  }
}

/// « Qovi DpW » (non encadre) : un appui ouvre les reglages. Le petit carre
/// orange signale l'environnement Test.
class _Brand extends StatelessWidget {
  const _Brand({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final tst = app.env.env == DpwEnv.tst;
    return Tooltip(
      message: T.settings,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: app.busy ? null : () => app.showNet(true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              const DpwLogo(size: 32),
              if (tst)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6AD55),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 10),
            const Text.rich(TextSpan(children: [
              TextSpan(text: 'Qovi ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Dpw.txt)),
              TextSpan(text: 'DpW', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Dpw.red)),
            ])),
          ]),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        dense: true,
        title: Text(text),
        trailing: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ),
    );
  }
}

// ── Connexion ────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.app});
  final AppState app;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _mail = TextEditingController(text: widget.app.cfg!.email);

  @override
  void dispose() {
    _mail.dispose();
    super.dispose();
  }

  void _forget() {
    _mail.clear();
    widget.app.forgetEmail();
  }

  // L'adresse est toujours retenue (planche v3) : ✕ pour l'oublier.
  void _go() => widget.app.login(_mail.text, true);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListView(padding: const EdgeInsets.fromLTRB(22, 24, 22, 24), children: [
      const Center(child: DpwLogo(size: 110)),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _mail,
            enabled: !app.busy,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(hintText: T.email),
            onSubmitted: (_) => _go(),
          ),
        ),
        const SizedBox(width: 8),
        SqBtn(icon: Icons.close, tip: T.forgetEmail, onTap: app.busy ? null : _forget),
      ]),
      const SizedBox(height: 28),
      if (!app.busy)
        Center(
          child: SqBtn(icon: Icons.login, tip: T.open, size: 130, onTap: _go, child: const SignInImg(size: 92)),
        )
      else ...[
        const Center(child: CircularProgressIndicator(color: Dpw.red)),
        const SizedBox(height: 14),
        Text(app.status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Dpw.txt)),
        const SizedBox(height: 14),
        Center(child: SqBtn(icon: Icons.close, tip: T.cancel, muted: true, onTap: app.cancelLogin)),
      ],
    ]);
  }
}

// ── Trousseau illisible ──────────────────────────────────────────────────
class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.error_outline, size: 56, color: Dpw.red),
      const SizedBox(height: 16),
      Text(T.cannotOpen, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text(T.freshOrKeep, textAlign: TextAlign.center, style: const TextStyle(color: Dpw.sub)),
      const SizedBox(height: 24),
      // Lot 15 (decision de Marc 06.11) : deux choix seulement. Repartir d'un
      // trousseau vide, ou verrouiller et laisser tel quel (rien d'autre).
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SqBtn(icon: Icons.restart_alt, tip: T.freshVault, size: 62, onTap: () => _fresh(context)),
        const SizedBox(width: 24),
        SqBtn(icon: Icons.logout, tip: T.lock, size: 62, onTap: app.lock, child: const SignOutImg(size: 40)),
      ]),
    ]);
  }

  Future<void> _fresh(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(T.freshVault),
        content: Text(T.freshAsk),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(T.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(T.freshVault)),
        ],
      ),
    );
    if (ok == true) await app.resetVault();
  }
}

// ── Liste des cles ───────────────────────────────────────────────────────
class ListPage extends StatefulWidget {
  const ListPage({super.key, required this.app});
  final AppState app;
  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  late final _filter = TextEditingController(text: widget.app.filter);
  bool _menu = false;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// Action sur les filtres, puis le champ reprend le texte du filtre courant.
  Future<void> _do(Future<void> Function() f) async {
    await f();
    if (!mounted) return;
    final t = widget.app.filter;
    _filter.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    setState(() => _menu = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final items = app.visible;
    return Column(children: [
      // Lot 17 (W2) : clic dans le champ = menu des filtres enregistres ;
      // un filtre choisi s'applique tout de suite et le menu se referme.
      TapRegion(
        onTapOutside: (_) {
          if (_menu) setState(() => _menu = false);
        },
        child: Column(children: [
          // Retour de Marc 10.11 : memes boutons (48) et memes ecarts (10)
          // que l'en-tete, pour que − tombe sous ⏻, ⌫ sous ⟳ et + sous +.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Row(children: [
              SqBtn(
                  icon: Icons.remove,
                  tip: T.fltDel,
                  onTap: app.curFlt == null ? null : () => _do(app.deleteFilter)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _filter,
                  style: const TextStyle(fontSize: 17),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Dpw.sub),
                    suffixIcon: Icon(_menu ? Icons.expand_less : Icons.expand_more, color: Dpw.sub),
                  ),
                  onTap: () => setState(() => _menu = true),
                  onChanged: app.setFilter,
                  onSubmitted: (_) => _do(app.submitFilter),
                ),
              ),
              const SizedBox(width: 10),
              SqBtn(icon: Icons.backspace_outlined, tip: T.clear, onTap: () => _do(app.clearFilter)),
              const SizedBox(width: 10),
              SqBtn(icon: Icons.add, tip: T.fltAdd, onTap: () => _do(app.addFilter)),
            ]),
          ),
          if (_menu) _FltMenu(app: app, onPick: (id) => _do(() => app.applyFilter(id))),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          itemCount: items.length,
          itemBuilder: (context, i) => _EntryCard(app: app, e: items[i]),
        ),
      ),
    ]);
  }
}

/// Menu deroulant des filtres enregistres (lot 17, W2).
class _FltMenu extends StatelessWidget {
  const _FltMenu({required this.app, required this.onPick});
  final AppState app;
  final void Function(String id) onPick;

  @override
  Widget build(BuildContext context) {
    final l = app.filters;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
          color: Dpw.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Dpw.line)),
      child: l.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Text(T.fltNone, style: const TextStyle(color: Dpw.sub)))
          : ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
              for (final f in l)
                ListTile(
                  dense: true,
                  selected: f.id == app.curFlt,
                  selectedColor: Dpw.red,
                  title: Text(f.txt.trim().isEmpty ? '—' : f.txt,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                  onTap: () => onPick(f.id),
                ),
            ]),
    );
  }
}

/// Date affichee en heure LOCALE (stockee en UTC) : AAAA-MM-JJ HH:MM.
String _ymdhm(DateTime? t) {
  if (t == null) return '—';
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.app, required this.e});
  final AppState app;
  final Entry e;

  @override
  Widget build(BuildContext context) {
    final web = e.url.startsWith('http://') || e.url.startsWith('https://');
    final name = e.nam.isEmpty ? T.noName : e.nam;
    final note = e.note.trim().split('\n').first.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: Dpw.card, borderRadius: BorderRadius.circular(18), boxShadow: Dpw.soft),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // W7 (lot 17) : seulement si « Afficher les dates » est coche ;
        // creation a gauche, modification a droite, un clic trie la liste.
        if (app.showDates)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              _DateTag(app: app, key0: 'cre', t: e.cre, tip: T.sortCre),
              const Spacer(),
              _DateTag(app: app, key0: 'mod', t: e.mod, tip: T.sortMod),
            ]),
          ),
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Dpw.avatarOf(name),
            child: Text(name.characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Dpw.txt)),
              if (note.isNotEmpty)
                Text(note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Dpw.sub)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          SqBtn(icon: Icons.edit_outlined, tip: T.edit, onTap: () => app.edit(e)),
          SqBtn(icon: Icons.person_outline, tip: T.copyWho, onTap: () => app.copyWho(e)),
          SqBtn(icon: Icons.key_outlined, tip: T.copyPass, onTap: () => app.copyPass(e)),
          web ? SqBtn(icon: Icons.open_in_new, tip: T.openSite, onTap: () => app.openUrl(e)) : const SqGap(),
        ]),
      ]),
    );
  }
}

// ── Fiche (consultation et edition) ─────────────────────────────────────
class _DateTag extends StatelessWidget {
  const _DateTag({required this.app, required this.key0, required this.t, required this.tip});
  final AppState app;
  final String key0;
  final DateTime? t;
  final String tip;

  @override
  Widget build(BuildContext context) {
    final on = app.sortBy == key0;
    final arrow = on ? (app.sortDesc ? ' ↓' : ' ↑') : '';
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => app.sortOn(key0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text('${_ymdhm(t)}$arrow',
              style: TextStyle(
                  fontSize: 11.5, color: on ? Dpw.red : Dpw.sub, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
        ),
      ),
    );
  }
}

class EditPage extends StatefulWidget {
  const EditPage({super.key, required this.app, required this.entry});
  final AppState app;
  final Entry entry;
  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  static const double _b = 56; // boutons de la fiche
  static const _fs = TextStyle(fontSize: 19, color: Dpw.txt);

  late final _nam = TextEditingController(text: widget.entry.nam);
  late final _url = TextEditingController(text: widget.entry.url);
  late final _who = TextEditingController(text: widget.entry.who);
  late final _pass = TextEditingController(text: widget.entry.pass);
  late final _note = TextEditingController(text: widget.entry.note);
  bool _show = false;

  @override
  void dispose() {
    for (final c in [_nam, _url, _who, _pass, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isNew => !(widget.app.vault?.entries.any((x) => x.id == widget.entry.id) ?? false);

  /// La fiche telle qu'affichee (pour copier/ouvrir sans enregistrer).
  Entry _cur() => widget.entry.copy()
    ..nam = _nam.text.trim()
    ..url = _url.text.trim()
    ..who = _who.text
    ..pass = _pass.text
    ..note = _note.text;

  Future<void> _save() async {
    final c = _cur();
    final e = widget.entry
      ..nam = c.nam
      ..url = c.url
      ..who = c.who
      ..pass = c.pass
      ..note = c.note;
    await widget.app.save(e);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(T.delAsk),
        content: Text(widget.entry.nam),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(T.no)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(T.delete)),
        ],
      ),
    );
    if (ok == true) await widget.app.remove(widget.entry);
  }

  Widget _lead(IconData icon, String tip) =>
      Tooltip(message: tip, child: SizedBox(width: 34, child: Icon(icon, size: 28, color: Dpw.sub)));

  Widget _field(IconData icon, String tip, TextEditingController c, List<Widget> acts,
      {bool obscure = false, TextInputType? kb}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        _lead(icon, tip),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: c, obscureText: obscure, keyboardType: kb, style: _fs)),
        for (final a in acts) ...[const SizedBox(width: 8), a],
      ]),
    );
  }

  SqBtn _btn(IconData i, String tip, VoidCallback onTap) => SqBtn(icon: i, tip: tip, size: _b, onTap: onTap);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final eye = _btn(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        _show ? T.hidePass : T.showPass, () => setState(() => _show = !_show));
    final passActs = _isNew
        ? [_btn(Icons.autorenew, T.generate, () => setState(() => _pass.text = Entry.newPassword())), eye]
        : [eye, _btn(Icons.copy, T.copyPass, () => app.copyPass(_cur()))];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(children: [
        Row(children: [
          _btn(Icons.arrow_back_ios_new, T.back, app.closeEdit),
          const Spacer(),
          if (!_isNew) ...[_btn(Icons.delete_outline, T.delete, _delete), const SizedBox(width: 10)],
          _btn(Icons.check, T.save, _save),
        ]),
        const SizedBox(height: 16),
        _field(Icons.label_outline, T.name, _nam, const []),
        _field(Icons.public, T.site, _url, [_btn(Icons.open_in_new, T.openSite, () => app.openUrl(_cur()))],
            kb: TextInputType.url),
        _field(Icons.person_outline, T.who, _who, [_btn(Icons.copy, T.copyWho, () => app.copyWho(_cur()))]),
        _field(Icons.key_outlined, T.pass, _pass, passActs, obscure: !_show),
        // La note descend jusqu'en bas de l'ecran.
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 14), child: _lead(Icons.notes, T.note)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _note,
                style: _fs,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Reglages ────────────────────────────────────────────────────────────
class NetPage extends StatelessWidget {
  const NetPage({super.key, required this.app});
  final AppState app;

  Widget _langBtn(Lang l) => _choice(l.name.toUpperCase(), lang == l, () => app.setLang(l.name));

  /// Bouton de choix (langue, delai) : rouge plein quand il est actif.
  Widget _choice(String label, bool on, VoidCallback onTap) {
    return Material(
      color: on ? Dpw.red : Dpw.btn,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Dpw.red, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: SizedBox(
          width: 58,
          height: 48,
          child: Center(
            child: Text(label,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: on ? Colors.white : Dpw.red)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = app.cfg!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(T.language, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final l in Lang.values) _langBtn(l)]),
      const SizedBox(height: 20),
      const Divider(),
      Text(T.autoLock, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final m in const [5, 15, 30, 60, 120])
          _choice(m < 60 ? '$m min' : '${m ~/ 60} h', c.idleMin == m, () => app.setIdle(m)),
      ]),
      const SizedBox(height: 12),
      const Divider(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: Dpw.red,
        title: Text(T.showDates, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(T.showDatesHint),
        value: c.showDates,
        onChanged: app.setShowDates,
      ),
      const Divider(),
      Text(T.env, style: const TextStyle(fontWeight: FontWeight.bold)),
      RadioGroup<DpwEnv>(
        groupValue: c.env,
        onChanged: (v) {
          if (v != null) app.setEnv(v);
        },
        child: Column(children: [
          for (final e in DpwEnv.values)
            RadioListTile<DpwEnv>(
              value: e,
              title: Text(EnvCfg.of(e).label),
              subtitle: Text(EnvCfg.of(e).ready ? EnvCfg.of(e).api : T.notYet),
            ),
        ]),
      ),
      if (app.unlocked)
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(T.envLocks),
        ),
      const Divider(),
      if (app.unlocked && !app.hasOldVault)
        ListTile(
          title: Text(T.oldWl),
          subtitle: Text(T.oldWlHint),
          trailing: TextButton(onPressed: app.pickOldVault, child: Text(T.choose)),
        ),
      if (app.hasOldVault)
        ListTile(
          title: Text(T.oldReady),
          subtitle: Text(T.oldReadyHint),
          trailing: TextButton(onPressed: () => _askOldKey(context), child: Text(T.importBtn)),
        ),
      ListTile(
        title: Text(T.deviceId),
        subtitle: Text('#${c.mobU.substring(0, 8)}'),
      ),
      // W12 : version de l'app (lib/version.dart, verifiee contre pubspec.yaml)
      ListTile(
        title: Text(T.version),
        subtitle: Text(dpwVerLabel),
      ),
    ]);
  }

  Future<void> _askOldKey(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(T.oldKey),
        content: TextField(
          controller: ctl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: T.hex64),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(T.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(T.importBtn)),
        ],
      ),
    );
    final key = ctl.text;
    ctl.dispose();
    if (ok == true) await app.importOld(key);
  }
}
