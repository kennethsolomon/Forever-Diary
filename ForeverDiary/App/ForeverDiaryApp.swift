import SwiftUI
import SwiftData

@main
struct ForeverDiaryApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            DiaryEntry.self,
            CheckInTemplate.self,
            CheckInValue.self,
            PhotoAsset.self
        ])

        let isTestHost = NSClassFromString("XCTestCase") != nil

        if isTestHost {
            // Use in-memory, local-only storage when running as test host
            let config = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            container = try! ModelContainer(for: schema, configurations: config)
        } else {
            // Try CloudKit first, fall back to local-only if unavailable
            let cloudConfig = ModelConfiguration(
                "ForeverDiary",
                schema: schema,
                cloudKitDatabase: .automatic
            )
            let localConfig = ModelConfiguration(
                "ForeverDiary",
                schema: schema,
                cloudKitDatabase: .none
            )

            if let cloudContainer = try? ModelContainer(for: schema, configurations: cloudConfig) {
                container = cloudContainer
            } else if let localContainer = try? ModelContainer(for: schema, configurations: localConfig) {
                container = localContainer
            } else {
                fatalError("Failed to create ModelContainer")
            }
        }

        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
