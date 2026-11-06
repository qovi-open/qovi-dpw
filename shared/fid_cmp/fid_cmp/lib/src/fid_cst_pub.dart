// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// fid_cst_pub.dart — Constantes publiques partagées (SiT/App/MoB/Srv)
// DÉPLACÉ le 13.07.2026 depuis ser/qfa_pub_srv/.../src/fid_cst_pub.dart vers
// fid_cmp (déjà annoncé dans le commentaire d'origine : "Destiné à un futur
// package shared/fid_cst/ importable par tous les projets") — nécessaire
// pour que qfa_mob accède à k_Login_ic/k_Pairing_ic/k_Alone_ic (routage
// Ident, voir mob_ident.dart).
// Port de _Cst.wl — section "gestion des erreurs"

const String Who_Log_uc  = '245a59e6-bdc5-4a58-8812-c274d7a04c53'; // Who bidon — pas encore connu
const String Who_Fid_uc  = '3cbb1672-e12e-433b-ad9d-6f6fd78f6fef'; // ch.qfa@... (marque blanche Fidelio)
const String Who_Fail_uc = '145a59e6-bdc5-4a58-8812-c274d7a04c53'; // Who bidon — contexte Fail_xxx

// Messages "erreur interne" multilingues (index 0=us,1=fr,2=de,3=it,4=es —
// aligné sur Spk_i 1-indexé WL : Fail_5ts[Spk_i - 1] en Dart)
// Format Score : c3_ titre, c0_ corps, r_ lien hotline, %1/%2 substitutions
const List<String> Fail_5ts = [
  'c3_Internal error\nc0_code for hotline\nr_hotline@%2\nc6_%1',
  'c3_Erreur interne\nc0_code pour la hotline\nr_hotline@%2\nc6_%1',
  'c3_Interner Fehler\nc0_Code für die Hotline\nr_hotline@%2\nc6_%1',
  "c3_Errore interno\nc0_codice per l'hotline\nr_hotline@%2\nc6_%1",
  'c3_Error interno\nc0_código para la línea directa\nr_hotline@%2\nc6_%1',
];

// Domaine principal — pourra changer, à terme candidat pour la config plutôt
// qu'une constante figée (TODO : déplacer vers config/*.yaml si besoin)
const String QfA_Dom_sc = 'qovi.ch';

// Classe des clés — port de _Cst.wl (section "Classe des clés")
const int k_Pairing_ic = 1; // Validation du rajout d'un nouvel Email dans le mobile
const int k_Login_ic   = 2; // Valide les demandes de login d'un site web
const int k_Alone_ic   = 3; // Valide les demandes de login d'un site via une App mobile
const int k_OfL_ic     = 10; // Authentification sans connexion réseau
const int k_Gen_Chk_ic = 9;  // Verifie l'existence d'une cle generique (fallback si type inconnu)
const int k_x_ic       = 11; // Père de la classe

// ─────────────────────────────────────────────────────────────────────────
// PROTOCOLE DE VOTE Go.i — CENTRALISÉ ICI le 15.07.2026
// ─────────────────────────────────────────────────────────────────────────
// Ces valeurs vivaient jusqu'ici en constantes PRIVÉES dupliquées dans
// TROIS fichiers (mob_shell.dart, s_clic_up_x.dart, s_pair_up_x.dart) —
// exactement le motif qui a produit le bug de la colonne `es` (une valeur
// qui vit à plusieurs endroits finit par diverger en silence). Un seul
// endroit désormais.
//
// ⚠️ COLLISION AVEC LES Vote_*_ic DU WL — À LIRE AVANT DE TOUCHER À ÇA ⚠️
//
// `Fid_Pub.txt` (fourni le 15.07.2026) donne enfin les VRAIES valeurs WL :
//     Vote_O_ic =  2   // Vote ouvert, pas encore de prise de position
//     Vote_Y_ic =  1   // Oui
//     Vote_B_ic =  0   // Blanc
//     Vote_N_ic = -1   // Non
//     Vote_A_ic = -2   // Abandon/Abstention ET informe le PuB
//     Vote_E_ic = -3   // Fin normale du workflow SANS informer le PuB
//
// Le protocole Go.i ci-dessous a été inventé le 13.07.2026 SANS ces
// valeurs sous les yeux. Résultat : 1/0/-1 coïncident, mais **-2 et -3
// veulent dire autre chose en WL qu'en Dart** :
//     -2 : Dart = Spam            | WL = Vote_A (Abandon, informe le PuB)
//     -3 : Dart = Home/Abandon    | WL = Vote_E (fin sans informer le PuB)
//
// CE N'EST PAS UN BUG, et il n'y a AUCUN risque d'interopérabilité —
// `k_Access_x.txt` (WL) montre que le MoB WL ne met JAMAIS -2 ni -3 sur le
// fil : Vote_A/Vote_B/Vote_N sont tous écrasés en Vote_N avant l'envoi, et
// Vote_E n'envoie rien du tout. **Le fil WL ne transporte que 1 ou -1.**
// C'est d'ailleurs ce qui explique le SWITCH de `s_Pair_Up_x` : recevoir un
// Vote_B ou un Vote_E est une anomalie *par construction*, puisqu'ils ne
// peuvent pas légitimement arriver.
//
// Le protocole Dart est donc un ENRICHISSEMENT assumé (Spam et Home portent
// une vraie information jusqu'au PuB, ce que WL ne fait pas), déjà validé
// sur appareil réel le 13.07.2026. On le garde. Le seul vrai danger est
// qu'un jour quelqu'un ajoute `Vote_A_ic = -2` à côté de `Go_Spam_ic = -2`
// et les mélange : c'est pour ça que les Vote_*_ic restent en commentaire
// ci-dessus et NE SONT PAS déclarés. Si un portage en a besoin un jour,
// qu'il les déclare dans son propre fichier, jamais ici.
//
// Sémantique Dart (voir RoadDev §11 et s_clic_up_x.dart) :
const int Go_Oui_ic     = 1;  // Vote réel — compte, busy-free GARDE Prv_Act_uk
const int Go_Blanc_ic   = 0;  // Vote réel — compte, busy-free GARDE Prv_Act_uk
const int Go_Non_ic     = -1; // Vote réel — compte, busy-free GARDE Prv_Act_uk
const int Go_Spam_ic    = -2; // Pas un vote (aucun PIN) mais COMPTE comme un Non ;
                              // busy-free MET Prv_Act_uk=null. Jamais renvoyé
                              // tel quel au site demandeur (mappé à -1).
const int Go_Abandon_ic = -3; // Home — PAS un vote, NE compte PAS, busy-free
                              // MET Prv_Act_uk=null, rien n'est diffusé.

// ─────────────────────────────────────────────────────────────────────────
// NIVEAU D'IDENTIFICATION EXIGÉ CÔTÉ MoB (Qrc_i / keys.SiT_Ident_i3)
// ─────────────────────────────────────────────────────────────────────────
// Valeurs RÉELLES WL, confirmées par `Fid_Pub.txt` (15.07.2026).
const int Aut_But_ic = 1; // Simple validation bouton — ni PIN ni Bio
const int Aut_Pin_ic = 2; // Impose la saisie du PIN code
const int Aut_Bio_ic = 3; // Impose faciale ou empreinte
const int Aut_Top_ic = 4; // Présent dans Fid_Pub.txt, usage inconnu — voir RoadDev

/// Ramène `keys.SiT_Ident_i3` à une valeur EXPLOITABLE.
///
/// ── POURQUOI CETTE FONCTION EXISTE (bug trouvé le 15.07.2026) ─────────
/// Trois fichiers serveur écrivaient `(row['SiT_Ident_i3'] as int?) ?? 2`,
/// croyant se protéger. Or `information_schema` dit :
///     whos.SiT_Ident_i3 | smallint | NOT NULL | DEFAULT 0
/// La colonne n'est JAMAIS nulle -> le `??` ne se déclenche JAMAIS. Et 0
/// n'est pas un Ident valide (le domaine est 1..3). Déroulé complet d'un 0 :
///     qrcEncode(identI3: 0)  -> String.fromCharCode(32) = espace
///     MoB: qrcDecode         -> identI3 = 0
///     mob_shell._vote()      -> needsPin = (0==Pin)||(0==Bio) = false
///     -> VOTE ENVOYÉ SANS PIN, en silence.
/// Un `??` ne teste que la nullité ; il fallait tester le DOMAINE.
///
/// Repli sur **PIN** et jamais sur Bouton, y compris pour un login : un
/// login raté se refait, un appairage raté donne un accès permanent. C'est
/// aussi le garde-fou du WL lui-même (`o_Mob_Pair_End_x` : `QRc_j.i = 2 //
/// Impose le PIN code` armé AVANT tout test).
int identSafe_i3(Object? raw) {
  final v = raw is int ? raw : null;
  if (v == null || v < Aut_But_ic || v > Aut_Bio_ic) return Aut_Pin_ic;
  return v;
}

// Nombre max d'essais du PIN avant reset de la DB du mobile — valeur RÉELLE
// WL, confirmée par `Fid_Pub.txt` le 15.07.2026 (`Pref_PIN_Trial_ic = 3`).
// Le placeholder posé à 3 dans mob_ctx.dart le 13.07 était juste : le TODO
// est levé, la valeur ne change pas.
const int Pref_PIN_Trial_ic = 3;


// UID des types de clé (identifiants publics du type, pas la clé elle-même)
const String U128c = '00000000-0000-0000-0000-000000000000';
const String U256c = '0000000000000000000000000000000000000000000000000000000000000000';
const String k_Login_Uc   = '6a9e175844d0ef2012fe7848af6c1924f1eb22fee7ac1ee8a589427c72e83613';
const String k_Alone_Uc   = '9f910f6f83725101eecb01ee034025daba6a2947fe33be4424376e0256c5d46c';
const String k_Pairing_uc = '061a312923c080d156c006a8083e06c75d5ae30919f9b7d559f2ef48971fcded';
const String k_OfL_Uc     = 'b910ae5d17d9d0a4391c833711b8237277e57fb991f0d0f9378a024fbcccdd15';

// Translation de l'UID d'un type de clé vers son No de classe interne
// Port de Pub_ti3 (WL, tableau associatif global)
const Map<String, int> Pub_ti3 = {
  k_Login_Uc: k_Login_ic,
  k_Alone_Uc: k_Alone_ic,
  k_Pairing_uc: k_Pairing_ic,
  k_OfL_Uc: k_OfL_ic,
};

// Validation d'un UID 256 bits (64 caractères hexadécimaux) — port de _U256_b
// Simplifié : WL affecte aussi Us=v en sortie, superflu ici (v déjà validé).
bool u256_b(String v) {
  if (v.length != 64) return false;
  return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(v);
}
