// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Marc Gandar
// FILEVER AutofillActivity.kt · 2026-11-20 · lot 25 (W17 : relais entre Android et l'ecran de DpW)
// W17 : activite invisible, lancee par Android quand l'usager touche « Remplir
// avec Qovi DpW ». Elle reste dans la tache de l'app d'origine, ouvre DpW
// (MainActivity, meme moteur Flutter, donc meme trousseau deverrouille), puis
// attend la fiche choisie : elle rend alors a Android un jeu de valeurs
// (utilisateur, mot de passe ; "" si un champ de la fiche est vide) et se ferme.
// Si l'usager revient en arriere dans DpW, elle se ferme sans rien remplir.
package ch.qovi.qfa_dpw

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import android.annotation.TargetApi

/// Demande en cours, lue par Flutter (canal dpw/autofill, « pending »).
object FillHub {
    @Volatile var pending: HashMap<String, String>? = null
}

@TargetApi(Build.VERSION_CODES.O)
class AutofillActivity : Activity() {
    private var userIds: ArrayList<AutofillId> = arrayListOf()
    private var passIds: ArrayList<AutofillId> = arrayListOf()
    private var done = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        userIds = ids(EX_USER)
        passIds = ids(EX_PASS)
        val req = hashMapOf(
            "pkg" to (intent.getStringExtra(EX_PKG) ?: ""),
            "web" to (intent.getStringExtra(EX_WEB) ?: ""),
        )
        current?.deliver(null, null) // une ancienne demande est abandonnee
        current = this
        FillHub.pending = req
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra(EX_FILL, true))
    }

    @Suppress("DEPRECATION")
    private fun ids(key: String): ArrayList<AutofillId> =
        (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(key, AutofillId::class.java)
        else intent.getParcelableArrayListExtra<AutofillId>(key)) ?: arrayListOf()

    /// [who] null = abandon. Sinon les valeurs partent vers l'app d'origine.
    fun deliver(who: String?, pass: String?) {
        if (done) return
        done = true
        if (who == null) {
            setResult(RESULT_CANCELED)
        } else {
            // presentation exigee par Android, jamais affichee (le remplissage est immediat)
            val pres = RemoteViews(packageName, android.R.layout.simple_list_item_1)
            @Suppress("DEPRECATION")
            val b = Dataset.Builder(pres)
            for (id in userIds) b.setValue(id, AutofillValue.forText(who))
            for (id in passIds) b.setValue(id, AutofillValue.forText(pass ?: ""))
            val r = Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, b.build())
            setResult(RESULT_OK, r)
        }
        finish()
    }

    override fun onDestroy() {
        if (current === this) {
            current = null
            FillHub.pending = null
        }
        super.onDestroy()
    }

    companion object {
        const val EX_PKG = "dpw_fill_pkg"
        const val EX_WEB = "dpw_fill_web"
        const val EX_USER = "dpw_fill_user"
        const val EX_PASS = "dpw_fill_pass"
        const val EX_FILL = "dpw_fill"
        @Volatile var current: AutofillActivity? = null
    }
}
