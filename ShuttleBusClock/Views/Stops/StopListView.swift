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

    @State private var presentingNewStop = false
    @State private var presentingAlwaysUpgrade = false

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
                        presentingNewStop = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $presentingNewStop) {
                StopEditView(mode: .create)
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
                presentingNewStop = true
            } label: {
                Text("添加站点")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(stops) { stop in
                    StopRow(stop: stop)
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
        }
    }

    // MARK: - Actions

    private func arm(_ stop: BusStop) {
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
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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