import SwiftUI

/// Shown while a trip is armed. Displays live distance to the destination.
///
/// Presented as a sheet, so dismissing it leaves the trip running — the two
/// buttons are deliberately different actions: "返回列表" keeps monitoring,
/// "取消行程" ends it.
struct ArmedTripView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "bus.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("行程进行中")
                    .font(.title2.bold())
                Text("锁屏后仍会持续监测")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(distanceString)
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundStyle(.tint)
                    // A four-digit km reading wraps onto two lines and breaks
                    // the layout at a fixed 96 pt, so let it shrink instead.
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: locationManager.distanceToTarget)
                Text("距下车点")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if let error = locationManager.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("返回列表", systemImage: "chevron.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                }

                Button(role: .destructive) {
                    locationManager.disarm()
                } label: {
                    Label("取消行程", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private var distanceString: String {
        guard let meters = locationManager.distanceToTarget else { return "—" }
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}

#Preview {
    ArmedTripView()
        .environment(LocationManager())
}