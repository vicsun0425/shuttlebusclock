import Foundation
import MapKit
import Observation

/// Drives place search inside `MapPickerView`.
///
/// Two-step by design: `MKLocalSearchCompleter` gives cheap as-you-type
/// suggestions, but a completion carries no coordinate — picking one still has
/// to be resolved with a real `MKLocalSearch` before we can drop a pin.
@Observable
final class MapSearchManager: NSObject, MKLocalSearchCompleterDelegate {

    /// What the user typed. Assigning drives the completer.
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                completions = []
                completer.cancel()
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    /// As-you-type suggestions for `query`.
    private(set) var completions: [MKLocalSearchCompletion] = []

    /// True while a chosen suggestion is being resolved to coordinates.
    private(set) var isSearching = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var activeSearch: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    /// Bias suggestions toward whatever the user is currently looking at.
    /// Without this, searching "星巴克" ranks by global relevance, not proximity.
    func updateRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    func clear() {
        query = ""
        completions = []
        completer.cancel()
        activeSearch?.cancel()
    }

    /// Resolve a suggestion into a real map item with coordinates.
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        await run(MKLocalSearch(request: MKLocalSearch.Request(completion: completion)))
    }

    /// Free-text search, for when the user hits return instead of tapping a
    /// suggestion. Returns the top hit.
    func search(_ text: String, in region: MKCoordinateRegion?) async -> MKMapItem? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let region { request.region = region }
        return await run(MKLocalSearch(request: request))
    }

    private func run(_ search: MKLocalSearch) async -> MKMapItem? {
        activeSearch?.cancel()
        activeSearch = search
        isSearching = true
        defer { isSearching = false }

        let response = try? await search.start()
        return response?.mapItems.first
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Typing mid-word legitimately produces "no results" errors; treating
        // them as an empty list keeps the UI quiet.
        completions = []
    }
}
