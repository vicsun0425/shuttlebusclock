import SwiftUI
import CoreLocation

/// Two-step permission onboarding. First we ask for "When In Use"; after
/// the user creates at least one stop and taps "Arm trip", we ask for
/// "Always". This pacing matters — Apple rejects apps that ask for Always
/// permission on first launch.
struct PermissionOnboardingView: View {
    @Environment(LocationManager.self) private var locationManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "bus.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("班车闹钟")
                    .font(.largeTitle.bold())
                Text("再也不会坐过站")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "location.fill",
                    title: "实时追踪",
                    detail: "GPS 实时计算你距离站点还有多远"
                )
                FeatureRow(
                    icon: "bell.and.waves.and.waveform.fill",
                    title: "大声闹钟",
                    detail: "静音模式下也能响铃,把你叫醒"
                )
                FeatureRow(
                    icon: "moon.zzz.fill",
                    title: "后台运行",
                    detail: "锁屏或切到其他 app 后仍持续工作"
                )
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button(action: { locationManager.requestWhenInUseAuthorization() }) {
                    Text("开始使用")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }

                Text("下一步会请求定位权限,以便在行程中持续监测距离。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    PermissionOnboardingView()
        .environment(LocationManager())
}