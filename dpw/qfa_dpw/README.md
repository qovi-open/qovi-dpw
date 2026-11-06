# qfa_dpw — client du trousseau Qovi DpW

Windows d'abord, Android ensuite : meme code, meme look (fenetre au ratio d'un telephone).

- `lib/core/alone.dart` : ouverture Alone (CH1) -> GO sur le mobile (CH4) -> cle du trousseau (CH5).
- `lib/vault/` : trousseau `_DpW_v2.aes` (AES-256-GCM) ; lit l'ancien `_DpW.aes` du WL sans jamais le modifier.
- La cle du trousseau reste en memoire jusqu'au verrouillage ou a la fermeture ; rien de secret sur disque.
- Tests : `flutter test`. Construction : `flutter build windows`, `flutter build apk` ou `flutter build linux` ; paquet Debian : `bash tool/build_deb.sh <version> <dossier>`.
