import SwiftUI

/// Shows the persistent alarm breadcrumb trail.
///
/// Exists so a silent failure leaves evidence. If the alarm doesn't go off,
/// this answers the only question that matters: did it try and fail to make
/// noise, or did it never trigger at all?
struct AlarmDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = AlarmDiagnostics.all()

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "还没有记录",
                        systemImage: "text.magnifyingglass",
                        description: Text("启动一次行程后,这里会记录闹钟的每一步。")
                    )
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.event)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(entry.at, format: .dateTime.month().day().hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !entry.detail.isEmpty {
                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("闹钟诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空") {
                        AlarmDiagnostics.clear()
                        entries = []
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.bold()
                }
            }
        }
    }
}
