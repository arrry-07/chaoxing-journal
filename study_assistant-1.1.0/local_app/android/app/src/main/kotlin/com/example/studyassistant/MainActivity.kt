package com.example.studyassistant

import android.app.NotificationManager
import android.content.pm.PackageManager
import java.util.zip.ZipFile
import android.content.Intent
import android.content.ComponentName
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private enum class SettingsOpenOutcome(val wireValue: String) {
        DIRECT("direct"),
        LIST_FALLBACK("listFallback"),
        APP_DETAILS_FALLBACK("appDetailsFallback"),
        UNAVAILABLE("unavailable"),
    }

    private var backupBridge: BackupBridge? = null
    private var personalFileBridge: PersonalFileBridge? = null
    private var verificationBrowser: VerificationBrowser? = null
    private var webSessionGeneration = 0L
    override fun onDestroy() {
        personalFileBridge?.close()
        personalFileBridge = null
        backupBridge?.close()
        backupBridge = null
        webSessionGeneration++
        verificationBrowser?.close()
        verificationBrowser = null
        super.onDestroy()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BackgroundReminderBridge.attach(flutterEngine, this)
        personalFileBridge = PersonalFileBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "study_assistant/personal_files"))
        backupBridge = BackupBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "study_assistant/backup"))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "study_assistant/external_links").setMethodCallHandler { call, result ->
            if(call.method == "verifySession") {
                val generation = ++webSessionGeneration
                val previous = verificationBrowser
                verificationBrowser = null
                fun openNew(cleaned: Boolean) {
                    if (generation != webSessionGeneration || isFinishing || isDestroyed) {
                        result.success(null)
                    } else if (!cleaned) {
                        result.error("web_cleanup_failed", "验证网站数据清理失败，请重试", null)
                    } else {
                        verificationBrowser = VerificationBrowser(this)
                        verificationBrowser!!.open(call.argument<String>("url"), call.argument<List<Map<String, String>>>("cookies") ?: emptyList(), call.argument<String>("userAgent"), result)
                    }
                }
                if (previous == null) openNew(true) else previous.close(::openNew)
                return@setMethodCallHandler
            }
            if(call.method == "clearWebSession") {
                webSessionGeneration++
                val previous = verificationBrowser
                verificationBrowser = null
                if (previous == null) WebSessionCleaner.clear(this) { result.success(it) }
                else previous.close { result.success(it) }
                return@setMethodCallHandler
            }
            if(call.method == "inspectApk") {
                result.success(inspectApk(call.argument<String>("filePath")))
                return@setMethodCallHandler
            }
            val opened = when (call.method) {
                "openUrl" -> openExternalUrl(call.argument<String>("url"))
                "openBrowser" -> openBrowser(call.argument<String>("url"))
                "openChaoxingAssignment" -> openChaoxingAssignment(call.argument<String>("url"))
                "installApk" -> installApk(call.argument<String>("filePath"))
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(opened)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "study_assistant/permissions").setMethodCallHandler { call, result ->
            if (call.method == "getAndroidSdkInt") {
                result.success(Build.VERSION.SDK_INT)
                return@setMethodCallHandler
            }
            if (call.method == "isNotificationListenerEnabled") {
                result.success(
                    NotificationManagerCompat.getEnabledListenerPackages(this)
                        .contains(packageName)
                )
                return@setMethodCallHandler
            }
            val outcome = when (call.method) {
                "openNotificationSettings",
                "openNotificationSettingsResult" -> openNotificationSettings()
                "openExactAlarmSettings",
                "openExactAlarmSettingsResult" -> openExactAlarmSettings()
                "openLockScreenNotificationSettings",
                "openLockScreenNotificationSettingsResult" ->
                    openNotificationChannelSettings(ASSIGNMENT_DEADLINE_CHANNEL_ID)
                "openNotificationChannelSettingsResult" ->
                    openNotificationChannelSettings(call.argument<String>("channelId"))
                "openBatterySettings",
                "openBatterySettingsResult" -> openBatterySettings()
                "openAppSettings",
                "openAppSettingsResult" -> openAppSettings()
                "openNotificationListenerSettings",
                "openNotificationListenerSettingsResult" ->
                    openNotificationListenerSettings()
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(
                if (call.method.endsWith("Result")) outcome.wireValue
                else (outcome == SettingsOpenOutcome.DIRECT ||
                    outcome == SettingsOpenOutcome.LIST_FALLBACK)
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        backupBridge?.onActivityResult(requestCode, resultCode, data)
        personalFileBridge?.onActivityResult(requestCode, resultCode, data)
    }

    private fun openNotificationSettings(): SettingsOpenOutcome {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            openAppNotificationSettings()
        ) {
            return SettingsOpenOutcome.DIRECT
        }
        return openAppDetailsFallback()
    }

    private fun openExactAlarmSettings(): SettingsOpenOutcome {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            openIntent(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(Uri.parse("package:$packageName"))
            )
        ) {
            return SettingsOpenOutcome.DIRECT
        }
        return openAppDetailsFallback()
    }

    private fun openNotificationChannelSettings(
        channelId: String?,
    ): SettingsOpenOutcome {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !channelId.isNullOrBlank()
        ) {
            val hasChannel = runCatching {
                getSystemService(NotificationManager::class.java)
                    .getNotificationChannel(channelId) != null
            }.getOrDefault(false)
            if (hasChannel && openIntent(
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            )) {
                return SettingsOpenOutcome.DIRECT
            }
            if (openAppNotificationSettings()) {
                return SettingsOpenOutcome.LIST_FALLBACK
            }
        }
        return openAppDetailsFallback()
    }

    private fun openBatterySettings(): SettingsOpenOutcome {
        if (openAppDetailsSettings()) {
            return SettingsOpenOutcome.APP_DETAILS_FALLBACK
        }
        if (openIntent(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))) {
            return SettingsOpenOutcome.LIST_FALLBACK
        }
        return SettingsOpenOutcome.UNAVAILABLE
    }

    private fun openNotificationListenerSettings(): SettingsOpenOutcome {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            openIntent(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                    .putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        ComponentName(
                            this,
                            ChaoxingNotificationListener::class.java
                        ).flattenToString()
                    )
            )
        ) {
            return SettingsOpenOutcome.DIRECT
        }
        if (openIntent(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))) {
            return SettingsOpenOutcome.LIST_FALLBACK
        }
        return openAppDetailsFallback()
    }

    private fun openAppSettings(): SettingsOpenOutcome {
        return if (openAppDetailsSettings()) {
            SettingsOpenOutcome.DIRECT
        } else {
            SettingsOpenOutcome.UNAVAILABLE
        }
    }

    private fun openAppNotificationSettings(): Boolean {
        return openIntent(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        )
    }

    private fun openAppDetailsSettings(): Boolean {
        return openIntent(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        )
    }

    private fun openAppDetailsFallback(): SettingsOpenOutcome {
        return if (openAppDetailsSettings()) {
            SettingsOpenOutcome.APP_DETAILS_FALLBACK
        } else {
            SettingsOpenOutcome.UNAVAILABLE
        }
    }

    private fun openExternalUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) {
            return false
        }
        return openIntent(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    @Suppress("DEPRECATION")
    private fun openChaoxingAssignment(url: String?): Boolean {
        val deepLink = ChaoxingAssignmentLink.build(url) ?: return false
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(deepLink))
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setPackage("com.chaoxing.mobile")
        val handlers = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        if (handlers.none { it.activityInfo.exported && it.activityInfo.enabled &&
                it.activityInfo.packageName == "com.chaoxing.mobile" }) return false
        return openIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun openBrowser(url: String?): Boolean {
        if (!BrowserPolicy.isAllowed(url)) return false
        val uri = Uri.parse(url)
        // Use only public SDK browser registration, intersected with HTTPS
        // handlers. App-link-only packages cannot enter this explicit chooser.
        val registeredBrowsers = packageManager.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_BROWSER), 0
        ).filter { it.activityInfo.exported && it.activityInfo.enabled }
            .map { it.activityInfo.packageName }
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://browser.invalid/"))
            .addCategory(Intent.CATEGORY_BROWSABLE)
        val handlers = packageManager.queryIntentActivities(probe, PackageManager.MATCH_DEFAULT_ONLY)
            .filter { it.activityInfo.exported && it.activityInfo.enabled }
        val allowedPackages = BrowserPolicy.browserPackages(registeredBrowsers,
            handlers.map { it.activityInfo.packageName })
        val browsers = handlers.filter { allowedPackages.contains(it.activityInfo.packageName) }
            .map { ComponentName(it.activityInfo.packageName, it.activityInfo.name) }
            .distinct()
        val targets = browsers.map { component ->
            Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
                .setComponent(component)
        }
        if (targets.isEmpty()) return false
        return if (targets.size == 1) openIntent(targets.first()) else openIntent(
            Intent.createChooser(targets.first(), "选择浏览器")
                .putExtra(Intent.EXTRA_INITIAL_INTENTS, targets.drop(1).toTypedArray())
        )
    }

    @Suppress("DEPRECATION")
    private fun inspectApk(filePath: String?): Map<String, Any> {
        if (filePath.isNullOrBlank()) return mapOf("compatible" to false, "reason" to "安装包不存在")
        return runCatching {
            val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
            val candidate = packageManager.getPackageArchiveInfo(filePath, flags)
                ?: return mapOf("compatible" to false, "reason" to "无法读取APK身份")
            val installed = packageManager.getPackageInfo(packageName, flags)
            val candidateCode = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
            val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
            val candidateSigs = if(Build.VERSION.SDK_INT >= 28) candidate.signingInfo?.apkContentsSigners else candidate.signatures
            val installedSigs = if(Build.VERSION.SDK_INT >= 28) installed.signingInfo?.apkContentsSigners else installed.signatures
            val signaturesMatch = !candidateSigs.isNullOrEmpty() && !installedSigs.isNullOrEmpty() && candidateSigs.toSet() == installedSigs.toSet()
            val appInfo = candidate.applicationInfo
            val sdkOk = appInfo != null && appInfo.minSdkVersion <= Build.VERSION.SDK_INT
            val nativePaths = ZipFile(filePath).use { zip -> zip.entries().asSequence().map { it.name }.filter { it.startsWith("lib/") && it.endsWith(".so") }.toList() }
            // A plugin can include an ABI without a matching Flutter engine.
            val abiOk = UpdateApkPolicy.hasSupportedFlutterEngine(
                nativePaths,
                Build.SUPPORTED_ABIS.toList()
            )
            val reason = when {
                candidate.packageName != packageName -> "安装包名不一致，无法覆盖升级"
                !signaturesMatch -> "安装签名不一致，无法覆盖升级"
                candidateCode <= installedCode -> "安装包版本未增加"
                !sdkOk -> "系统版本不满足要求"
                !abiOk -> "安装包不支持此设备架构"
                else -> ""
            }
            mapOf("compatible" to reason.isEmpty(), "reason" to reason, "applicationId" to candidate.packageName, "versionCode" to candidateCode, "versionName" to (candidate.versionName ?: ""))
        }.getOrElse { mapOf("compatible" to false, "reason" to "安装包身份检查失败") }
    }

    private fun installApk(filePath: String?): Boolean {
        if (filePath.isNullOrBlank()) {
            return false
        }
        if (inspectApk(filePath)["compatible"] != true) return false
        if(Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            openIntent(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).setData(Uri.parse("package:$packageName")))
            return false
        }
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            return false
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.update_file_provider",
            apkFile
        )
        return openIntent(
            Intent(Intent.ACTION_INSTALL_PACKAGE)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                .putExtra(Intent.EXTRA_RETURN_RESULT, true)
        )
    }

    private fun openIntent(intent: Intent): Boolean {
        return runCatching {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.isSuccess
    }

    private companion object {
        const val ASSIGNMENT_DEADLINE_CHANNEL_ID = "assignment_deadlines"
    }
}
