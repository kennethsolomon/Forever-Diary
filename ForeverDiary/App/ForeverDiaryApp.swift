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
        let config = ModelConfiguration(
            "ForeverDiary",
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
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
