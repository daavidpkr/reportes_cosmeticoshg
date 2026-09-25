package com.example.reportes_cosmeticoshg

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private data class PendingDownload(
        val call: MethodCall,
        val result: MethodChannel.Result,
    )

    private var pendingDownload: PendingDownload? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.reportes_cosmeticoshg/notification_settings",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openNotificationSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            try {
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ),
                )
            }
            result.success(null)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.reportes_cosmeticoshg/document_downloads",
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveDocument") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                if (pendingDownload != null) {
                    result.error(
                        "download_busy",
                        "Ya hay un documento esperando permiso de almacenamiento.",
                        null,
                    )
                    return@setMethodCallHandler
                }
                pendingDownload = PendingDownload(call, result)
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    DOWNLOAD_PERMISSION_REQUEST,
                )
                return@setMethodCallHandler
            }
            saveDocument(call, result)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != DOWNLOAD_PERMISSION_REQUEST) return
        val pending = pendingDownload ?: return
        pendingDownload = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveDocument(pending.call, pending.result)
        } else {
            pending.result.error(
                "storage_permission_denied",
                "Se necesita permiso de almacenamiento para guardar en Descargas en esta versión de Android.",
                null,
            )
        }
    }

    private fun saveDocument(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val requestedName = call.argument<String>("fileName")?.trim().orEmpty()
        val mimeType = call.argument<String>("mimeType")?.trim().orEmpty()
        if (bytes == null || bytes.isEmpty() || requestedName.isEmpty() || mimeType.isEmpty()) {
            result.error("invalid_document", "El documento, nombre o tipo MIME no es válido.", null)
            return
        }
        val safeName = File(requestedName).name
        if (safeName != requestedName) {
            result.error("invalid_name", "El nombre del documento no es válido.", null)
            return
        }

        Thread {
            try {
                val savedName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(bytes, safeName, mimeType)
                } else {
                    saveLegacy(bytes, safeName)
                }
                runOnUiThread {
                    result.success(
                        mapOf(
                            "name" to savedName,
                            "location" to "Descargas/$savedName",
                        ),
                    )
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "document_write_failed",
                        "No se pudo escribir el archivo en Descargas: ${error.message ?: "error desconocido"}",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun saveWithMediaStore(
        bytes: ByteArray,
        requestedName: String,
        mimeType: String,
    ): String {
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/Descargas/"
        val savedName = uniqueMediaStoreName(requestedName, relativePath)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, savedName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Android no pudo crear el archivo.")
        try {
            resolver.openOutputStream(uri, "w")?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("Android no pudo abrir el archivo para escritura.")
            val updated = resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            if (updated != 1) {
                throw IllegalStateException("Android no confirmó la publicación del archivo.")
            }
            return savedName
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun uniqueMediaStoreName(requestedName: String, relativePath: String): String {
        var candidate = requestedName
        var suffix = 1
        while (mediaStoreNameExists(candidate, relativePath)) {
            candidate = suffixedName(requestedName, suffix++)
        }
        return candidate
    }

    private fun mediaStoreNameExists(name: String, relativePath: String): Boolean {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection =
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            arrayOf(relativePath, name),
            null,
        )?.use { cursor -> return cursor.moveToFirst() }
        return false
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(bytes: ByteArray, requestedName: String): String {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Descargas",
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("No se pudo crear Download/Descargas.")
        }
        var file = File(directory, requestedName)
        var suffix = 1
        while (file.exists()) file = File(directory, suffixedName(requestedName, suffix++))
        try {
            FileOutputStream(file).use { stream ->
                stream.write(bytes)
                stream.flush()
            }
        } catch (error: Exception) {
            file.delete()
            throw error
        }
        return file.name
    }

    private fun suffixedName(name: String, suffix: Int): String {
        val dot = name.lastIndexOf('.')
        return if (dot > 0) {
            "${name.substring(0, dot)} ($suffix)${name.substring(dot)}"
        } else {
            "$name ($suffix)"
        }
    }

    companion object {
        private const val DOWNLOAD_PERMISSION_REQUEST = 7102
    }
}
