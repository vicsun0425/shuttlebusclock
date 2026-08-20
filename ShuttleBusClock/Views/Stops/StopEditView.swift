import SwiftUI
import SwiftData
import CoreLocation

/// Create / edit a single bus stop. Lets the user drop a pin on a map
/// (or use current location) and pick a radius preset.
struct StopEditView: View {
    enum Mode {
        case create
        case edit(BusStop)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) private var locationManager

    @State private var name: String = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var radius: Double = 3000
    @State private var presentingMapPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如:公司、家", text: $name)
                        .textInputAutocapitalization(.never)
                }

                Section("位置") {
                    if let coord = coordinate {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                    .font(.subheadline)
                                    .monospaced()
                            }
                        }
                    } else {
                        Text("未选择")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        presentingMapPicker = true
                    } label: {
                        Label("在地图上选择", systemImage: "map")
                    }

                    if let here = locationManager.currentLocation {
                        Button {
                            coordinate = here.coordinate
                        } label: {
                            Label("使用当前位置", systemImage: "location.fill")
                        }
                    }
                }

                Section("提醒距离") {
                    Picker("半径", selection: $radius) {
                        ForEach(BusStop.RadiusPreset.allCases) { preset in
                            Text(preset.label).tag(preset.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !BusStop.RadiusPreset.allCases.contains(where: { $0.matches(radius: radius) }) {
                        Text("自定义:\(Int(radius / 1000)) km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑站点" : "添加站点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .bold()
                }
            }
            .sheet(isPresented: $presentingMapPicker) {
                // Fall back to where the user is now, so the map (and search
                // results) start out nearby instead of in Beijing.
                MapPickerView(
                    initialCoordinate: coordinate ?? locationManager.currentLocation?.coordinate
                ) { picked, placeName in
                    coordinate = picked
                    // Searching for a place already told us what it's called;
                    // don't make the user retype it.
                    if let placeName, name.trimmingCharacters(in: .whitespaces).isEmpty {
                        name = placeName
                    }
                }
            }
            .onAppear(perform: populateFromMode)
        }
    }

    // MARK: - Helpers

    private var isEditing: Bool {
        if case .edit = mode { return true } else { return false }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && coordinate != nil
    }

    private func populateFromMode() {
        if case .edit(let stop) = mode {
            name = stop.name
            coordinate = stop.coordinate
            radius = stop.radius
        }
    }

    private func save() {
        guard let coord = coordinate else { return }
        switch mode {
        case .create:
            let next = BusStop(
                name: name.trimmingCharacters(in: .whitespaces),
                latitude: coord.latitude,
                longitude: coord.longitude,
                radius: radius,
                sortIndex: nextSortIndex()
            )
            modelContext.insert(next)
        case .edit(let stop):
            stop.name = name.trimmingCharacters(in: .whitespaces)
            stop.latitude = coord.latitude
            stop.longitude = coord.longitude
            stop.radius = radius
        }
        try? modelContext.save()
        dismiss()
    }

    private func nextSortIndex() -> Int {
        let descriptor = FetchDescriptor<BusStop>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count
    }
}

#Preview("Create") {
    StopEditView(mode: .create)
        .environment(LocationManager())
        .modelContainer(PersistenceController.preview)
}