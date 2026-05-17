import SwiftUI
import SwiftData

@main
struct FinanceTrackerApp: App {

    // MARK: - DI Container
    @State private var appContainer: AppContainer

    // MARK: - SwiftData ModelContainer (single source of truth)
    private let modelContainer: ModelContainer

    // MARK: - Onboarding
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false

    // MARK: - iCloud — opt-in. Requires paid Apple Developer Program + iCloud
    // capability enabled in Xcode → Signing & Capabilities. Personal/free
    // signing teams cannot enable CloudKit, so this stays off by default.
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false

    // MARK: - Theme — "system" | "light" | "dark"
    @AppStorage("themePreference") private var themePreference: String = "dark"

    // MARK: - Face ID lock
    @AppStorage("faceIDEnabled") private var faceIDEnabled: Bool = false
    @State private var isUnlocked: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    private var preferredScheme: ColorScheme? {
        switch themePreference {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil   // .system → follow device
        }
    }

    // MARK: - Init

    init() {
        let schema = Schema([
            TransactionModel.self,
            AccountModel.self,
            BudgetModel.self,
            MerchantRuleModel.self,
            CardStatementModel.self,
            GoalModel.self
        ])

        // iCloud is gated behind a runtime preference. To enable:
        //   1. Paid Apple Developer Program account
        //   2. Xcode → Target → Signing & Capabilities → + Capability → iCloud
        //      → ✓ CloudKit → container: iCloud.com.sovinnour.FinanceTracker
        //   3. Toggle "iCloud Sync" in app Settings
        // If the capability isn't actually enabled in Xcode but the toggle is
        // on, ModelContainer init will throw — we fall back to local-only.
        let useCloud = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: useCloud ? .automatic : .none
        )

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // CloudKit may have failed (capability not enabled / free signing team).
            // Fall back to local-only so the app still launches.
            if useCloud {
                let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                do {
                    container = try ModelContainer(for: schema, configurations: [local])
                    UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
                } catch {
                    fatalError("Failed to create ModelContainer: \(error)")
                }
            } else {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

        self.modelContainer = container
        // AppContainer creates repos from the main context and seeds sample data.
        _appContainer = State(initialValue: AppContainer(modelContext: container.mainContext))
        // Attach merchant rule store to the same context.
        MainActor.assumeIsolated {
            MerchantRuleStore.shared.attach(modelContext: container.mainContext)
        }

        // Request notification permission for card due-date reminders.
        NotificationManager.shared.requestPermission()
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(\.appContainer, appContainer)
                    .modelContainer(modelContainer)
                    .preferredColorScheme(preferredScheme)
                    .fullScreenCover(isPresented: Binding(
                        get: { !hasOnboarded },
                        set: { _ in }
                    )) {
                        OnboardingView(hasOnboarded: $hasOnboarded)
                    }
                    .onOpenURL { url in
                        DeepLinkHandler.shared.handle(url)
                    }

                // Lock overlay — covers everything while the app is locked
                if faceIDEnabled && !isUnlocked {
                    LockScreenView(onUnlock: { isUnlocked = true })
                        .preferredColorScheme(.dark)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isUnlocked)
            .onChange(of: scenePhase) { _, phase in
                // Re-lock whenever the app leaves the foreground.
                if phase == .background || phase == .inactive {
                    if faceIDEnabled { isUnlocked = false }
                }
            }
            .onChange(of: faceIDEnabled) { _, enabled in
                // If the user turns the toggle off, ensure the app stays unlocked.
                if !enabled { isUnlocked = true }
            }
            .onAppear {
                // Start unlocked if Face ID isn't enabled.
                if !faceIDEnabled { isUnlocked = true }
            }
        }
    }
}
