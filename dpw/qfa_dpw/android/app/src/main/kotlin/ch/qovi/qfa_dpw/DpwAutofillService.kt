// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER DpwAutofillService.kt · 2026-11-20 · lot 25 (W17 : remplissage automatique Android)
// W17 (decisions de Marc 20.11) : quand l'usager touche un champ de connexion
// dans une autre app ou un navigateur, Android demande a DpW ce qu'il propose.
// DpW ne lit JAMAIS le contenu des champs : il repere seulement les champs
// « utilisateur » et « mot de passe » (indices, type de saisie, attributs
// HTML, noms), et propose UNE ligne « Remplir avec DpW », verrouillee : la
// toucher ouvre DpW (AutofillActivity -> MainActivity), ou l'usager choisit la
// fiche apres la validation Qovi habituelle. Aucune valeur n'est donnee ici.
package ch.qovi.qfa_dpw

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import android.annotation.TargetApi
import java.util.Locale

@TargetApi(Build.VERSION_CODES.O)
class DpwAutofillService : AutofillService() {

    private class Fields {
        val user = ArrayList<AutofillId>()
        val pass = ArrayList<AutofillId>()
        var lastText: AutofillId? = null
        var web: String? = null
    }

    private enum class Kind { USER, PASS, OTHER }

    override fun onFillRequest(request: FillRequest, cancellationSignal: CancellationSignal, callback: FillCallback) {
        try {
            val st = request.fillContexts.lastOrNull()?.structure
            val pkg = st?.activityComponent?.packageName ?: ""
            if (st == null || pkg.isEmpty() || pkg == packageName) {
                callback.onSuccess(null)
                return
            }
            val f = Fields()
            for (i in 0 until st.windowNodeCount) walk(st.getWindowNodeAt(i).rootViewNode, f)
            if (f.pass.isEmpty() && f.user.isEmpty()) {
                callback.onSuccess(null)
                return
            }
            val pres = RemoteViews(packageName, android.R.layout.simple_list_item_1)
            pres.setTextViewText(android.R.id.text1, label())
            val intent = Intent(this, AutofillActivity::class.java).apply {
                putExtra(AutofillActivity.EX_PKG, pkg)
                putExtra(AutofillActivity.EX_WEB, f.web ?: "")
                putParcelableArrayListExtra(AutofillActivity.EX_USER, f.user)
                putParcelableArrayListExtra(AutofillActivity.EX_PASS, f.pass)
            }
            var flags = PendingIntent.FLAG_CANCEL_CURRENT
            if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
            val pi = PendingIntent.getActivity(this, nextCode(), intent, flags)
            @Suppress("DEPRECATION")
            val ds = Dataset.Builder(pres)
            for (id in f.user) ds.setValue(id, null)
            for (id in f.pass) ds.setValue(id, null)
            ds.setAuthentication(pi.intentSender)
            callback.onSuccess(FillResponse.Builder().addDataset(ds.build()).build())
        } catch (e: Exception) {
            // jamais d'exception vers l'app de l'usager : on ne propose rien
            callback.onSuccess(null)
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // DpW n'enregistre rien depuis une autre app (les fiches se creent dans DpW).
        callback.onSuccess()
    }

    private fun walk(n: AssistStructure.ViewNode, f: Fields) {
        if (f.web == null && !n.webDomain.isNullOrEmpty()) f.web = n.webDomain
        val id = n.autofillId
        if (id != null && n.autofillType == View.AUTOFILL_TYPE_TEXT && n.visibility == View.VISIBLE) {
            when (kind(n)) {
                Kind.PASS -> {
                    // Pas de champ utilisateur repere : celui juste avant le mot de passe.
                    if (f.user.isEmpty() && f.lastText != null) f.user.add(f.lastText!!)
                    if (!f.pass.contains(id)) f.pass.add(id)
                }
                Kind.USER -> if (!f.user.contains(id)) f.user.add(id)
                Kind.OTHER -> f.lastText = id
            }
        }
        for (i in 0 until n.childCount) walk(n.getChildAt(i), f)
    }

    private fun kind(n: AssistStructure.ViewNode): Kind {
        val hints = n.autofillHints?.map { it.lowercase(Locale.ROOT) } ?: emptyList()
        if (hints.any { it.contains("password") }) return Kind.PASS
        if (hints.any { it.contains("username") || it.contains("email") }) return Kind.USER
        val t = n.inputType
        val cls = t and InputType.TYPE_MASK_CLASS
        val v = t and InputType.TYPE_MASK_VARIATION
        if (cls == InputType.TYPE_CLASS_TEXT && (v == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                v == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD || v == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)) {
            return Kind.PASS
        }
        if (cls == InputType.TYPE_CLASS_NUMBER && v == InputType.TYPE_NUMBER_VARIATION_PASSWORD) return Kind.PASS
        var htmlType = ""
        var htmlName = ""
        n.htmlInfo?.attributes?.forEach { a ->
            when (a.first?.lowercase(Locale.ROOT)) {
                "type" -> htmlType = a.second?.lowercase(Locale.ROOT) ?: ""
                "name", "id", "autocomplete" -> htmlName += " " + (a.second?.lowercase(Locale.ROOT) ?: "")
            }
        }
        if (htmlType == "password") return Kind.PASS
        if (htmlType == "email") return Kind.USER
        if (cls == InputType.TYPE_CLASS_TEXT && (v == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
                v == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS)) {
            return Kind.USER
        }
        val words = ((n.idEntry ?: "") + " " + (n.hint ?: "") + htmlName).lowercase(Locale.ROOT)
        if (listOf("pass", "pwd", "mot de passe", "kennwort").any { words.contains(it) }) return Kind.PASS
        if (listOf("user", "login", "mail", "identifiant", "benutzer", "utente", "account").any { words.contains(it) }) {
            return Kind.USER
        }
        return Kind.OTHER
    }

    private fun label(): String = when (Locale.getDefault().language) {
        "fr" -> "Remplir avec Qovi DpW"
        "de" -> "Mit Qovi DpW ausfüllen"
        "it" -> "Compila con Qovi DpW"
        else -> "Fill with Qovi DpW"
    }

    companion object {
        private var code = 0
        @Synchronized
        private fun nextCode(): Int {
            code = (code + 1) and 0xFFFF
            return code
        }
    }
}
