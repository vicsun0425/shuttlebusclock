import SwiftUI
import SwiftData

/// The app-wide master switch, plus a readout of how many geofences
/// CoreLocation actually accepted.
///
/// The count comes from `didStartMonitoringFor` callbacks, not from what we
/// asked for — a registration that silently failed would otherwise look
/// identical to one that worked until the morning it didn't.
struct ScheduleStatusCard: View {
    @Environment(LocationManager.self) private var locationManager

    let stops: [BusStop]

    @State private var masterOn = ScheduleSettings.masterEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $masterOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("定时监测")
                        .font(.headline)
                    Text("到点自动守候,无需每趟手动启动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: masterOn) { _, newValue in
                ScheduleSettings.masterEnabled = newValue
                locationManager.reconcileScheduleRegions(with: stops)
            }

            Label(statusText, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch locationManager.scheduleStatus {
        case .off:
            return "已关闭,所有站点仍可手动点按启动"
        case .noEligibleStops:
            return "已开启,但还没有站点启用定时"
        case .active(let registered, let enabled):
            return "已注册 \(registered)/\(enabled) 个站点的监测围栏"
        case .overLimit(let registered, let enabled):
            return "已启用 \(enabled) 个,超出 iOS 上限,仅注册前 \(registered) 个"
        case .failed(let message):
            return message
        }
    }

    private var statusIcon: String {
        switch locationManager.scheduleStatus {
        case .off:              return "moon.zzz"
        case .noEligibleStops:  return "info.circle"
        case .active:           return "checkmark.circle"
        case .overLimit:        return "exclamationmark.triangle"
        case .failed:           return "xmark.octagon"
        }
    }

    private var statusColor: Color {
        switch locationManager.scheduleStatus {
        case .active:                       return .green
        case .overLimit, .failed:           return .orange
        case .off, .noEligibleStops:        return .secondary
        }
    }
}
