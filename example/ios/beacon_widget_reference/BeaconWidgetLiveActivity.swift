// ===== ไฟล์อ้างอิงสำหรับ Widget Extension =====
// หลังสร้าง target "BeaconWidget" ใน Xcode แล้ว:
// ลบไฟล์ .swift ที่ template สร้างมาทั้งหมดใน target นั้น
// แล้ว copy เนื้อหาไฟล์นี้ไปแทน (ไฟล์เดียวจบ)

import ActivityKit
import SwiftUI
import WidgetKit

/// ต้องตรงกับ struct เดียวกันใน Runner/LiveActivityManager.swift เป๊ะ
/// (ชื่อ type + ชื่อ field — ActivityKit จับคู่ข้าม process ด้วยสิ่งนี้)
struct BeaconActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var beaconCount: Int
    }

    var title: String
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
            // ---- จอล็อค / แบนเนอร์ (iPhone 12 เห็นแบบนี้ — ไม่มี Dynamic Island) ----
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
            .padding()

        } dynamicIsland: { context in
            // ---- Dynamic Island (iPhone 14 Pro ขึ้นไป) ----
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
