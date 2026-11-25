package mx.vaquita.vaquita_mx

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingMethod: String? = null
    private var deepLinkChannel: MethodChannel? = null
    private var initialDeepLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (initialDeepLink == null) {
            initialDeepLink = intent?.dataString
        }
        deepLinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.vaquita.vaquita_mx/deep_links").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getInitialLink") {
                    val link = initialDeepLink
                    initialDeepLink = null
                    result.success(link)
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.vaquita.vaquita_mx/contacts").setMethodCallHandler { call, result ->
            if (call.method != "getPhoneNumbers" && call.method != "getContacts") { result.notImplemented(); return@setMethodCallHandler }
            if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                pendingResult = result
                pendingMethod = call.method
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CONTACTS), 7)
            } else complete(result, call.method)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString
        if (!link.isNullOrBlank()) {
            deepLinkChannel?.invokeMethod("onDeepLink", link)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7) {
            val result = pendingResult ?: return
            pendingResult = null
            val method = pendingMethod
            pendingMethod = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && method != null) complete(result, method) else result.error("denied", "Contacts permission was denied", null)
        }
    }

    private fun complete(result: MethodChannel.Result, method: String) {
        if (method == "getContacts") result.success(contacts()) else result.success(phoneNumbers())
    }

    private fun phoneNumbers(): List<String> {
        val phones = linkedSetOf<String>()
        contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) phones.add(cursor.getString(0))
        }
        return phones.toList()
    }

    private fun contacts(): List<Map<String, String>> {
        val contacts = linkedMapOf<String, String>()
        contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            ),
            null,
            null,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(0)?.trim().orEmpty()
                val phone = cursor.getString(1)?.trim().orEmpty()
                if (name.isNotEmpty() && phone.isNotEmpty()) contacts.putIfAbsent(phone, name)
            }
        }
        return contacts.map { mapOf("name" to it.value, "phone" to it.key) }
    }
}
