import AppIntents
import Foundation

extension Notification.Name {
    /// ToggleScanIntent (runs in the app process) → LiveActivityManager → Dart
    /// Declared here because this file belongs to both targets —
    /// LiveActivityManager (Runner only) references the name when observing
    static let beaconToggleScan = Notification.Name("beaconToggleScan")
}

/// The Live Activity button (iOS 17+) — this file must be a member of
/// **both** Runner and BeaconWidget: the widget needs the type to compile
/// the button, but LiveActivityIntent makes the system run perform() in the
/// app's process (launching the app into the background if it isn't running)
@available(iOS 17.0, *)
struct ToggleScanIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle beacon scan"

    func perform() async throws -> some IntentResult {
        // Just signal and return — perform() is time-limited; the real work
        // (stop/start monitoring + updating the card) belongs to the Dart
        // side via LiveActivityManager
        NotificationCenter.default.post(name: .beaconToggleScan, object: nil)
        return .result()
    }
}
