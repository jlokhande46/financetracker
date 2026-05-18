import SwiftUI

struct ContentView: View {

    @Environment(\.appContainer) private var container
    @State private var selectedTab: Tab = .home

    // MARK: - Tab Definition
    enum Tab: Int, CaseIterable {
        case home, transactions, analytics, budgets, profile

        var title: String {
            switch self {
            case .home:         return "Home"
            case .transactions: return "Transactions"
            case .analytics:    return "Analytics"
            case .budgets:      return "Budgets"
            case .profile:      return "Profile"
            }
        }

        var icon: String {
            switch self {
            case .home:         return "house.fill"
            case .transactions: return "list.bullet.rectangle"
            case .analytics:    return "chart.bar.fill"
            case .budgets:      return "target"
            case .profile:      return "person.crop.circle.fill"
            }
        }
    }

    // MARK: - ViewModels (created once the container is injected)
    @State private var dashboardVM: DashboardViewModel?
    @State private var analyticsVM: AnalyticsViewModel?
    @State private var budgetsVM: BudgetsViewModel?

    private var deepLink: DeepLinkHandler { DeepLinkHandler.shared }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if let container {
                tabContent(container: container)
            } else {
                LoadingView()
            }
        }
        .onChange(of: deepLink.pendingSMSText) { _, text in
            if text != nil {
                selectedTab = .transactions
            }
        }
        .onAppear {
            // Cold-launch: deep link may have set pendingSMSText before this
            // view mounted, in which case .onChange will not fire.
            if deepLink.pendingSMSText?.isEmpty == false {
                selectedTab = .transactions
            }
        }
        .task {
            guard let c = container, dashboardVM == nil else { return }

            // Create all VMs before any load so every tab shows its loading state immediately.
            let dvm = DashboardViewModel(transactionRepo: c.transactionRepo, budgetRepo: c.budgetRepo,
                                         accountRepo: c.accountRepo, cardStatementRepo: c.cardStatementRepo,
                                         goalRepo: c.goalRepo)
            let avm = AnalyticsViewModel(transactionRepo: c.transactionRepo, budgetRepo: c.budgetRepo)
            let bvm = BudgetsViewModel(transactionRepo: c.transactionRepo, budgetRepo: c.budgetRepo)

            dashboardVM = dvm
            analyticsVM = avm
            budgetsVM = bvm

            await dvm.load()
            await avm.load()
            await bvm.load()
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(container: AppContainer) -> some View {
        TabView(selection: $selectedTab) {

            // Home / Dashboard
            Group {
                if let vm = dashboardVM {
                    DashboardView(viewModel: vm)
                } else {
                    LoadingView()
                }
            }
            .tabItem {
                Label(Tab.home.title, systemImage: Tab.home.icon)
            }
            .badge(dashboardVM?.unreadInsightCount ?? 0)
            .tag(Tab.home)

            // Transactions
            TransactionFeedView(transactionRepo: container.transactionRepo, accountRepo: container.accountRepo)
            .tabItem {
                Label(Tab.transactions.title, systemImage: Tab.transactions.icon)
            }
            .badge(dashboardVM?.pendingReviewCount ?? 0)
            .tag(Tab.transactions)

            // Analytics
            Group {
                if let vm = analyticsVM {
                    AnalyticsView(viewModel: vm)
                } else {
                    LoadingView()
                }
            }
            .tabItem {
                Label(Tab.analytics.title, systemImage: Tab.analytics.icon)
            }
            .tag(Tab.analytics)

            // Budgets
            Group {
                if let vm = budgetsVM {
                    BudgetsView(viewModel: vm)
                } else {
                    LoadingView()
                }
            }
            .tabItem {
                Label(Tab.budgets.title, systemImage: Tab.budgets.icon)
            }
            .tag(Tab.budgets)

            // Profile / Settings
            SettingsView()
                .tabItem {
                    Label(Tab.profile.title, systemImage: Tab.profile.icon)
                }
                .tag(Tab.profile)
        }
        .tint(.brandPrimary)
        .onAppear {
            styleTabBar()
        }
    }

    // MARK: - UITabBar Styling

    private func styleTabBar() {
        // Dynamic backgrounds via UIColor providers so the tab bar follows light/dark.
        let bgColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: "#141418"))
                : UIColor(Color(hex: "#FFFFFF"))
        }
        let normalIconColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: "#8E8E99"))
                : UIColor(Color(hex: "#6C6C72"))
        }

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bgColor

        appearance.stackedLayoutAppearance.normal.iconColor = normalIconColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalIconColor
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.brandPrimary)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.brandPrimary)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

