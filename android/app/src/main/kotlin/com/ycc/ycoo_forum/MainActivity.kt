package com.ycc.ycoo_forum

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.webkit.URLUtil
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private val channelName = "ycoo/attachment_download"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "download") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url")?.trim().orEmpty()
                val cookie = call.argument<String>("cookie")?.trim().orEmpty()
                val referer = call.argument<String>("referer")?.trim().takeUnless { it.isNullOrEmpty() } ?: "https://ycoo.net/"
                val requestedFilename = call.argument<String>("filename")?.trim().orEmpty()
                if (url.isEmpty()) { result.error("INVALID_URL", "附件地址为空", null); return@setMethodCallHandler }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
                        startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName")))
                        result.error("STORAGE_PERMISSION", "请允许源论坛访问所有文件后再下载附件", null)
                        return@setMethodCallHandler
                    }
                    val forumDir = File(Environment.getExternalStorageDirectory(), "源论坛")
                    if (!forumDir.exists() && !forumDir.mkdirs()) { result.error("STORAGE_FAILED", "无法创建 /storage/emulated/0/源论坛", null); return@setMethodCallHandler }
                    val guessedName = if (requestedFilename.isNotEmpty() && !isDownloadScript(requestedFilename)) requestedFilename else guessNameFromUrl(url)
                    val target = uniqueFile(forumDir, sanitizeFileName(guessedName))
                    Thread {
                        val finalTarget = downloadToFile(url, cookie, referer, target, requestedFilename)
                        runOnUiThread {
                            Toast.makeText(this, if (finalTarget != null) "附件已保存到 /storage/emulated/0/源论坛/${finalTarget.name}" else "附件下载失败，请检查登录状态或网络", Toast.LENGTH_LONG).show()
                        }
                    }.apply { name = "YcooAttachmentDownload" }.start()
                    result.success(true)
                } catch (e: Exception) { result.error("DOWNLOAD_FAILED", e.message, null) }
            }
    }

    private fun downloadToFile(url: String, cookie: String, referer: String, initialTarget: File, requestedFilename: String): File? {
        var connection: HttpURLConnection? = null
        var target = initialTarget
        try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = true
                connectTimeout = 15000
                readTimeout = 30000
                requestMethod = "GET"
                setRequestProperty("Referer", referer)
                if (cookie.isNotEmpty()) setRequestProperty("Cookie", cookie)
                setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36")
                setRequestProperty("Accept", "*/*")
                setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
            }
            val code = connection.responseCode
            if (code !in 200..299) return null
            val contentType = connection.contentType?.substringBefore(';')?.trim()?.lowercase().orEmpty()
            if (contentType == "text/html" && connection.contentLengthLong > 0L && connection.contentLengthLong < 1024 * 1024) return null

            val responseName = resolveResponseFileName(connection.getHeaderField("Content-Disposition"), connection.url.toString(), contentType)
            val requestedIsGeneric = requestedFilename.isBlank() || looksGeneric(requestedFilename) || isDownloadScript(requestedFilename)
            val requestedHasExtension = hasFileExtension(requestedFilename)
            if (responseName.isNotBlank() && !looksGeneric(responseName) && (requestedIsGeneric || !requestedHasExtension || looksGeneric(target.name))) {
                target = uniqueFile(initialTarget.parentFile ?: return null, sanitizeFileName(responseName))
            }

            val temp = File(target.parentFile, ".${target.name}.part")
            if (temp.exists()) temp.delete()
            connection.inputStream.use { input ->
                FileOutputStream(temp).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }

            // 动态下载入口通常是 forum.php / attachment.php，没有可用扩展名。
            // 此时必须根据实际响应内容识别格式，而不是把接口脚本名当成附件格式。
            val detectedExtension = detectFileExtension(temp, contentType)
            if (isDownloadScript(target.name) || !hasFileExtension(target.name)) {
                if (detectedExtension.isNotEmpty()) {
                    val baseName = if (isDownloadScript(target.name)) "论坛附件" else target.name
                    val renamed = uniqueFile(target.parentFile ?: return null, "$baseName$detectedExtension")
                    target = renamed
                }
            }

            if (target.exists()) target.delete()
            if (!temp.renameTo(target)) { temp.copyTo(target, overwrite = true); temp.delete() }
            return if (target.exists() && target.length() > 0L) target else null
        } catch (_: Exception) { return null }
        finally { connection?.disconnect() }
    }

    private fun guessNameFromUrl(url: String): String {
        try {
            val uri = Uri.parse(url)
            for (key in listOf("filename", "file", "name")) {
                val value = uri.getQueryParameter(key)?.trim().orEmpty()
                if (value.isNotEmpty() && !isDownloadScript(value)) return decodeFileName(value)
            }
            val f = uri.getQueryParameter("_f")?.trim().orEmpty()
            if (f.isNotEmpty()) {
                val decoded = decodeFileName(f)
                if (hasFileExtension(decoded)) return decoded
                if (decoded.startsWith(".") && decoded.length <= 12) return "论坛附件$decoded"
                if (Regex("^[A-Za-z0-9]{1,12}$").matches(decoded)) return "论坛附件.$decoded"
            }
            val pathName = uri.lastPathSegment?.trim().orEmpty()
            if (pathName.isNotEmpty() && !isDownloadScript(pathName)) return decodeFileName(pathName)
        } catch (_: Exception) {}
        return "论坛附件_${System.currentTimeMillis()}"
    }

    private fun resolveResponseFileName(disposition: String?, finalUrl: String, mime: String): String {
        if (!disposition.isNullOrBlank()) {
            val guessed = URLUtil.guessFileName(finalUrl, disposition, mime)
            if (guessed.isNotBlank() && !looksGeneric(guessed) && !isDownloadScript(guessed) && hasFileExtension(guessed)) return guessed
        }
        val pathName = try { Uri.parse(finalUrl).lastPathSegment.orEmpty() } catch (_: Exception) { "" }
        if (pathName.isNotBlank() && !isDownloadScript(pathName)) {
            val decoded = decodeFileName(pathName)
            if (hasFileExtension(decoded)) return decoded
        }
        return ""
    }

    private fun detectFileExtension(file: File, mime: String): String {
        try {
            file.inputStream().use { input ->
                val header = ByteArray(32)
                val count = input.read(header)
                if (count > 0) {
                    if (startsWith(header, count, byteArrayOf(0x25, 0x50, 0x44, 0x46))) return ".pdf"
                    if (startsWith(header, count, byteArrayOf(0x50, 0x4B, 0x03, 0x04)) || startsWith(header, count, byteArrayOf(0x50, 0x4B, 0x05, 0x06))) return if (mime.contains("epub")) ".epub" else if (mime.contains("android.package")) ".apk" else ".zip"
                    if (startsWith(header, count, byteArrayOf(0x1F, 0x8B.toByte()))) return ".gz"
                    if (startsWith(header, count, byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47))) return ".png"
                    if (startsWith(header, count, byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()))) return ".jpg"
                    if (startsWith(header, count, byteArrayOf(0x47, 0x49, 0x46, 0x38))) return ".gif"
                    if (count >= 12 && String(header, 0, 4, Charsets.US_ASCII) == "RIFF" && String(header, 8, 4, Charsets.US_ASCII) == "WEBP") return ".webp"
                }
            }
            val bytes = file.inputStream().use { it.readNBytes(minOf(file.length().toInt(), 128 * 1024)) }
            val text = bytes.toString(Charsets.UTF_8).trimStart('\uFEFF', ' ', '\t', '\r', '\n')
            if (text.startsWith("{") || text.startsWith("[")) return ".json"
        } catch (_: Exception) {}
        return extensionForMime(mime)
    }

    private fun startsWith(data: ByteArray, count: Int, prefix: ByteArray): Boolean {
        if (count < prefix.size) return false
        for (i in prefix.indices) if (data[i] != prefix[i]) return false
        return true
    }

    private fun isDownloadScript(name: String): Boolean {
        val n = name.substringBefore('?').substringBefore('#').trim().lowercase()
        return n == "forum.php" || n == "attachment.php" || n == "download.php" || n == "download" || n == "plugin.php" || n == "index.php"
    }

    private fun hasFileExtension(name: String): Boolean {
        val clean = name.substringBefore('?').substringBefore('#').trim()
        return Regex(".+\\.[A-Za-z0-9]{1,12}$").matches(clean) && !isDownloadScript(clean)
    }

    private fun extensionForMime(mime: String): String = when {
        mime.contains("application/json") -> ".json"
        mime.contains("application/zip") -> ".zip"
        mime.contains("application/x-rar") -> ".rar"
        mime.contains("application/x-7z") -> ".7z"
        mime.contains("application/pdf") -> ".pdf"
        mime.contains("application/epub") -> ".epub"
        mime.contains("application/vnd.android.package-archive") -> ".apk"
        mime.contains("text/plain") -> ".txt"
        mime.contains("text/xml") || mime.contains("application/xml") -> ".xml"
        mime.contains("text/csv") -> ".csv"
        mime.contains("audio/mpeg") -> ".mp3"
        mime.contains("audio/wav") || mime.contains("audio/x-wav") -> ".wav"
        mime.contains("audio/flac") -> ".flac"
        mime.contains("video/mp4") -> ".mp4"
        mime.contains("image/jpeg") -> ".jpg"
        mime.contains("image/png") -> ".png"
        mime.contains("image/gif") -> ".gif"
        mime.contains("image/webp") -> ".webp"
        else -> ""
    }

    private fun looksGeneric(name: String): Boolean {
        val n = name.trim().lowercase()
        return n.isEmpty() || n == "论坛附件" || n.startsWith("论坛附件_") || isDownloadScript(n)
    }

    private fun decodeFileName(value: String): String = try { Uri.decode(value).replace("+", " ").trim() } catch (_: Exception) { value.trim() }

    private fun sanitizeFileName(value: String): String {
        var name = decodeFileName(value).replace("/", "_").replace("\\", "_").replace(Regex("[\\u0000-\\u001F]"), "").trim()
        if (name.isEmpty() || name == "." || name == "..") name = "论坛附件_${System.currentTimeMillis()}"
        if (name.length > 180) name = name.take(180)
        return name
    }

    private fun uniqueFile(dir: File, name: String): File {
        var target = File(dir, name)
        if (!target.exists()) return target
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var index = 1
        while (target.exists()) { target = File(dir, "$base ($index)$ext"); index++ }
        return target
    }
}
