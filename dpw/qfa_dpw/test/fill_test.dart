// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER fill_test.dart · 2026-11-20 · lot 25 (W17 : correspondance des fiches, champ apk)
import 'package:flutter_test/flutter_test.dart';
import 'package:qfa_dpw/core/fill_match.dart';
import 'package:qfa_dpw/vault/entry.dart';

void main() {
  final ubs = Entry(nam: 'UBS e-banking', url: 'https://www.ubs.com/login', who: 'marc', pass: 'x');
  final post = Entry(nam: 'PostFinance', url: 'postfinance.ch', who: 'm2', pass: 'y');
  final wifi = Entry(nam: 'Wi-Fi maison', who: '', pass: 'z');
  final all = [ubs, post, wifi];

  test('hote d’une url', () {
    expect(hostOf('https://www.ubs.com/login'), 'ubs.com');
    expect(hostOf('postfinance.ch'), 'postfinance.ch');
    expect(hostOf(''), '');
  });

  test('site : meme hote ou sous-domaine en tete', () {
    expect(fillMatches(all, web: 'ubs.com'), [ubs]);
    expect(fillMatches(all, web: 'secure.ubs.com'), [ubs]);
    expect(fillMatches(all, web: 'www.postfinance.ch').first, post);
    expect(fillMatches(all, web: 'example.org'), isEmpty);
  });

  test('app : morceau significatif du paquet', () {
    expect(fillMatches(all, pkg: 'com.ubs.mobile'), [ubs]);
    expect(fillMatches(all, pkg: 'ch.postfinance.android'), [post]);
    expect(fillMatches(all, pkg: 'com.android.chrome'), isEmpty); // « chrome » n'est dans aucune fiche
  });

  test('app retenue : score le plus haut', () {
    wifi.apk = ['com.example.router'];
    expect(fillMatches(all, pkg: 'com.example.router'), [wifi]);
    expect(fillScore(wifi, pkg: 'com.example.router'), 4);
    wifi.apk = [];
  });

  test('champ apk : synchro, empreinte inchangee sans apk, noms invalides ecartes', () {
    final e = Entry(nam: 'a', pass: 'b');
    final h0 = e.hash;
    expect(Entry.fromJson(e.toJson()).hash, h0);
    expect(e.toJson().containsKey('apk'), isFalse);
    e.apk = Entry.cleanApks(['com.ubs.mobile', 'com.ubs.mobile', '../x', 'pasdepoint', 'ch.post.app']);
    expect(e.apk, ['com.ubs.mobile', 'ch.post.app']);
    expect(e.hash, isNot(h0));
    final back = Entry.fromJson(e.toJson());
    expect(back.apk, e.apk);
    expect(back.hash, e.hash);
    expect(back.extra.containsKey('apk'), isFalse);
  });
}
