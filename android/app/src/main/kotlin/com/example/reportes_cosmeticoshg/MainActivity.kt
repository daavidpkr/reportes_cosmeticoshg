package com.example.reportes_cosmeticoshg

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private data class PendingDownload(
        val call: MethodCall,
        val result: MethodChannel.Result,
    )

    private var pendingDownload: PendingDownload? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        cleanupInstalledUpdates()
        super.onCreate(savedInstanceState)
    }

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.reportes_cosmeticoshg/updates",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installedVersion" -> result.success(
                    mapOf(
                        "version" to installedPackageInfo().versionName.orEmpty(),
                        "build" to packageBuild(installedPackageInfo()),
                    ),
                )
                "prepareDownload" -> prepareUpdateDownload(call, result)
                "validateApk" -> validateUpdateApk(call, result)
                "canInstallPackages" -> result.success(canInstallPackages())
                "requestInstallPermission" -> requestInstallPermission(result)
                "installApk" -> installUpdateApk(call, result)
                else -> result.notImplemented()
            }
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

    private fun installedPackageInfo() = packageManager.getPackageInfo(
        packageName,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        },
    )

    @Suppress("DEPRECATION")
    private fun packageBuild(info: android.content.pm.PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    private fun prepareUpdateDownload(call: MethodCall, result: MethodChannel.Result) {
        val build = call.argument<Int>("build")
        if (build == null || build.toLong() <= packageBuild(installedPackageInfo())) {
            result.error("invalid_update_build", "La actualización debe tener un build superior.", null)
            return
        }
        val directory = updateDirectory()
        if (!directory.exists() && !directory.mkdirs()) {
            result.error("update_directory", "No se pudo preparar la carpeta segura.", null)
            return
        }
        result.success(directory.absolutePath)
    }

    private fun validateUpdateApk(call: MethodCall, result: MethodChannel.Result) {
        val file = verifiedUpdateFile(call.argument<String>("path"))
        val expectedBuild = call.argument<Int>("build")?.toLong()
        val expectedVersion = call.argument<String>("version")
        if (file == null || expectedBuild == null || expectedVersion.isNullOrBlank()) {
            result.success(false)
            return
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        @Suppress("DEPRECATION")
        val archive = packageManager.getPackageArchiveInfo(file.absolutePath, flags)
        val installed = installedPackageInfo()
        val valid = archive != null &&
            archive.packageName == packageName &&
            packageBuild(archive) == expectedBuild &&
            packageBuild(archive) > packageBuild(installed) &&
            archive.versionName == expectedVersion &&
            compareVersions(expectedVersion, installed.versionName.orEmpty()) >= 0 &&
            packageSignatures(archive).isNotEmpty() &&
            packageSignatures(archive).intersect(packageSignatures(installed)).isNotEmpty()
        result.success(valid)
    }

    private fun packageSignatures(info: android.content.pm.PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo
            if (signingInfo?.hasMultipleSigners() == true) {
                signingInfo.apkContentsSigners?.toList().orEmpty()
            } else {
                signingInfo?.signingCertificateHistory?.toList().orEmpty()
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.toList().orEmpty()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        }.toSet()
    }

    private fun compareVersions(left: String, right: String): Int {
        fun parts(value: String) = value
            .substringBefore('-')
            .substringBefore('+')
            .split('.')
            .map { it.toIntOrNull() ?: -1 }
        val a = parts(left)
        val b = parts(right)
        for (index in 0 until maxOf(a.size, b.size)) {
            val comparison = a.getOrElse(index) { 0 }.compareTo(b.getOrElse(index) { 0 })
            if (comparison != 0) return comparison
        }
        return 0
    }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (canInstallPackages()) {
            result.success(null)
            return
        }
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("install_permission", "No se pudo abrir la autorización de Android.", null)
        }
    }

    private fun installUpdateApk(call: MethodCall, result: MethodChannel.Result) {
        if (!canInstallPackages()) {
            result.error("install_permission", "Android todavía no autorizó la instalación.", null)
            return
        }
        val file = verifiedUpdateFile(call.argument<String>("path"))
        if (file == null || !file.name.matches(Regex("update-[0-9]+\\.apk"))) {
            result.error("invalid_apk_path", "El APK no está en la carpeta segura.", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.update_files", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("installer_unavailable", "Android no pudo abrir el instalador.", null)
        }
    }

    private fun verifiedUpdateFile(path: String?): File? {
        if (path.isNullOrBlank()) return null
        val directory = updateDirectory().canonicalFile
        val file = File(path).canonicalFile
        return file.takeIf {
            it.exists() && it.isFile && it.parentFile == directory && it.extension == "apk"
        }
    }

    private fun updateDirectory() = File(cacheDir, "updates")

    private fun cleanupInstalledUpdates() {
        val directory = updateDirectory()
        val installedBuild = try {
            packageBuild(packageManager.getPackageInfo(packageName, 0))
        } catch (_: Exception) {
            return
        }
        directory.listFiles()?.forEach { file ->
            val match = Regex("update-([0-9]+)\\.(apk|part)").matchEntire(file.name)
            val targetBuild = match?.groupValues?.get(1)?.toLongOrNull()
            if (targetBuild == null || targetBuild <= installedBuild || file.extension == "part") {
                file.delete()
            }
        }
    }

    companion object {
        private const val DOWNLOAD_PERMISSION_REQUEST = 7102
    }
}
