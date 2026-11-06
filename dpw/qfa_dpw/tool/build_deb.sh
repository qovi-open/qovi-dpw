#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Marc Gandar
# FILEVER build_deb.sh · 2026-11-04 · paquet Debian/Ubuntu de Qovi DpW (RUNPATH des plugins = $ORIGIN)
# Compile l'app Linux (flutter build linux) et fabrique
# <dossier de sortie>/qovi-dpw_<version>_amd64.deb :
#   /opt/qovi-dpw/                         l'app (bundle Flutter)
#   /usr/bin/qovi-dpw                      commande (lien vers l'app)
#   /usr/share/applications/qovi-dpw.desktop  entree de menu
#   /usr/share/icons/hicolor/192x192/apps/qovi-dpw.png  icone Q rouge
# Installation : sudo apt install ./qovi-dpw_<version>_amd64.deb
# Desinstallation : sudo apt remove qovi-dpw (le trousseau, dans le profil de
# l'usager, n'est pas touche). Mise a jour : installer la nouvelle version.
# Usage : bash tool/build_deb.sh [version] [dossier de sortie]
#         (defauts : 3.0.1 et dist/ a cote de pubspec.yaml)
# Outils : flutter, dpkg-deb, patchelf (paquets clang cmake ninja-build libgtk-3-dev patchelf).
set -euo pipefail
VER=${1:-3.0.1}
D=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=${2:-$D/dist}
mkdir -p "$OUTDIR"
OUT=$OUTDIR/qovi-dpw_${VER}_amd64.deb
ST=$(mktemp -d /tmp/qovi-dpw-deb.XXXXXX)
trap 'rm -rf "$ST"' EXIT

cd "$D"
flutter build linux --release
B=$D/build/linux/x64/release/bundle
[ -x "$B/qfa_dpw" ] || { echo "!! bundle absent : $B"; exit 1; }
# Les plugins compiles gardent le dossier de compilation dans leur RUNPATH :
# on le remplace par $ORIGIN (les bibliotheques sont toutes dans lib/).
command -v patchelf >/dev/null || { echo "!! patchelf manquant (sudo apt install patchelf)"; exit 1; }
for so in "$B"/lib/*.so; do
  rp=$(patchelf --print-rpath "$so")
  if [ -n "$rp" ] && [ "$rp" != '$ORIGIN' ]; then patchelf --set-rpath '$ORIGIN' "$so"; echo "RUNPATH remis a \$ORIGIN : $(basename "$so")"; fi
done
ICO=$D/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
[ -f "$ICO" ] || { echo "!! icone absente : $ICO"; exit 1; }

mkdir -p "$ST/DEBIAN" "$ST/opt/qovi-dpw" "$ST/usr/bin" "$ST/usr/share/applications" "$ST/usr/share/icons/hicolor/192x192/apps"
cp -a "$B/." "$ST/opt/qovi-dpw/"
ln -s /opt/qovi-dpw/qfa_dpw "$ST/usr/bin/qovi-dpw"
cp "$ICO" "$ST/usr/share/icons/hicolor/192x192/apps/qovi-dpw.png"

cat > "$ST/usr/share/applications/qovi-dpw.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Qovi DpW
GenericName=Password keychain
GenericName[fr]=Trousseau de mots de passe
GenericName[de]=Passwort-Schlüsselbund
GenericName[it]=Portachiavi di password
Comment=Password keychain opened by Qovi, synced by QR without cloud
Comment[fr]=Trousseau de mots de passe ouvert par Qovi, synchronisé par QR sans cloud
Exec=/opt/qovi-dpw/qfa_dpw
Icon=qovi-dpw
Terminal=false
Categories=Utility;Security;
StartupWMClass=qfa_dpw
DESK

SIZE=$(du -sk "$ST/opt" | cut -f1)
cat > "$ST/DEBIAN/control" <<CTL
Package: qovi-dpw
Version: $VER
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0t64 | libgtk-3-0 (>= 3.24), libc6 (>= 2.31)
Installed-Size: $SIZE
Maintainer: Marc Gandar <security@qovi.ch>
Homepage: https://qovi.ch
Description: Qovi DpW - password keychain opened by Qovi
 Password keychain opened by Qovi without a master password,
 synchronised between PC and phone by QR code, without any cloud.
 Licence GPL-3.0-or-later.
CTL

find "$ST" -type d -exec chmod 755 {} +
dpkg-deb --root-owner-group --build "$ST" "$OUT" >/dev/null
echo "== paquet"; dpkg-deb -I "$OUT" | grep -E "Package|Version|Architecture|Depends|Installed-Size"
echo "== contenu (extrait)"; dpkg-deb -c "$OUT" | awk '{print $6}' | grep -vE "/data/flutter_assets/.+/" | head -20
ls -l "$OUT"; md5sum "$OUT"
