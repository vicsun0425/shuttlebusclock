import SwiftUI
import SwiftData

/// Per-stop scheduled-monitoring settings: on/off, which weekdays, and the
/// daily time window.
///
/// Every control writes straight through to the `@Model`, and the footer
/// re-runs the real `ScheduleEvaluator` against the live values — so the row at
/// the bottom is the actual decision the geofence will make, not a mock-up.
struct StopScheduleEditView: View {
    @Bindable var stop: BusStop

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) private var locationManager

    @Query(sort: \BusStop.sortIndex, order: .forward) private var allStops: [BusStop]

    /// Ticks once a minute so the live decision doesn't go stale while the
    /// sheet is open — the window boundary can pass while you're looking at it.
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// `Calendar.current.weekdaySymbols` is Sunday-first, matching our bit 0.
    private var weekdayOrder: [Int] { [2, 3, 4, 5, 6, 7, 1] }  // Mon…Sun for display

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("为此站点启用定时", isOn: Binding(
                        get: { stop.isScheduleEnabled },
                        set: { stop.isScheduleEnabled = $0; persist() }
                    ))
                } footer: {
                    Text("开启后,这个站点会常驻监测。App 关闭、锁屏、甚至重启手机后依然有效,不需要每趟手动启动。")
                }

                Section("生效星期") {
                    HStack(spacing: 6) {
                        ForEach(weekdayOrder, id: \.self) { weekday in
                            weekdayChip(weekday)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    DatePicker(
                        "开始",
                        selection: minuteBinding(\.startMinute),
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "结束",
                        selection: minuteBinding(\.endMinute),
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("生效时段")
                } footer: {
                    windowFooter
                }

                Section("现在") {
                    liveDecisionRow
                }
            }
            .navigationTitle(stop.name)
            .navigationBarTitleDisplayMode(.inline)
            // The DatePicker follows the system locale, which on an
            // English-language phone means a 12-hour AM/PM wheel. The spec is
            // 24-hour, so pin the locale rather than the system's.
            .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.bold()
                }
            }
            .onReceive(tick) { now = $0 }
        }
    }

    // MARK: - Pieces

    private func weekdayChip(_ weekday: Int) -> some View {
        let selected = stop.isWeekdaySelected(weekday)
        return Button {
            stop.setWeekday(weekday, selected: !selected)
            persist()
        } label: {
            Text(ScheduleEvaluator.weekdayName(weekday).replacingOccurrences(of: "周", with: ""))
                .font(.subheadline.weight(selected ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var windowFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if stop.startMinute == stop.endMinute {
                Label(
                    "开始和结束相同,这是一个空时段,永远不会触发。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            } else if stop.crossesMidnight {
                Label(
                    "跨夜时段:\(ScheduleEvaluator.timeString(stop.startMinute)) 到次日 \(ScheduleEvaluator.timeString(stop.endMinute))",
                    systemImage: "moon.stars"
                )
            }
            Text("按 24 小时制,包含开始时刻、不含结束时刻。")
        }
        .font(.caption)
    }

    private var liveDecisionRow: some View {
        let decision = locationManager.currentDecision(for: stop, at: now)
        return HStack(spacing: 10) {
            Image(systemName: decision.isFiring ? "checkmark.circle.fill" : "moon.zzz.fill")
                .foregroundStyle(decision.isFiring ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(decision.isFiring ? "生效中" : "未生效")
                    .font(.headline)
                Text(decision.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Plumbing

    /// Bridges minutes-since-midnight to the `Date` a DatePicker wants. Only
    /// the hour and minute components are ever read back.
    private func minuteBinding(_ key: ReferenceWritableKeyPath<BusStop, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = stop[keyPath: key]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                stop[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                persist()
            }
        )
    }

    /// Save, then re-register geofences so the switches take effect
    /// immediately rather than at next launch.
    private func persist() {
        try? modelContext.save()
        locationManager.reconcileScheduleRegions(with: allStops)
    }
}
