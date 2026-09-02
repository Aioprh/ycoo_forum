package com.ycc.ycoo_forum

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.webkit.URLUtil
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
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
                    ?: "https://www.ycoo.net/"
                if (url.isEmpty()) {
                    result.error("INVALID_URL", "附件地址为空", null)
                    return@setMethodCallHandler
                }
                try {
                    val storageRoot = Environment.getExternalStorageDirectory()
                    val forumDir = File(storageRoot, "源论坛")

                    // Android 11+ 对 /storage/emulated/0/ 根目录下的自定义文件夹采用
                    // scoped storage 限制。用户明确要求固定保存到 /storage/emulated/0/源论坛，
                    // 因此这里使用系统的“所有文件访问权”。没有授权时只打开对应设置页，
                    // 不再偷偷退回 Android.providers.downloads/cache。
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.error("STORAGE_PERMISSION", "请允许源论坛访问所有文件后再下载附件", null)
                        return@setMethodCallHandler
                    }

                    if (!forumDir.exists() && !forumDir.mkdirs()) {
                        result.error("STORAGE_FAILED", "无法创建 /storage/emulated/0/源论坛", null)
                        return@setMethodCallHandler
                    }

                    val filename = resolveFileName(url, cookie, referer)
                    val target = uniqueFile(forumDir, sanitizeFileName(filename))
                    val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    val request = DownloadManager.Request(Uri.parse(url)).apply {
                        setTitle(target.name)
                        setDescription("源论坛附件")
                        setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        setAllowedOverMetered(true)
                        setAllowedOverRoaming(true)
                        setDestinationUri(Uri.fromFile(target))
                        addRequestHeader("Referer", referer)
                        if (cookie.isNotEmpty()) addRequestHeader("Cookie", cookie)
                        addRequestHeader(
                            "User-Agent",
                            "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
                        )
                    }
                    manager.enqueue(request)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("DOWNLOAD_FAILED", e.message, null)
                }
            }
    }

    private fun resolveFileName(url: String, cookie: String, referer: String): String {
        var current = url
        var connection: HttpURLConnection? = null
        try {
            repeat(6) {
                connection = (URL(current).openConnection() as HttpURLConnection).apply {
                    requestMethod = "HEAD"
                    instanceFollowRedirects = false
                    connectTimeout = 10000
                    readTimeout = 10000
                    setRequestProperty("Referer", referer)
                    if (cookie.isNotEmpty()) setRequestProperty("Cookie", cookie)
                    setRequestProperty(
                        "User-Agent",
                        "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
                    )
                }
                val code = connection!!.responseCode
                val disposition = connection!!.getHeaderField("Content-Disposition")
                val mime = connection!!.contentType
                val dispositionName = if (!disposition.isNullOrBlank()) {
                    URLUtil.guessFileName(current, disposition, mime)
                } else ""
                if (dispositionName.isNotBlank() && !looksGeneric(dispositionName)) return dispositionName

                val location = connection!!.getHeaderField("Location")
                if (code in 300..399 && !location.isNullOrBlank()) {
                    current = URL(URL(current), location).toString()
                    return@repeat
                }

                val guessed = URLUtil.guessFileName(current, disposition, mime)
                if (guessed.isNotBlank() && !looksGeneric(guessed)) return guessed
                return@repeat
            }
        } catch (_: Exception) {
            // Fall through to URL/query based filename recovery.
        } finally {
            connection?.disconnect()
        }

        val uri = Uri.parse(current)
        val queryNames = listOf("filename", "file", "name")
        for (key in queryNames) {
            val value = uri.getQueryParameter(key)?.trim().orEmpty()
            if (value.isNotEmpty()) return decodeFileName(value)
        }
        val pathName = uri.lastPathSegment?.trim().orEmpty()
        if (pathName.isNotEmpty() && !pathName.equals("attachment.php", true)) {
            val decoded = decodeFileName(pathName)
            if (decoded.isNotEmpty()) return decoded
        }
        val f = uri.getQueryParameter("_f")?.trim().orEmpty()
        if (f.isNotEmpty() && f.startsWith(".") && f.length <= 12) {
            return "论坛附件$f"
        }
        return "论坛附件_${System.currentTimeMillis()}"
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
        while (target.exists()) {
            target = File(dir, "$base ($index)$ext")
            index++
        }
        return target
    }
}
