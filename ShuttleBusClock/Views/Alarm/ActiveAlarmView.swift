import SwiftUI

/// Full-screen alarm UI. The user must explicitly acknowledge to dismiss.
/// Audio continues playing until `AlarmManager.stop()` is called.
struct ActiveAlarmView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(AlarmManager.self) private var alarmManager

    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.red.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: pulse
                    )

                VStack(spacing: 8) {
                    Text("即将到达")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    if let name = alarmManager.activeStopName {
                        Text(name)
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    if let meters = alarmManager.activeDistance {
                        Text(distanceString(meters))
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                Button {
                    locationManager.dismissAlarm()
                } label: {
                    Text("我醒了")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 48)
            }
        }
        .onAppear { pulse = true }
    }

    private func distanceString(_ meters: Double) -> String {
        if meters < 1000 {
            return "还有 \(Int(meters)) 米"
        } else {
            return String(format: "还有 %.1f 公里", meters / 1000)
        }
    }
}

#Preview {
    ActiveAlarmView()
        .environment(LocationManager())
        .environment(AlarmManager())
}