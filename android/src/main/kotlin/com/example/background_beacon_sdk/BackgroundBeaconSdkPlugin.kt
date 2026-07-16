package com.example.background_beacon_sdk

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.example.background_beacon_sdk.core.BeaconRegionData
import com.example.background_beacon_sdk.core.BeaconScanner
import com.example.background_beacon_sdk.core.BeaconStore
import com.example.background_beacon_sdk.core.ScanSettingsData
import com.example.background_beacon_sdk.gms.GmsBeaconScanner
import com.example.background_beacon_sdk.hms.HmsBeaconScanner
import com.example.background_beacon_sdk.util.MobileServicesDetector
import com.example.background_beacon_sdk.util.PermissionManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * Entry point ฝั่ง Android — ชื่อ class ต้องตรง `pluginClass` ใน pubspec.yaml
 *
 * หน้าที่: รับ channel call → แปลง Map ↔ data class → delegate ไป scanner
 * ห้ามมี scan logic ที่นี่ (อยู่ core/)
 */
class BackgroundBeaconSdkPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private val mainHandler = Handler(Looper.getMainLooper())
    private val permissionManager = PermissionManager()

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null
    private var scanner: BeaconScanner? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // detect/scan ใช้ applicationContext — ไม่ต้องพึ่ง activity
        // (activity จำเป็นเฉพาะ requestPermissions)
        context = binding.applicationContext

        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "background_beacon_sdk/methods",
        )
        eventChannel = EventChannel(
            binding.binaryMessenger,
            "background_beacon_sdk/events",
        )

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    /** สร้าง scanner ตามผล detect ครั้งแรกที่ต้องใช้ แล้ว reuse ตลอด engine */
    private fun ensureScanner(): BeaconScanner =
        scanner ?: when (MobileServicesDetector.detect(context)) {
            "hms" -> HmsBeaconScanner(context)
            else -> GmsBeaconScanner(context)
        }.also { created ->
            // scan callback มาบน binder thread — eventSink ต้องถูกเรียกบน main
            created.setListener { event ->
                mainHandler.post { eventSink?.success(event.toMap()) }
            }
            scanner = created
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detectMobileServices" ->
                result.success(MobileServicesDetector.detect(context))

            "requestPermissions" -> {
                val currentActivity = activity
                    ?: return result.error(
                        "NO_ACTIVITY",
                        "requestPermissions requires a foreground activity",
                        null,
                    )
                permissionManager.request(currentActivity, result)
            }

            "startMonitoring" -> {
                try {
                    val regions = call.argument<List<Map<String, Any?>>>("regions")!!
                        .map { BeaconRegionData.fromMap(it) }
                    val settings =
                        ScanSettingsData.fromMap(call.argument<Map<String, Any?>>("settings")!!)
                    ensureScanner().startMonitoring(regions, settings)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("START_FAILED", e.message, null)
                }
            }

            "stopMonitoring" -> {
                scanner?.stopMonitoring()
                result.success(null)
            }

            "detectBeacon" -> {
                try {
                    @Suppress("UNCHECKED_CAST")
                    val region = BeaconRegionData.fromMap(call.arguments as Map<String, Any?>)
                    // callback มาบน main thread แล้ว (สัญญาของ BeaconScanner.detectBeacon)
                    ensureScanner().detectBeacon(region, DETECT_TIMEOUT_MS) { found ->
                        result.success(found)
                    }
                } catch (e: Exception) {
                    result.error("DETECT_FAILED", e.message, null)
                }
            }

            "registerBackgroundCallback" -> {
                // channel ส่ง int เล็กมาเป็น Int ใหญ่มาเป็น Long — รับผ่าน Number
                val dispatcherHandle =
                    (call.argument<Number>("dispatcherHandle"))?.toLong()
                val callbackHandle = (call.argument<Number>("callbackHandle"))?.toLong()
                if (dispatcherHandle == null || callbackHandle == null) {
                    result.error("REGISTER_FAILED", "Missing callback handles", null)
                } else {
                    BeaconStore.saveCallbackHandles(context, dispatcherHandle, callbackHandle)
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(permissionManager)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(permissionManager)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scanner?.stopMonitoring() // engine ตาย scan ต้องไม่รั่วกินแบตต่อ
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private companion object {
        const val DETECT_TIMEOUT_MS = 3000L
    }
}
