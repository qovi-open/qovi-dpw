// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER MainActivity.kt · 2026-11-20 · lot 28 (canal dpw/qovi ; lot 27 : W17 retour a l'app d'origine ; lot 25 : dpw/autofill ; lot 21 : W15)
package ch.qovi.qfa_dpw

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // W17 (lot 25) : canal du remplissage automatique (voir AutofillActivity).
    private var fillCh: MethodChannel? = null

    // W15 (lot 21, decision de Marc 19.11) : ecran protege. Pas de capture ni
    // d'enregistrement d'ecran, et l'apercu de la liste des apps recentes est
    // noir : un mot de passe ou une carte affiches ne fuient pas par la.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // W14 (lot 20) : « bright » true = luminosite de la fenetre au maximum
        // (pour qu'un lecteur lise le QR de la carte), false = reglage du telephone.
        // Seulement la fenetre de DpW : le reglage du systeme n'est pas touche.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dpw/screen").setMethodCallHandler { call, result ->
            if (call.method == "bright") {
                val on = call.arguments as? Boolean ?: false
                val lp = window.attributes
                lp.screenBrightness = if (on) 1f else WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                window.attributes = lp
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        // Lot 28 : has = Qovi installe sur ce telephone ; open = le lancer
        // (premier plan : il se connecte, DpW relance le login au retour).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dpw/qovi").setMethodCallHandler { call, result ->
            val i = packageManager.getLaunchIntentForPackage(QOVI)
            when (call.method) {
                "has" -> result.success(i != null)
                "open" -> result.success(
                    if (i == null) false else try {
                        startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        true
                    } catch (e: Exception) {
                        false
                    })
                else -> result.notImplemented()
            }
        }
        // W17 (lot 25) : pending = demande en attente ; fill = fiche choisie
        // (part vers l'app d'origine, DpW se retire) ; cancel = abandon ;
        // settings = page Android du service de saisie automatique.
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dpw/autofill")
        fillCh = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "pending" -> result.success(FillHub.pending)
                "fill", "cancel" -> {
                    val who = if (call.method == "fill") call.argument<String>("who") ?: "" else null
                    val pass = if (call.method == "fill") call.argument<String>("pass") ?: "" else null
                    // Lot 27 (essai de Marc 20.11) : DpW ferme, la fiche choisie ramenait
                    // a Qovi (derniere app avant DpW, a cause de l'ouverture). On ramene
                    // donc explicitement la tache de l'app d'origine (Chrome, Migros...).
                    val origin = if (Build.VERSION.SDK_INT >= 26) AutofillActivity.current?.taskId else null
                    FillHub.pending = null
                    if (Build.VERSION.SDK_INT >= 26) AutofillActivity.current?.deliver(who, pass)
                    if (!backTo(origin)) moveTaskToBack(true)
                    result.success(null)
                }
                "settings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 26) {
                            startActivity(Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE, Uri.parse("package:$packageName")))
                        }
                    } catch (e: Exception) {
                        // page absente sur ce telephone : rien
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        /// Lot 28 : paquet de l'app Qovi (Test et Production).
        const val QOVI = "ch.wippso.qfa.mob"
    }

    /// Lot 27 : remet au premier plan la tache [task] (celle de l'app a remplir).
    /// false si impossible : l'appelant se contente alors de reculer DpW.
    private fun backTo(task: Int?): Boolean {
        if (task == null || task == taskId) return false
        return try {
            (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).moveTaskToFront(task, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    // W17 : DpW deja ouvert, Android le ramene pour une nouvelle demande.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(AutofillActivity.EX_FILL, false)) {
            fillCh?.invokeMethod("request", FillHub.pending)
        }
    }
}
