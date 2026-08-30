package com.ycc.ycoo_forum

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
                val referer = call.argument<String>("referer")?.trim().takeUnless { it.isNullOrEmpty() } ?: "https://www.ycoo.net/"
                if (url.isEmpty()) {
                    result.error("INVALID_URL", "附件地址为空", null)
                    return@setMethodCallHandler
                }
                try {
                    val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    val request = DownloadManager.Request(Uri.parse(url)).apply {
                        setTitle("下载论坛附件")
                        setDescription(url.substringAfterLast('/').substringBefore('?').ifEmpty { "论坛附件" })
                        setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        setAllowedOverMetered(true)
                        setAllowedOverRoaming(true)
                        addRequestHeader("Referer", referer)
                        if (cookie.isNotEmpty()) addRequestHeader("Cookie", cookie)
                        addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36")
                    }
                    manager.enqueue(request)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("DOWNLOAD_FAILED", e.message, null)
                }
            }
    }
}
