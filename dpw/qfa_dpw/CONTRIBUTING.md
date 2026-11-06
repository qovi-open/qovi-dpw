# Contributing to Qovi DpW

Thank you for your interest. Contributions are accepted under the project
licence, **GPL-3.0-or-later**, and must be certified with the
[Developer Certificate of Origin](https://developercertificate.org/) (DCO).

Each commit must carry a `Signed-off-by` line with your real name and e-mail:

    git commit -s -m "Short description of the change"

which adds:

    Signed-off-by: Your Name <you@example.com>

By signing off, you certify that you wrote the change or have the right to
submit it under the project licence.

Please keep each change small and focused, run `flutter analyze` and
`flutter test` before submitting, and describe in the commit message what
the change does and why.

Security problems must not be reported publicly: see SECURITY.md.

The shared library `shared/fid_cmp/fid_cmp` (channel encryption and message
framing) is published so that the application can be rebuilt from source,
but it is maintained by the author only: **contributions to `fid_cmp` are not
accepted**. Please report problems in it as issues (or privately, for
security matters).

---

**Français.** Les contributions sont acceptées sous la licence du projet
(GPL-3.0-or-later) et chaque commit doit porter une ligne `Signed-off-by`
(DCO), ajoutée par `git commit -s`.
La bibliothèque partagée `shared/fid_cmp/fid_cmp` est publiée pour permettre
de reconstruire l'application, mais elle n'accepte pas de contributions
extérieures : signalez-y les problèmes (en privé pour la sécurité).
