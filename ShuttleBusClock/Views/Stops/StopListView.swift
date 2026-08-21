import SwiftUI
import SwiftData
import CoreLocation
import UIKit

/// Lists all saved bus stops. One tap arms the trip; the row shows live
/// distance during the arm.
struct StopListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) private var locationManager

    @Query(sort: \BusStop.sortIndex, order: .forward) private var stops: [BusStop]

    @State private var presentingAlwaysUpgrade = false
    @State private var activeSheet: ActiveSheet?

    /// One sheet modifier, one piece of state. Stacking several `.sheet`
    /// modifiers on the same view is unreliable in SwiftUI — they compete, and
    /// the loser presents a dimming layer with no content behind it.
    private enum ActiveSheet: Identifiable {
        case newStop
        case schedule(BusStop)
        case trip
        case diagnostics

        var id: String {
            switch self {
            case .newStop:            return "new"
            case .diagnostics:        return "diagnostics"
            case .schedule(let stop): return "schedule-\(stop.persistentModelID.hashValue)"
            case .trip:               return "trip"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if stops.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("我的站点")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .newStop
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .newStop:            StopEditView(mode: .create)
                case .schedule(let stop): StopScheduleEditView(stop: stop)
                case .trip:               ArmedTripView()
                case .diagnostics:        AlarmDiagnosticsView()
                }
            }
            // Raise the trip view when a trip starts, and take it away once the
            // trip ends. Dismissing it by hand leaves `tripState` alone, which
            // is what keeps "返回列表" from doubling as "取消行程".
            .onChange(of: locationManager.tripState) { _, newState in
                if case .armed = newState {
                    activeSheet = .trip
                } else if case .trip = activeSheet {
                    activeSheet = nil
                }
            }
            // Re-register geofences whenever the app comes back to the list,
            // and whenever a stop is added, removed, or edited. iOS keeps the
            // regions across launches, but this is what repairs the set after
            // the user changes something or revokes and restores permission.
            .onAppear { locationManager.reconcileScheduleRegions(with: stops) }
            .onChange(of: stops) { _, newStops in
                locationManager.reconcileScheduleRegions(with: newStops)
            }
            .alert(
                "需要「始终定位」权限",
                isPresented: $presentingAlwaysUpgrade
            ) {
                Button("去设置") {
                    openSettings()
                }
                Button("稍后", role: .cancel) {}
            } message: {
                Text("要让闹钟在 app 关闭后也能工作,需要在「设置 > 隐私 > 定位」中允许「始终」。")
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有站点", systemImage: "mappin.slash")
        } description: {
            Text("点击右上角 + 添加你常坐的班车路线")
        } actions: {
            Button {
                activeSheet = .newStop
            } label: {
                Text("添加站点")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        List {
            if locationManager.tripState.isActive {
                Section {
                    Button {
                        activeSheet = .trip
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bus.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("行程进行中")
                                    .font(.headline)
                                Text("点按查看剩余距离")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if locationManager.backgroundMonitoringWillFail {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("闹钟在后台不会响", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("当前定位权限是「\(LocationManager.authName(locationManager.authorizationStatus))」。锁屏或切到其他 App 后 iOS 不会再唤醒本应用,闹钟不会响。必须改成「始终」。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("去设置修改") { openSettings() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ScheduleStatusCard(stops: stops)
            }

            Section {
                ForEach(stops) { stop in
                    StopRow(stop: stop) { activeSheet = .schedule(stop) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(stop)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            arm(stop)
                        }
                }
            } footer: {
                if let error = locationManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    activeSheet = .diagnostics
                } label: {
                    Label("闹钟诊断记录", systemImage: "stethoscope")
                }
            } footer: {
                Text("闹钟没响时先看这里:能区分「没触发」和「触发了但没出声」。")
            }

            if !locationManager.scheduleLog.isEmpty {
                Section("最近的定时判定") {
                    ForEach(locationManager.scheduleLog.prefix(5)) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.decision.isFiring
                                  ? "bell.fill" : "bell.slash")
                                .foregroundStyle(entry.decision.isFiring ? .red : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.stopName).font(.subheadline)
                                Text(entry.decision.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.at, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func arm(_ stop: BusStop) {
        // Already running this trip? The tap means "show me it again", not
        // "start over" — re-arming would reset the hysteresis state.
        if locationManager.tripState.isActive,
           locationManager.tripState.stopID == stop.persistentModelID {
            activeSheet = .trip
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            openSettings()
        case .authorizedWhenInUse:
            // Step 2 of the permission flow: ask for Always in context.
            locationManager.requestAlwaysAuthorization()
            locationManager.arm(stop: stop)
        case .authorizedAlways:
            locationManager.arm(stop: stop)
        @unknown default:
            locationManager.arm(stop: stop)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Row

private struct StopRow: View {
    @Environment(LocationManager.self) private var locationManager
    let stop: BusStop
    /// Tapping the clock opens the schedule editor; tapping the rest of the
    /// row still arms a manual trip.
    let onScheduleTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "mappin")
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.headline)
                Text(formattedRadius)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if stop.isScheduleEnabled {
                    Text(scheduleSummary)
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            Spacer()

            if isActive, let distance = locationManager.distanceToTarget {
                VStack(alignment: .trailing) {
                    Text(distanceString(distance))
                        .font(.title3.bold())
                        .foregroundStyle(.tint)
                    Text("剩余")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: onScheduleTapped) {
                    Image(systemName: stop.isScheduleEnabled ? "clock.fill" : "clock")
                        .font(.title3)
                        .foregroundStyle(stop.isScheduleEnabled ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var scheduleSummary: String {
        let days = (1...7)
            .filter { stop.isWeekdaySelected($0) }
            .map { ScheduleEvaluator.weekdayName($0).replacingOccurrences(of: "周", with: "") }
        let dayText: String
        switch days.count {
        case 7: dayText = "每天"
        case 0: dayText = "无生效日"
        default: dayText = days.joined()
        }
        return "\(dayText) \(ScheduleEvaluator.timeString(stop.startMinute))–\(ScheduleEvaluator.timeString(stop.endMinute))"
    }

    private var isActive: Bool {
        locationManager.tripState.stopID == stop.persistentModelID
    }

    private var formattedRadius: String {
        let km = stop.radius / 1000
        if km == km.rounded() {
            return "提前 \(Int(km)) km 提醒"
        } else {
            return "提前 \(String(format: "%.1f", km)) km 提醒"
        }
    }

    private func distanceString(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}

#Preview {
    StopListView()
        .environment(LocationManager())
        .modelContainer(PersistenceController.preview)
}