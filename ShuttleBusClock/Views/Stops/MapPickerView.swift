import SwiftUI
import MapKit
import CoreLocation

/// Modal map view for selecting a destination. The user can search for a place,
/// or pan/zoom and tap to drop a pin; the returned coordinate is what gets saved.
struct MapPickerView: View {
    let initialCoordinate: CLLocationCoordinate2D?
    let onPick: (CLLocationCoordinate2D, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition
    @State private var picked: CLLocationCoordinate2D?
    /// Place name when the pin came from search; nil when tapped manually.
    @State private var pickedName: String?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var search = MapSearchManager()
    @FocusState private var searchFocused: Bool

    init(initialCoordinate: CLLocationCoordinate2D?, onPick: @escaping (CLLocationCoordinate2D, String?) -> Void) {
        self.initialCoordinate = initialCoordinate
        self.onPick = onPick

        let center: CLLocationCoordinate2D
        if let initialCoordinate {
            center = initialCoordinate
        } else {
            center = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074) // 北京
        }
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map
                searchOverlay
            }
            .safeAreaInset(edge: .bottom) { readout }
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确定") {
                        if let picked {
                            onPick(picked, pickedName)
                        }
                        dismiss()
                    }
                    .bold()
                    .disabled(picked == nil)
                }
            }
        }
    }

    // MARK: - Pieces

    private var map: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let picked {
                    Marker(pickedName ?? "选定位置", coordinate: picked)
                        .tint(.red)
                }
            }
            .onTapGesture { screenPoint in
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                searchFocused = false
                // A hand-dropped pin has no place name to carry back.
                apply(coordinate: coord, name: nil, recenter: false)
            }
            .onMapCameraChange { context in
                visibleRegion = context.region
                search.updateRegion(context.region)
            }
        }
    }

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索地点、地址", text: $search.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit(runFreeTextSearch)

                if search.isSearching {
                    ProgressView()
                } else if !search.query.isEmpty {
                    Button {
                        search.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            if searchFocused && !search.completions.isEmpty {
                suggestions
            }

            if let error = search.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var suggestions: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(search.completions, id: \.self) { completion in
                    Button {
                        select(completion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)

                    Divider()
                }
            }
        }
        .frame(maxHeight: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }

    private var readout: some View {
        Group {
            if let picked {
                VStack(spacing: 2) {
                    if let pickedName {
                        Text(pickedName)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(String(format: "%.5f, %.5f", picked.latitude, picked.longitude))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
            } else {
                Text("搜索地点,或点击地图选择位置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func select(_ completion: MKLocalSearchCompletion) {
        searchFocused = false
        Task {
            guard let item = await search.resolve(completion) else { return }
            apply(
                coordinate: item.placemark.coordinate,
                name: item.name ?? completion.title,
                recenter: true
            )
        }
    }

    private func runFreeTextSearch() {
        let text = search.query
        searchFocused = false
        Task {
            guard let item = await search.search(text, in: visibleRegion) else { return }
            apply(coordinate: item.placemark.coordinate, name: item.name, recenter: true)
        }
    }

    private func apply(coordinate: CLLocationCoordinate2D, name: String?, recenter: Bool) {
        picked = coordinate
        pickedName = name
        guard recenter else { return }
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
}

#Preview {
    MapPickerView(initialCoordinate: nil) { _, _ in }
}
