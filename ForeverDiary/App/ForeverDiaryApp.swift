import SwiftUI
import SwiftData

@main
struct ForeverDiaryApp: App {
    let container: ModelContainer
    let authService: CognitoAuthService
    let syncService: SyncService

    init() {
        let schema = Schema([
            DiaryEntry.self,
            CheckInTemplate.self,
            CheckInValue.self,
            PhotoAsset.self
        ])

        let isTestHost = NSClassFromString("XCTestCase") != nil
        let resolvedContainer: ModelContainer

        if isTestHost {
            let config = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                resolvedContainer = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Test ModelContainer failed: \(error.localizedDescription)")
            }
        } else {
            let localConfig = ModelConfiguration(
                "ForeverDiary",
                schema: schema,
                cloudKitDatabase: .none
            )

            if let localContainer = try? ModelContainer(for: schema, configurations: localConfig) {
                resolvedContainer = localContainer
            } else {
                let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                if let memoryContainer = try? ModelContainer(for: schema, configurations: memoryConfig) {
                    resolvedContainer = memoryContainer
                } else {
                    fatalError("Failed to create any ModelContainer")
                }
            }
        }

        container = resolvedContainer
        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: container.mainContext)

        // Services are created in all modes (needed for @Environment in views).
        // Init has no network side effects; startSync() guards against test mode.
        let auth = CognitoAuthService()
        let api = APIClient(authService: auth)
        authService = auth
        syncService = SyncService(apiClient: api, authService: auth, container: resolvedContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(syncService)
                .task {
                    await startSync()
                }
        }
        .modelContainer(container)
    }

    private func startSync() async {
        let isTestHost = NSClassFromString("XCTestCase") != nil
        guard !isTestHost else { return }

        do {
            _ = try await authService.authenticate()
            try? await Task.sleep(for: .seconds(2))
            await syncService.syncAll()
        } catch {
            print("[ForeverDiary] Auth/sync init failed: \(error.localizedDescription)")
        }
    }
}
