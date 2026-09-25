package mx.vaquita.vaquita_mx

import android.Manifest
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.vaquita.vaquita_mx/contacts").setMethodCallHandler { call, result ->
            if (call.method != "getPhoneNumbers") { result.notImplemented(); return@setMethodCallHandler }
            if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                pendingResult = result
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CONTACTS), 7)
            } else result.success(phoneNumbers())
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7) {
            val result = pendingResult ?: return
            pendingResult = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) result.success(phoneNumbers()) else result.error("denied", "Contacts permission was denied", null)
        }
    }

    private fun phoneNumbers(): List<String> {
        val phones = linkedSetOf<String>()
        contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) phones.add(cursor.getString(0))
        }
        return phones.toList()
    }
}
