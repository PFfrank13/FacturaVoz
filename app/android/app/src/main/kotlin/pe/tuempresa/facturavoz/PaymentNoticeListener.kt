package pe.tuempresa.facturavoz

import android.app.Notification
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Avisos de pago automáticos (docs/INVESTIGACION_RETAIL.md, fila 1): lee SOLO las notificaciones de Yape y de
 * las apps bancarias con Plin, y solo las de dinero recibido. Todo se procesa en el teléfono; la app guarda el
 * aviso en «Avisos de Yape y Plin» de la empresa. El dueño activa el permiso a mano y lo puede quitar cuando quiera.
 */
class PaymentNoticeListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        // En una compilación de prueba también se aceptan avisos simulados con «adb shell cmd notification post».
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val watched = WATCHED.contains(pkg) || (debuggable && pkg == "com.android.shell")
        if (!watched) return
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        val body = "$title $text".trim()
        if (!isIncomingPayment(body)) return
        PaymentNoticeStore.add(applicationContext, "${sbn.key}|${body.hashCode()}", pkg, body.take(500), sbn.postTime)
    }

    companion object {
        /** Yape, BCP y los bancos que integran Plin (Interbank, BBVA, Scotiabank). */
        val WATCHED = setOf(
            "com.bcp.innovacxion.yapeapp",
            "com.bcp.bank.bcp",
            "pe.com.interbank.mobilebanking",
            "com.bbva.nxt_peru",
            "pe.com.scotiabank.blpm.android.client",
        )
        private val money = Regex("""S/\.?\s*\d""", RegexOption.IGNORE_CASE)
        private val incoming = Regex("""te\s+(envi|yape|pag|transfiri)|recibiste|has recibido|abono|te depositaron""", RegexOption.IGNORE_CASE)

        /** Solo dinero que entra: «Juan te envió un pago por S/ 10». No lee pagos que hace el dueño. */
        fun isIncomingPayment(body: String): Boolean = money.containsMatchIn(body) && incoming.containsMatchIn(body)
    }
}

/** Cola local (máx. 50) hasta que la app la lee; se descartan repetidos por clave. */
object PaymentNoticeStore {
    private const val PREFS = "fv_payment_notices"
    private const val KEY = "queue"
    private val main = Handler(Looper.getMainLooper())
    @Volatile var onNotice: ((Map<String, Any>) -> Unit)? = null

    @Synchronized
    fun add(context: Context, key: String, pkg: String, text: String, at: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(KEY, "[]"))
        for (i in 0 until queue.length()) if (queue.getJSONObject(i).optString("key") == key) return
        val item = JSONObject().put("key", key).put("pkg", pkg).put("text", text).put("at", at)
        queue.put(item)
        val trimmed = JSONArray()
        val from = maxOf(0, queue.length() - 50)
        for (i in from until queue.length()) trimmed.put(queue.get(i))
        prefs.edit().putString(KEY, trimmed.toString()).apply()
        val map = mapOf<String, Any>("key" to key, "pkg" to pkg, "text" to text, "at" to at)
        main.post { onNotice?.invoke(map) }
    }

    /** Devuelve y vacía la cola. */
    @Synchronized
    fun drain(context: Context): List<Map<String, Any>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(KEY, "[]"))
        prefs.edit().putString(KEY, "[]").apply()
        return (0 until queue.length()).map { i ->
            val o = queue.getJSONObject(i)
            mapOf("key" to o.optString("key"), "pkg" to o.optString("pkg"), "text" to o.optString("text"), "at" to o.optLong("at"))
        }
    }
}
