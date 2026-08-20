import Foundation
import SwiftData

/// Centralized SwiftData `ModelContainer` setup.
///
/// Kept tiny on purpose — SwiftData models live in their own files; this
/// file exists so previews, tests, and the app all share one place to
/// change the schema or storage location.
enum PersistenceController {
    /// The single container used by the running app.
    static let shared: ModelContainer = {
        let schema = Schema([BusStop.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// In-memory container preloaded with one sample stop, for SwiftUI
    /// previews and unit tests.
    @MainActor
    static let preview: ModelContainer = {
        let schema = Schema([BusStop.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let sample = BusStop(
            name: "示例:公司",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 3000
        )
        context.insert(sample)
        return container
    }()
}