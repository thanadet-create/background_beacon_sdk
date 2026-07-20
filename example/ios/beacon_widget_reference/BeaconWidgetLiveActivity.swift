// ===== Reference file for the Widget Extension =====
// After creating the "BeaconWidget" target in Xcode:
// delete every template-generated .swift file in that target
// and copy this file's contents in as the replacement.
// The toggle button also needs Runner/ToggleScanIntent.swift as a
// member of this target (tick both Runner and BeaconWidget).
import ActivityKit
import SwiftUI
import WidgetKit

/// Must match the same struct in Runner/LiveActivityManager.swift exactly
/// (type + field names — ActivityKit pairs across processes with these)
struct BeaconActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var beaconCount: Int
        /// Drives the toggle button label on the card (iOS 17+) —
        /// true = show the stop button
        var isScanning: Bool
    }

    var title: String
}

/// Stop/start button on the card — iOS 17+ only (widget Button(intent:));
/// 16.2 sees the card without the button, same as before
@available(iOS 17.0, *)
private struct ToggleButton: View {
    let isScanning: Bool

    var body: some View {
        Button(intent: ToggleScanIntent()) {
            Label(
                isScanning ? "หยุดสแกน" : "เริ่มสแกน",
                systemImage: isScanning ? "pause.fill" : "play.fill"
            )
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isScanning ? .red : .green)
    }
}

@main
struct BeaconWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeaconWidgetLiveActivity()
    }
}

struct BeaconWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BeaconActivityAttributes.self) { context in
            // ---- Lock screen / banner (what an iPhone 12 sees — no Dynamic Island) ----
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.headline)
                        Text(context.state.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack {
                        Text("\(context.state.beaconCount)")
                            .font(.title)
                            .bold()
                        Text("beacon")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if #available(iOS 17.0, *) {
                    ToggleButton(isScanning: context.state.isScanning)
                }
            }
            .padding()

        } dynamicIsland: { context in
            // ---- Dynamic Island (iPhone 14 Pro and up) ----
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.statusText)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.beaconCount)")
                        .font(.title2)
                        .bold()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Buttons only work in expanded — the system makes
                    // compact/minimal non-interactive
                    if #available(iOS 17.0, *) {
                        ToggleButton(isScanning: context.state.isScanning)
                    }
                }
            } compactLeading: {
                Image(systemName: "dot.radiowaves.left.and.right")
            } compactTrailing: {
                Text("\(context.state.beaconCount)")
            } minimal: {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
        }
    }
}
