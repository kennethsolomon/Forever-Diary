import SwiftUI
import SwiftData

@main
struct ForeverDiaryApp: App {
    let container: ModelContainer
    let cognitoAuth: CognitoAuthService
    let googleAuth: GoogleAuthService
    let syncService: SyncService

    @Environment(\.scenePhase) private var scenePhase

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

        let auth = CognitoAuthService()
        let api = APIClient(authService: auth)
        cognitoAuth = auth
        googleAuth = GoogleAuthService()
        syncService = SyncService(apiClient: api, authService: auth, container: resolvedContainer)
    }

    var body: some Scene {
        WindowGroup {
            if cognitoAuth.isAuthenticated {
                ContentView()
                    .environment(syncService)
                    .environment(cognitoAuth)
                    .task { await startSync() }
            } else {
                SignInView()
                    .environment(cognitoAuth)
                    .environment(googleAuth)
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard cognitoAuth.isAuthenticated else { return }
            if phase == .active {
                Task { await syncService.syncAll() }
                syncService.startPeriodicSync()
            } else if phase == .background {
                syncService.stopPeriodicSync()
            }
        }
    }

    private func startSync() async {
        let isTestHost = NSClassFromString("XCTestCase") != nil
        guard !isTestHost else { return }

        try? await Task.sleep(for: .seconds(2))
        await syncService.syncAll()

        let seedCtx = ModelContext(container)
        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: seedCtx)
        await syncService.deduplicateTemplates()
        await syncService.deduplicateCheckInValues()
    }
}
