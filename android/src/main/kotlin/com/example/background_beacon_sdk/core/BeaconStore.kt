package com.example.background_beacon_sdk.core

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistence for state that must survive process death — SharedPreferences.
 *
 * Consumers: HeadlessBeaconRunner (loads config when woken with no engine),
 * BootReceiver (restarts the scan after reboot), BleBeaconScanner (writes on
 * start/stop).
 *
 * Stores:
 * - callback handles (dispatcher + user) from registerBackgroundCallback
 * - the active monitoring region set + settings
 * - headless-mode inside-state (identifier → lastSeen ms), separate from
 *   in-process RegionStateTracker state — different lifecycle
 */
internal object BeaconStore {

    private const val PREFS = "background_beacon_sdk"
    private const val KEY_DISPATCHER_HANDLE = "dispatcherHandle"
    private const val KEY_CALLBACK_HANDLE = "callbackHandle"
    private const val KEY_REGIONS = "regions"
    private const val KEY_SETTINGS = "settings"
    private const val KEY_INSIDE_STATE = "insideState"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---- callback handles ----

    fun saveCallbackHandles(context: Context, dispatcherHandle: Long, callbackHandle: Long) {
        prefs(context).edit()
            .putLong(KEY_DISPATCHER_HANDLE, dispatcherHandle)
            .putLong(KEY_CALLBACK_HANDLE, callbackHandle)
            .apply()
    }

    /** Returns (dispatcherHandle, callbackHandle) — null if never registered */
    fun loadCallbackHandles(context: Context): Pair<Long, Long>? {
        val p = prefs(context)
        if (!p.contains(KEY_DISPATCHER_HANDLE)) return null
        return p.getLong(KEY_DISPATCHER_HANDLE, 0) to p.getLong(KEY_CALLBACK_HANDLE, 0)
    }

    // ---- monitoring config ----

    fun saveMonitoring(
        context: Context,
        regions: List<BeaconRegionData>,
        settings: ScanSettingsData,
    ) {
        val regionsJson = JSONArray(regions.map { region ->
            JSONObject()
                .put("identifier", region.identifier)
                .put("uuid", region.uuid ?: JSONObject.NULL)
                .put("major", region.major ?: JSONObject.NULL)
                .put("minor", region.minor ?: JSONObject.NULL)
        })
        val settingsJson = JSONObject()
            .put("scanIntervalMs", settings.scanIntervalMs)
            .put("scanDurationMs", settings.scanDurationMs)
            .put("foregroundServiceNotification", settings.foregroundServiceNotification)
            .put("beaconLayout", settings.beaconLayout)
            .put("rangingEnabled", settings.rangingEnabled)
            .put("continuousRanging", settings.continuousRanging)

        prefs(context).edit()
            .putString(KEY_REGIONS, regionsJson.toString())
            .putString(KEY_SETTINGS, settingsJson.toString())
            .apply()
    }

    fun clearMonitoring(context: Context) {
        prefs(context).edit()
            .remove(KEY_REGIONS)
            .remove(KEY_SETTINGS)
            .remove(KEY_INSIDE_STATE)
            .apply()
    }

    fun loadRegions(context: Context): List<BeaconRegionData> {
        val raw = prefs(context).getString(KEY_REGIONS, null) ?: return emptyList()
        val array = JSONArray(raw)
        return (0 until array.length()).map { i ->
            val json = array.getJSONObject(i)
            BeaconRegionData(
                identifier = json.getString("identifier"),
                uuid = if (json.isNull("uuid")) null else json.getString("uuid"),
                major = if (json.isNull("major")) null else json.getInt("major"),
                minor = if (json.isNull("minor")) null else json.getInt("minor"),
            )
        }
    }

    fun loadSettings(context: Context): ScanSettingsData? {
        val raw = prefs(context).getString(KEY_SETTINGS, null) ?: return null
        val json = JSONObject(raw)
        return ScanSettingsData(
            scanIntervalMs = json.getInt("scanIntervalMs"),
            scanDurationMs = json.getInt("scanDurationMs"),
            foregroundServiceNotification = json.getBoolean("foregroundServiceNotification"),
            beaconLayout = json.getString("beaconLayout"),
            // optBoolean: older JSON from a previous install lacks this key
            continuousRanging = json.optBoolean("continuousRanging", false),
            rangingEnabled = json.getBoolean("rangingEnabled"),
        )
    }

    /** Is monitoring still active — decides whether BootReceiver restarts the scan */
    fun hasActiveMonitoring(context: Context): Boolean =
        prefs(context).contains(KEY_REGIONS)

    // ---- headless inside-state ----

    fun loadInsideState(context: Context): MutableMap<String, Long> {
        val raw = prefs(context).getString(KEY_INSIDE_STATE, null) ?: return mutableMapOf()
        val json = JSONObject(raw)
        val state = mutableMapOf<String, Long>()
        json.keys().forEach { key -> state[key] = json.getLong(key) }
        return state
    }

    fun saveInsideState(context: Context, state: Map<String, Long>) {
        prefs(context).edit()
            .putString(KEY_INSIDE_STATE, JSONObject(state as Map<*, *>).toString())
            .apply()
    }

    /**
     * Cleared on startMonitoring — old session state must not leak across:
     * stale inside flags from a previous headless run silently suppress the
     * new session's enterRegion (kill the app and enter never fires again
     * while the beacon stays visible).
     */
    fun clearInsideState(context: Context) {
        prefs(context).edit().remove(KEY_INSIDE_STATE).apply()
    }
}
