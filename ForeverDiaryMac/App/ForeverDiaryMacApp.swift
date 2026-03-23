import SwiftUI
import SwiftData

@main
struct ForeverDiaryMacApp: App {
    let container: ModelContainer
    let cognitoAuth: CognitoAuthService
    let googleAuth: GoogleAuthService
    let syncService: SyncService
    let networkMonitor: NetworkMonitor
    let speechService: SpeechService
    @AppStorage("fontScale") private var fontScale: Double = 1.0

    init() {
        let schema = Schema([
            DiaryEntry.self,
            CheckInTemplate.self,
            CheckInValue.self,
            PhotoAsset.self
        ])

        let localConfig = ModelConfiguration(
            "ForeverDiaryMac",
            schema: schema,
            cloudKitDatabase: .none
        )

        let resolvedContainer: ModelContainer
        if let c = try? ModelContainer(for: schema, configurations: localConfig) {
            resolvedContainer = c
        } else {
            let memConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            resolvedContainer = (try? ModelContainer(for: schema, configurations: memConfig))!
        }

        container = resolvedContainer

        let auth = CognitoAuthService()
        let api = APIClient(authService: auth)
        let monitor = NetworkMonitor()
        monitor.start()
        cognitoAuth = auth
        googleAuth = GoogleAuthService()
        networkMonitor = monitor
        syncService = SyncService(apiClient: api, authService: auth, container: resolvedContainer, networkMonitor: monitor)
        speechService = SpeechService()
    }

    var body: some Scene {
        WindowGroup {
            MacRootView(container: container)
                .environment(syncService)
                .environment(cognitoAuth)
                .environment(googleAuth)
                .environment(networkMonitor)
                .environment(speechService)
                .environment(\.fontScale, fontScale)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Go to Today") {
                    NotificationCenter.default.post(name: .goToToday, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    fontScale = min(2.0, fontScale + 0.1)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    fontScale = max(0.75, fontScale - 0.1)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Zoom") {
                    fontScale = 1.0
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsMacView()
                .environment(syncService)
                .environment(cognitoAuth)
                .environment(networkMonitor)
                .environment(speechService)
                .environment(\.fontScale, fontScale)
                .modelContainer(container)
        }
    }
}

// MARK: - Root View (applies theme + auth gate)

struct MacRootView: View {
    let container: ModelContainer

    @Environment(SyncService.self) private var syncService
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Environment(GoogleAuthService.self) private var googleAuth
    @AppStorage("appTheme") private var storedTheme: String = AppTheme.system.rawValue

    var body: some View {
        Group {
            if cognitoAuth.isAuthenticated {
                MainWindowView()
                    .environment(syncService)
                    .environment(cognitoAuth)
                    .task { await startSync() }
            } else {
                SignInMacView()
                    .environment(cognitoAuth)
                    .environment(googleAuth)
            }
        }
        .preferredColorScheme(AppTheme(rawValue: storedTheme)?.colorScheme ?? nil)
    }

    private func startSync() async {
        try? await Task.sleep(for: .seconds(2))
        await syncService.syncAll()

        let seedCtx = ModelContext(container)
        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: seedCtx)
        await syncService.deduplicateTemplates()
        await syncService.deduplicateCheckInValues()
        syncService.startPeriodicSync()
    }
}
