// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER txt.dart · 2026-11-20 · lot 28 (bouton Ouvrir Qovi ; lot 27 : WL retire, chemin Chrome ; lot 25 : W17)
// Tous les textes visibles du client DpW, en quatre langues (decision de
// Marc 01.11 : les trois langues suisses + anglais US). La langue suit
// celle de l'appareil (toute autre langue donne l'anglais), sauf si l'usager
// en choisit une dans les reglages (lot 2i).
// Chaque texte est ecrit fr, de, it, en cote a cote pour faciliter la relecture.
import 'dart:io';

enum Lang { fr, de, it, en }

Lang lang = _detect();

/// Applique la langue choisie ('fr', 'de', 'it', 'en') ; vide = l'appareil.
void applyLang(String code) {
  for (final l in Lang.values) {
    if (l.name == code) {
      lang = l;
      return;
    }
  }
  lang = _detect();
}

Lang _detect() {
  final l = Platform.localeName.toLowerCase();
  if (l.startsWith('fr')) return Lang.fr;
  if (l.startsWith('de')) return Lang.de;
  if (l.startsWith('it')) return Lang.it;
  return Lang.en;
}

String _p(String fr, String de, String it, String en) => switch (lang) {
      Lang.fr => fr,
      Lang.de => de,
      Lang.it => it,
      Lang.en => en,
    };

String _n(int n, String one, String many) => n > 1 ? many : one;

class T {
  // ── Ecrans ──────────────────────────────────────────────────────────
  static String get settings => _p('Réglages', 'Einstellungen', 'Impostazioni', 'Settings');
  static String get language => _p('Langue', 'Sprache', 'Lingua', 'Language');
  static String get forgetEmail => _p('Oublier l’adresse', 'Adresse vergessen', 'Dimentica l’indirizzo', 'Forget the address');
  static String get autoLock => _p('Verrouillage après inactivité', 'Sperre nach Inaktivität',
      'Blocco dopo inattività', 'Lock after inactivity');
  static String get back => _p('Retour', 'Zurück', 'Indietro', 'Back');
  static String get lock => _p('Verrouiller', 'Sperren', 'Bloccare', 'Lock');
  static String get loginHint => _p('Ouvrez votre trousseau en validant sur votre mobile.',
      'Öffnen Sie Ihren Schlüsselbund, indem Sie auf Ihrem Handy bestätigen.',
      'Apra il portachiavi confermando sul suo cellulare.',
      'Open your keychain by approving on your phone.');
  static String get email => _p('Adresse email', 'E-Mail-Adresse', 'Indirizzo e-mail', 'Email address');
  static String get keepEmail => _p('Retenir mon adresse sur ce poste', 'Meine Adresse auf diesem Gerät merken',
      'Ricorda il mio indirizzo su questo dispositivo', 'Remember my address on this device');
  static String get open => _p('Ouvrir le trousseau', 'Schlüsselbund öffnen', 'Apri il portachiavi', 'Open keychain');
  static String get cancel => _p('Annuler', 'Abbrechen', 'Annulla', 'Cancel');
  static String get cannotOpen => _p('Le trousseau de cet appareil ne s’ouvre pas.',
      'Der Schlüsselbund dieses Geräts lässt sich nicht öffnen.',
      'Il portachiavi di questo dispositivo non si apre.',
      'This device’s keychain cannot be opened.');
  static String get clear => _p('Effacer', 'Löschen', 'Cancella', 'Clear');
  static String get fltAdd => _p('Enregistrer ce filtre', 'Diesen Filter speichern', 'Salva questo filtro',
      'Save this filter');
  static String get fltDel => _p('Détruire ce filtre', 'Diesen Filter löschen', 'Elimina questo filtro',
      'Delete this filter');
  static String get fltNone => _p('Aucun filtre enregistré. Tapez un filtre puis +.',
      'Kein gespeicherter Filter. Filter eingeben, dann +.', 'Nessun filtro salvato. Scriva un filtro, poi +.',
      'No saved filters. Type a filter, then +.');
  static String get showDates => _p('Afficher les dates', 'Daten anzeigen', 'Mostra le date', 'Show dates');
  static String get showDatesHint => _p(
      'Création à gauche, modification à droite ; un clic sur une date trie la liste.',
      'Erstellung links, Änderung rechts; ein Klick auf ein Datum sortiert die Liste.',
      'Creazione a sinistra, modifica a destra; un clic su una data ordina l’elenco.',
      'Created on the left, modified on the right; click a date to sort the list.');
  static String get sortCre => _p('Trier par date de création', 'Nach Erstellungsdatum sortieren',
      'Ordina per data di creazione', 'Sort by creation date');
  static String get sortMod => _p('Trier par date de modification', 'Nach Änderungsdatum sortieren',
      'Ordina per data di modifica', 'Sort by modification date');
  static String get sync => _p('Synchroniser', 'Synchronisieren', 'Sincronizzare', 'Sync');
  static String get newKey => _p('Nouvelle clé', 'Neuer Schlüssel', 'Nuova chiave', 'New key');
  static String get noName => _p('(sans nom)', '(ohne Namen)', '(senza nome)', '(no name)');
  static String get edit => _p('Modifier', 'Bearbeiten', 'Modificare', 'Edit');
  static String get copyWho => _p('Copier l’identifiant', 'Benutzernamen kopieren', 'Copia l’identificativo', 'Copy username');
  static String get copyPass => _p('Copier le mot de passe', 'Passwort kopieren', 'Copia la password', 'Copy password');
  static String get openSite => _p('Ouvrir le site', 'Website öffnen', 'Apri il sito', 'Open website');
  static String get delAsk => _p('Supprimer cette clé ?', 'Diesen Schlüssel löschen?', 'Eliminare questa chiave?', 'Delete this key?');
  static String get no => _p('Non', 'Nein', 'No', 'No');
  static String get delete => _p('Supprimer', 'Löschen', 'Elimina', 'Delete');
  static String get hidePass => _p('Masquer', 'Verbergen', 'Nascondi', 'Hide');
  static String get showPass => _p('Afficher', 'Anzeigen', 'Mostra', 'Show');
  static String get generate => _p('Générer', 'Generieren', 'Genera', 'Generate');
  static String get name => _p('Nom', 'Name', 'Nome', 'Name');
  static String get site => _p('Adresse du site', 'Website-Adresse', 'Indirizzo del sito', 'Website address');
  static String get who => _p('Identifiant', 'Benutzername', 'Identificativo', 'Username');
  static String get pass => _p('Mot de passe', 'Passwort', 'Password', 'Password');
  static String get note => _p('Note', 'Notiz', 'Nota', 'Note');
  static String get save => _p('Enregistrer', 'Speichern', 'Salva', 'Save');
  static String get env => _p('Environnement', 'Umgebung', 'Ambiente', 'Environment');
  static String get notYet => _p('Pas encore disponible', 'Noch nicht verfügbar', 'Non ancora disponibile', 'Not yet available');
  static String get envLocks => _p('Changer d’environnement verrouille le trousseau.',
      'Ein Wechsel der Umgebung sperrt den Schlüsselbund.',
      'Cambiare ambiente blocca il portachiavi.',
      'Changing environment locks the keychain.');
  static String get version => _p('Version', 'Version', 'Versione', 'Version');
  static String get deviceId => _p('Identifiant du poste', 'Geräte-ID', 'ID del dispositivo', 'Device ID');
  static String get send => _p('Envoyer (afficher le QR)', 'Senden (QR anzeigen)', 'Invia (mostra il QR)',
      'Send (show the QR)');
  static String get receive => _p('Recevoir (scanner le QR)', 'Empfangen (QR scannen)', 'Ricevi (scansiona il QR)',
      'Receive (scan the QR)');

  // ── Informations ────────────────────────────────────────────────────
  static String get badEmail => _p('Adresse email invalide.', 'Ungültige E-Mail-Adresse.',
      'Indirizzo e-mail non valido.', 'Invalid email address.');
  static String get freshOrKeep => _p('Vous pouvez repartir d’un trousseau vide, ou verrouiller et le laisser tel quel.',
      'Sie können mit einem leeren Schlüsselbund neu beginnen oder sperren und ihn so lassen.',
      'Può ripartire da un portachiavi vuoto, oppure bloccare e lasciarlo così.',
      'You can start over with an empty keychain, or lock and leave it as it is.');
  static String get freshVault => _p('Repartir d’un trousseau vide', 'Mit leerem Schlüsselbund neu beginnen',
      'Ripartire da un portachiavi vuoto', 'Start over with an empty keychain');
  static String get freshAsk => _p(
      'Le trousseau actuel sera mis de côté sur cet appareil et ne sera plus utilisé. Vous pourrez ensuite remplir le nouveau en synchronisant un autre appareil.',
      'Der aktuelle Schlüsselbund wird auf diesem Gerät beiseitegelegt und nicht mehr verwendet. Danach können Sie den neuen durch Synchronisieren mit einem anderen Gerät füllen.',
      'Il portachiavi attuale sarà messo da parte su questo dispositivo e non verrà più usato. Potrà poi riempire il nuovo sincronizzando un altro dispositivo.',
      'The current keychain will be set aside on this device and no longer used. You can then fill the new one by syncing another device.');
  static String get freshDone => _p('Nouveau trousseau vide ouvert ; l’ancien est mis de côté.',
      'Neuer leerer Schlüsselbund geöffnet; der alte wurde beiseitegelegt.',
      'Nuovo portachiavi vuoto aperto; il vecchio è stato messo da parte.',
      'New empty keychain opened; the old one was set aside.');
  static String get loginFailed => _p('Erreur inattendue pendant la connexion.', 'Unerwarteter Fehler bei der Anmeldung.',
      'Errore imprevisto durante l’accesso.', 'Unexpected error while signing in.');
  static String get movedLocal => _p('Trousseau repris dans le stockage local de l’app.',
      'Schlüsselbund in den lokalen Speicher der App übernommen.',
      'Portachiavi ripreso nella memoria locale dell’app.',
      'Keychain moved to the app’s local storage.');
  static String openFail(Object e) => _p("Impossible d'ouvrir le trousseau ($e).",
      'Schlüsselbund kann nicht geöffnet werden ($e).', 'Impossibile aprire il portachiavi ($e).',
      'Cannot open the keychain ($e).');
  static String get syncPrep => _p('Préparation de la synchronisation…', 'Synchronisierung wird vorbereitet…',
      'Preparazione della sincronizzazione…', 'Preparing sync…');
  static String get syncFail => _p('Échec de la synchronisation.', 'Synchronisierung fehlgeschlagen.',
      'Sincronizzazione non riuscita.', 'Sync failed.');
  static String get scanThis => _p('Scannez ce QR avec DpW sur l’autre appareil (valable 10 minutes).',
      'Scannen Sie diesen QR mit DpW auf dem anderen Gerät (10 Minuten gültig).',
      'Scansioni questo QR con DpW sull’altro dispositivo (valido 10 minuti).',
      'Scan this QR with DpW on the other device (valid 10 minutes).');
  // W17 (lot 25) : remplissage automatique Android
  static String get yes => _p('Oui', 'Ja', 'Sì', 'Yes');
  static String fillFor(String t) => _p('Remplir : $t', 'Ausfüllen: $t', 'Compilare: $t', 'Fill in: $t');
  static String get fillNoMatch => _p('Aucune fiche ne correspond : choisissez-la dans la liste.',
      'Kein Eintrag passt: Wählen Sie ihn in der Liste.', 'Nessuna scheda corrisponde: la scelga nell’elenco.',
      'No entry matches: choose it from the list.');
  static String get fillRemember => _p('Retenir pour cette app ?', 'Für diese App merken?', 'Ricordare per questa app?',
      'Remember for this app?');
  static String fillRememberAsk(String nam, String pkg) => _p(
      'La fiche « $nam » sera proposée directement dans l’app $pkg.',
      'Der Eintrag „$nam“ wird in der App $pkg direkt vorgeschlagen.',
      'La scheda «$nam» sarà proposta direttamente nell’app $pkg.',
      'The entry “$nam” will be offered directly in the app $pkg.');
  static String get fillSet => _p('Remplissage automatique', 'Automatisches Ausfüllen', 'Compilazione automatica',
      'Autofill');
  static String get fillSetHint => _p(
      'Choisir Qovi DpW comme service de saisie automatique d’Android (une seule fois).',
      'Qovi DpW als Android-Dienst für automatisches Ausfüllen wählen (einmalig).',
      'Scegliere Qovi DpW come servizio di compilazione automatica di Android (una volta sola).',
      'Choose Qovi DpW as the Android autofill service (once).');
  // W17 (lot 27, chemin releve par Marc sur le S10 le 20.11) : Chrome remplit
  // lui-meme les mots de passe ; il faut lui dire de passer par Android.
  static String get fillChrome => _p(
      'Dans Chrome : Paramètres → Saisie automatique des mots de passe → Service de saisie automatique → « Saisie automatique avec un autre service ».',
      'In Chrome: Einstellungen → Autofill-Dienste → „Autofill mit einem anderen Dienst“.',
      'In Chrome: Impostazioni → Servizi di compilazione automatica → «Compilazione automatica con un altro servizio».',
      'In Chrome: Settings → Autofill services → “Autofill using another service”.');
  // Lot 28 : bouton sous le refus 575, quand Qovi est sur ce telephone.
  static String get qoviOpenRetry => _p('Ouvrir Qovi sur ce téléphone, puis réessayer',
      'Qovi auf diesem Telefon öffnen und erneut versuchen',
      'Aprire Qovi su questo telefono e riprovare',
      'Open Qovi on this phone, then try again');
  static String get fillActivate => _p('Activer', 'Aktivieren', 'Attivare', 'Enable');
  // W18 (lot 23) : image du disque sur PC
  static String get cardPickFront => _p('Choisir ou glisser l’image du recto', 'Bild der Vorderseite wählen oder hierher ziehen',
      'Scegliere o trascinare l’immagine del fronte', 'Choose or drop the front image');
  static String get cardPickBack => _p('Choisir ou glisser l’image du verso', 'Bild der Rückseite wählen oder hierher ziehen',
      'Scegliere o trascinare l’immagine del retro', 'Choose or drop the back image');
  static String get cardImgType => _p('Images', 'Bilder', 'Immagini', 'Images');
  static String get cardTooBig => _p('Image trop grande (20 Mo au plus).', 'Bild zu groß (höchstens 20 MB).',
      'Immagine troppo grande (al massimo 20 MB).', 'Image too large (20 MB at most).');
  static String get cardNotImage => _p('Ce fichier n’est pas une image lisible (JPEG ou PNG).',
      'Diese Datei ist kein lesbares Bild (JPEG oder PNG).', 'Questo file non è un’immagine leggibile (JPEG o PNG).',
      'This file is not a readable image (JPEG or PNG).');
  static String get cardOrigLeft => _p('L’image d’origine est toujours sur votre disque, en clair : supprimez-la si elle ne sert plus.',
      'Das Originalbild liegt weiterhin unverschlüsselt auf Ihrem Datenträger: Löschen Sie es, wenn Sie es nicht mehr brauchen.',
      'L’immagine originale è ancora sul disco, in chiaro: la elimini se non serve più.',
      'The original image is still on your disk, unencrypted: delete it if you no longer need it.');
  // W14 etape 2 (lot 22) : photos de carte apres la synchro des fiches
  static String photosStep(int d, int t) =>
      _p('Photos : $d/$t', 'Fotos: $d/$t', 'Foto: $d/$t', 'Photos: $d/$t');
  static String photosOk(int s, int g) => _p('Photos : $s envoyée(s), $g reçue(s).',
      'Fotos: $s gesendet, $g empfangen.', 'Foto: $s inviate, $g ricevute.', 'Photos: $s sent, $g received.');
  static String get photosFail => _p('Photos non transférées : refais une synchro (les fiches, elles, sont à jour).',
      'Fotos nicht übertragen: Synchronisierung wiederholen (die Einträge sind aktuell).',
      'Foto non trasferite: ripeti la sincronizzazione (le schede sono aggiornate).',
      'Photos not transferred: sync again (the entries themselves are up to date).');
  static String get syncSwap => _p('Échange des trousseaux…', 'Schlüsselbunde werden ausgetauscht…',
      'Scambio dei portachiavi…', 'Exchanging keychains…');
  static String saveFail(Object e) => _p("Échec de l'enregistrement du trousseau ($e).",
      'Speichern des Schlüsselbunds fehlgeschlagen ($e).', 'Salvataggio del portachiavi non riuscito ($e).',
      'Saving the keychain failed ($e).');
  static String get whoCopied => _p('Identifiant copié.', 'Benutzername kopiert.', 'Identificativo copiato.', 'Username copied.');
  static String get passCopied => _p('Mot de passe copié (effacé dans 30 s).', 'Passwort kopiert (in 30 s gelöscht).',
      'Password copiata (cancellata tra 30 s).', 'Password copied (cleared in 30 s).');
  static String get noUrl => _p('Pas d’adresse web valide pour cette clé.', 'Keine gültige Webadresse für diesen Schlüssel.',
      'Nessun indirizzo web valido per questa chiave.', 'No valid web address for this key.');

  // ── Bilan de synchro ────────────────────────────────────────────────
  static String get upToDate => _p('Trousseau déjà à jour.', 'Schlüsselbund bereits aktuell.',
      'Portachiavi già aggiornato.', 'Keychain already up to date.');
  static String added(int n) => _p('$n ${_n(n, 'ajoutée', 'ajoutées')}', '$n hinzugefügt', '$n ${_n(n, 'aggiunta', 'aggiunte')}', '$n added');
  static String changed(int n) => _p('$n ${_n(n, 'modifiée', 'modifiées')}', '$n geändert', '$n ${_n(n, 'modificata', 'modificate')}', '$n changed');
  static String removed(int n) => _p('$n ${_n(n, 'supprimée', 'supprimées')}', '$n gelöscht', '$n ${_n(n, 'eliminata', 'eliminate')}', '$n deleted');
  static String copies(int n) => _p('$n ${_n(n, 'doublon', 'doublons')} à vérifier', '$n ${_n(n, 'Duplikat', 'Duplikate')} zu prüfen',
      '$n ${_n(n, 'doppione', 'doppioni')} da verificare', '$n ${_n(n, 'duplicate', 'duplicates')} to check');
  static String synced(String parts) => _p('Trousseau synchronisé : $parts.', 'Schlüsselbund synchronisiert: $parts.',
      'Portachiavi sincronizzato: $parts.', 'Keychain synced: $parts.');

  // ── Ouverture (CH5) ─────────────────────────────────────────────────
  static String envNotReady(String l) => _p("L'environnement $l n'est pas encore disponible.",
      'Die Umgebung $l ist noch nicht verfügbar.', 'L’ambiente $l non è ancora disponibile.',
      'The $l environment is not available yet.');
  static String get cancelled => _p('Annulé.', 'Abgebrochen.', 'Annullato.', 'Cancelled.');
  static String get stepOpen => _p('Ouverture de la demande…', 'Anfrage wird geöffnet…', 'Apertura della richiesta…', 'Opening the request…');
  static String get stepValidate => _p('Validez la demande sur votre mobile (app Qovi)…',
      'Bestätigen Sie die Anfrage auf Ihrem Handy (App Qovi)…',
      'Confermi la richiesta sul suo cellulare (app Qovi)…',
      'Approve the request on your phone (Qovi app)…');
  static String get stepReceived => _p(
      'Validation reçue, ouverture du trousseau… (la première fois sur un appareil, cela peut prendre jusqu’à une minute)',
      'Bestätigung erhalten, Schlüsselbund wird geöffnet… (beim ersten Mal auf einem Gerät bis zu einer Minute)',
      'Conferma ricevuta, apertura del portachiavi… (la prima volta su un dispositivo può richiedere fino a un minuto)',
      'Approval received, opening the keychain… (the first time on a device can take up to a minute)');
  static String qoviDown(String h) => _p('Qovi est injoignable ($h).', 'Qovi ist nicht erreichbar ($h).',
      'Qovi non è raggiungibile ($h).', 'Qovi is unreachable ($h).');
  static String get qoviBad => _p('Réponse de Qovi illisible.', 'Antwort von Qovi unlesbar.',
      'Risposta di Qovi illeggibile.', 'Unreadable answer from Qovi.');
  static String get qoviRefused => _p('Ouverture refusée par Qovi', 'Öffnen von Qovi abgelehnt',
      'Apertura rifiutata da Qovi', 'Opening refused by Qovi');
  static String ch4Down(String hp) => _p('Canal de validation injoignable ($hp).', 'Bestätigungskanal nicht erreichbar ($hp).',
      'Canale di conferma non raggiungibile ($hp).', 'Approval channel unreachable ($hp).');
  static String get reqRefused => _p('Demande refusée', 'Anfrage abgelehnt', 'Richiesta rifiutata', 'Request refused');
  static String get ch4Broken => _p('Canal de validation interrompu.', 'Bestätigungskanal unterbrochen.',
      'Canale di conferma interrotto.', 'Approval channel interrupted.');
  static String get ch4Closed => _p('Canal de validation fermé.', 'Bestätigungskanal geschlossen.',
      'Canale di conferma chiuso.', 'Approval channel closed.');
  static String get noApproval => _p('Aucune validation reçue en 130 s.', 'Keine Bestätigung innerhalb von 130 s.',
      'Nessuna conferma ricevuta in 130 s.', 'No approval received within 130 s.');
  static String message(Object n) => _p('message $n', 'Meldung $n', 'messaggio $n', 'message $n');

  /// Texte d'un refus de Qovi connu par son numero (Tip.t[0]), null sinon.
  /// [waits] = valeur de %Waits recue (ex. « 12 s »), vide possible (lot 18, MoB.4).
  static String? tip(int n, String waits) => switch (n) {
        441 => _p('Votre adresse est en cours de validation dans un autre contexte.',
                'Ihre Adresse wird gerade in einem anderen Kontext bestätigt.',
                'Il suo indirizzo è in fase di convalida in un altro contesto.',
                'Your address is being validated in another context.') +
            (waits.isEmpty
                ? ''
                : _p(' Attendez $waits et relancez.', ' Warten Sie $waits und versuchen Sie es erneut.',
                    ' Attenda $waits e riprovi.', ' Wait $waits and try again.')),
        // Lot 23 (Marc 20.11) : 575 = aucun telephone Qovi pret pour ce serveur.
        575 => _p('Aucun téléphone Qovi n’est prêt : ouvrez Qovi sur votre téléphone, vérifiez qu’il est sur le même environnement que DpW (Test ou Production), puis réessayez.',
            'Kein Qovi-Telefon ist bereit: Öffnen Sie Qovi auf Ihrem Telefon, prüfen Sie, dass es dieselbe Umgebung wie DpW verwendet (Test oder Produktion), und versuchen Sie es erneut.',
            'Nessun telefono Qovi è pronto: apra Qovi sul telefono, verifichi che usi lo stesso ambiente di DpW (Test o Produzione) e riprovi.',
            'No Qovi phone is ready: open Qovi on your phone, check that it uses the same environment as DpW (Test or Production), then try again.'),
        _ => null,
      };
  static String dpwDown(String h) => _p('Service DpW injoignable ($h).', 'DpW-Dienst nicht erreichbar ($h).',
      'Servizio DpW non raggiungibile ($h).', 'DpW service unreachable ($h).');
  static String get dpwNoReply => _p('Pas de réponse du service DpW.', 'Keine Antwort vom DpW-Dienst.',
      'Nessuna risposta dal servizio DpW.', 'No answer from the DpW service.');
  static String get keyMissing => _p('Clé du trousseau absente de la réponse.', 'Schlüssel fehlt in der Antwort.',
      'Chiave del portachiavi assente dalla risposta.', 'Keychain key missing from the answer.');
  static String get dpwRefused => _p('Refus du service DpW.', 'Ablehnung durch den DpW-Dienst.',
      'Rifiuto del servizio DpW.', 'Refused by the DpW service.');
  static String dpwRefusedWhy(String s) => _p('Refus du service DpW ($s).', 'Ablehnung durch den DpW-Dienst ($s).',
      'Rifiuto del servizio DpW ($s).', 'Refused by the DpW service ($s).');

  // ── Synchronisation (reseau) ────────────────────────────────────────
  static String get recvInvalid => _p('Trousseau reçu invalide.', 'Empfangener Schlüsselbund ungültig.',
      'Portachiavi ricevuto non valido.', 'Received keychain is invalid.');
  static String get recvUnreadable => _p('Trousseau reçu illisible (clé de session erronée ou bloc altéré).',
      'Empfangener Schlüsselbund unlesbar (falscher Sitzungsschlüssel oder veränderter Block).',
      'Portachiavi ricevuto illeggibile (chiave di sessione errata o blocco alterato).',
      'Received keychain unreadable (wrong session key or altered block).');
  static String get dpwClosed => _p('Le service DpW a fermé la connexion.', 'Der DpW-Dienst hat die Verbindung geschlossen.',
      'Il servizio DpW ha chiuso la connessione.', 'The DpW service closed the connection.');
  static String get qrUsed => _p('QR expiré ou déjà utilisé : relancez la synchronisation.',
      'QR abgelaufen oder bereits verwendet: Synchronisierung neu starten.',
      'QR scaduto o già usato: rilanci la sincronizzazione.', 'QR expired or already used: start the sync again.');
  static String get otherAccount => _p('Les deux appareils ne sont pas ouverts sur le même compte.',
      'Die beiden Geräte sind nicht mit demselben Konto geöffnet.',
      'I due dispositivi non sono aperti sullo stesso account.',
      'The two devices are not open on the same account.');
  static String get sameDevice => _p('Ce QR a été affiché par cet appareil.', 'Dieser QR wurde von diesem Gerät angezeigt.',
      'Questo QR è stato mostrato da questo dispositivo.', 'This QR was shown by this device.');
  static String get unknownDevice => _p('Cet appareil n’est pas reconnu par le service DpW : rouvrez le trousseau.',
      'Dieses Gerät ist dem DpW-Dienst nicht bekannt: Schlüsselbund neu öffnen.',
      'Questo dispositivo non è riconosciuto dal servizio DpW: riapra il portachiavi.',
      'This device is not known to the DpW service: open the keychain again.');
  static String get timeout10 => _p('Délai de 10 minutes dépassé.', 'Zeitlimit von 10 Minuten überschritten.',
      'Tempo limite di 10 minuti superato.', '10-minute time limit exceeded.');
  static String get syncCancelled => _p('Synchronisation annulée.', 'Synchronisierung abgebrochen.',
      'Sincronizzazione annullata.', 'Sync cancelled.');
  static String get notDpwQr => _p('Ce QR n’est pas un QR de synchronisation DpW.', 'Dieser QR ist kein DpW-Synchronisierungs-QR.',
      'Questo QR non è un QR di sincronizzazione DpW.', 'This QR is not a DpW sync QR.');
  static String get dpwIncomplete => _p('Réponse du service DpW incomplète.', 'Antwort des DpW-Dienstes unvollständig.',
      'Risposta del servizio DpW incompleta.', 'Incomplete answer from the DpW service.');

  // ── Trousseau (fichier) ─────────────────────────────────────────────
  static String get notV2 => _p("Ce fichier n'est pas un trousseau DpW v2.", 'Diese Datei ist kein DpW-v2-Schlüsselbund.',
      'Questo file non è un portachiavi DpW v2.', 'This file is not a DpW v2 keychain.');
  static String get wrongKey => _p('Trousseau illisible avec la clé de ce compte (ou fichier modifié).',
      'Schlüsselbund mit dem Schlüssel dieses Kontos unlesbar (oder Datei verändert).',
      'Portachiavi illeggibile con la chiave di questo account (o file modificato).',
      'Keychain unreadable with this account’s key (or file modified).');
  static String get badContent => _p('Contenu du trousseau invalide.', 'Inhalt des Schlüsselbunds ungültig.',
      'Contenuto del portachiavi non valido.', 'Invalid keychain content.');

  // ── W14 (lot 20) : photo de carte ───────────────────────────────────
  static String get card => _p('Carte', 'Karte', 'Carta', 'Card');
  static String get cardShow => _p('Afficher la carte', 'Karte anzeigen', 'Mostra la carta', 'Show the card');
  static String get cardFront => _p('Recto', 'Vorderseite', 'Fronte', 'Front');
  static String get cardBack => _p('Verso', 'Rückseite', 'Retro', 'Back');
  static String get cardShootFront => _p('Photographier le recto', 'Vorderseite fotografieren',
      'Fotografa il fronte', 'Photograph the front');
  static String get cardShootBack => _p('Photographier le verso', 'Rückseite fotografieren',
      'Fotografa il retro', 'Photograph the back');
  static String get cardRetake => _p('Reprendre la photo', 'Foto neu aufnehmen', 'Rifai la foto', 'Retake the photo');
  static String get cardDelete => _p('Supprimer la photo', 'Foto löschen', 'Elimina la foto', 'Delete the photo');
  static String get cardDelAsk => _p('Supprimer cette photo ?', 'Dieses Foto löschen?', 'Eliminare questa foto?',
      'Delete this photo?');
  static String get cardElsewhere => _p('Photo prise sur un autre appareil.', 'Foto auf einem anderen Gerät aufgenommen.',
      'Foto scattata su un altro dispositivo.', 'Photo taken on another device.');
  static String get cardUnreadable => _p('Photo illisible.', 'Foto unlesbar.', 'Foto illeggibile.', 'Unreadable photo.');
  static String cardSaveFail(Object e) => _p('Photo non enregistrée : $e', 'Foto nicht gespeichert: $e',
      'Foto non salvata: $e', 'Photo not saved: $e');
  static String get camHint => _p('Placez la carte dans le cadre.', 'Legen Sie die Karte in den Rahmen.',
      'Metta la carta nella cornice.', 'Place the card inside the frame.');
  static String get camShoot => _p('Prendre la photo', 'Foto aufnehmen', 'Scatta la foto', 'Take the photo');
  static String get camNone => _p('Aucune caméra disponible.', 'Keine Kamera verfügbar.',
      'Nessuna fotocamera disponibile.', 'No camera available.');
  static String camFail(Object e) => _p('Caméra : $e', 'Kamera: $e', 'Fotocamera: $e', 'Camera: $e');
  static String get linesHint => _p('Rond : incliner la droite. Milieu : la déplacer. Touchez la carte pour valider.',
      'Kreis: Linie neigen. Mitte: verschieben. Karte antippen zum Bestätigen.',
      'Cerchio: inclina la linea. Centro: spostala. Tocchi la carta per confermare.',
      'Dot: tilt the line. Middle: move it. Tap the card to confirm.');
  static String get cornersOk => _p('Valider', 'Bestätigen', 'Conferma', 'Confirm');
}
