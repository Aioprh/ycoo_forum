package com.ycc.ycoo_forum

import android.content.Context
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
                val referer = call.argument<String>("referer")?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: "https://ycoo.net/"

                if (url.isEmpty()) {
                    result.error("INVALID_URL", "附件地址为空", null)
                    return@setMethodCallHandler
                }

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.error("STORAGE_PERMISSION", "请允许源论坛访问所有文件后再下载附件", null)
                        return@setMethodCallHandler
                    }

                    val forumDir = File(Environment.getExternalStorageDirectory(), "源论坛")
                    if (!forumDir.exists() && !forumDir.mkdirs()) {
                        result.error("STORAGE_FAILED", "无法创建 /storage/emulated/0/源论坛", null)
                        return@setMethodCallHandler
                    }

                    val guessedName = guessNameFromUrl(url)
                    val target = uniqueFile(forumDir, sanitizeFileName(guessedName))

                    Thread {
                        val ok = downloadToFile(url, cookie, referer, target)
                        runOnUiThread {
                            Toast.makeText(
                                this,
                                if (ok) "附件已保存到 /storage/emulated/0/源论坛/${target.name}"
                                else "附件下载失败，请检查登录状态或网络",
                                Toast.LENGTH_LONG,
                            ).show()
                        }
                    }.apply { name = "YcooAttachmentDownload" }.start()

                    result.success(true)
                } catch (e: Exception) {
                    result.error("DOWNLOAD_FAILED", e.message, null)
                }
            }
    }

    private fun downloadToFile(
        url: String,
        cookie: String,
        referer: String,
        initialTarget: File,
    ): Boolean {
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
                setRequestProperty(
                    "User-Agent",
                    "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
                )
                setRequestProperty("Accept", "*/*")
                setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
            }

            val code = connection.responseCode
            if (code !in 200..299) return false

            val contentType = connection.contentType?.lowercase().orEmpty()
            if (contentType.contains("text/html") && connection.contentLengthLong > 0L && connection.contentLengthLong < 1024 * 1024) {
                return false
            }

            val serverName = resolveResponseFileName(
                connection.getHeaderField("Content-Disposition"),
                connection.url.toString(),
                contentType,
            )
            if (serverName.isNotBlank() && !looksGeneric(serverName)) {
                target = uniqueFile(initialTarget.parentFile ?: return false, sanitizeFileName(serverName))
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
            if (target.exists()) target.delete()
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
            return target.exists() && target.length() > 0L
        } catch (_: Exception) {
            return false
        } finally {
            connection?.disconnect()
        }
    }

    private fun guessNameFromUrl(url: String): String {
        return try {
            val uri = Uri.parse(url)
            for (key in listOf("filename", "file", "name")) {
                val value = uri.getQueryParameter(key)?.trim().orEmpty()
                if (value.isNotEmpty()) return decodeFileName(value)
            }
            val pathName = uri.lastPathSegment?.trim().orEmpty()
            if (pathName.isNotEmpty() && !pathName.equals("attachment.php", true)) {
                val decoded = decodeFileName(pathName)
                if (decoded.isNotEmpty()) return decoded
            }
            val f = uri.getQueryParameter("_f")?.trim().orEmpty()
            if (f.startsWith(".") && f.length <= 12) return "论坛附件$f"
        } catch (_: Exception) {}
        return "论坛附件_${System.currentTimeMillis()}"
    }

    private fun resolveResponseFileName(disposition: String?, finalUrl: String, mime: String): String {
        if (!disposition.isNullOrBlank()) {
            val guessed = URLUtil.guessFileName(finalUrl, disposition, mime)
            if (guessed.isNotBlank() && !looksGeneric(guessed)) return guessed
        }
        return guessNameFromUrl(finalUrl)
    }

    private fun looksGeneric(name: String): Boolean {
        val n = name.trim().lowercase()
        return n.isEmpty() || n == "attachment.php" || n == "download" || n == "download.php"
    }

    private fun decodeFileName(value: String): String = try {
        Uri.decode(value).replace("+", " ").trim()
    } catch (_: Exception) {
        value.trim()
    }

    private fun sanitizeFileName(value: String): String {
        var name = decodeFileName(value)
            .replace("/", "_")
            .replace("\\", "_")
            .replace(Regex("[\\u0000-\\u001F]"), "")
            .trim()
        if (name.isEmpty() || name == "." || name == "..") {
            name = "论坛附件_${System.currentTimeMillis()}"
        }
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
        while (target.exists()) {
            target = File(dir, "$base ($index)$ext")
            index++
        }
        return target
    }
}
