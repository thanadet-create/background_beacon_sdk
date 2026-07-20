package com.example.background_beacon_sdk.core

/**
 * Region enter/exit state machine — derived from raw sightings.
 *
 * BLE has no direct "left the area" event, only "saw an advertisement" —
 * exit must be inferred from silence: no beacon of the region seen for
 * longer than [exitTimeoutMs] counts as exited. The timeout must always
 * exceed the duty cycle, or scan rest periods become false exits
 * (the creator is responsible — see BleBeaconScanner.exitTimeoutMs).
 *
 * Thread contract: call every method from the main thread only (no locks inside).
 */
class RegionStateTracker(private val exitTimeoutMs: Long) {

    /** Identifiers of regions currently "inside" → last seen time (epoch ms) */
    private val lastSeenAt = mutableMapOf<String, Long>()

    /**
     * Record a beacon sighting for this region — returns `true` when the
     * state just flipped outside→inside (caller must emit enterRegion).
     */
    fun onSighting(regionIdentifier: String, nowMs: Long): Boolean {
        val wasInside = lastSeenAt.containsKey(regionIdentifier)
        lastSeenAt[regionIdentifier] = nowMs
        return !wasInside
    }

    /**
     * Returns identifiers of regions silent past the timeout and removes
     * them from "inside" — caller must emit exitRegion per entry
     * (empty beacons list per the wire contract).
     */
    fun checkExits(nowMs: Long): List<String> {
        val exited = lastSeenAt.filterValues { nowMs - it > exitTimeoutMs }.keys.toList()
        exited.forEach { lastSeenAt.remove(it) }
        return exited
    }

    /** Regions currently "inside" — used for the notification status text */
    fun insideRegions(): Set<String> = lastSeenAt.keys.toSet()
}
