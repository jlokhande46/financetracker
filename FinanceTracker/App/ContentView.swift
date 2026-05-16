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

    // MARK: - Badge Counts
    @State private var unreadInsightCount: Int = 0
    @State private var pendingReviewCount: Int = 0

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
        .task {
            guard let c = container else { return }

            if dashboardVM == nil {
                let vm = DashboardViewModel(transactionRepo: c.transactionRepo, budgetRepo: c.budgetRepo, accountRepo: c.accountRepo, cardStatementRepo: c.cardStatementRepo, goalRepo: c.goalRepo)
                dashboardVM = vm
                await vm.load()
                unreadInsightCount = vm.insights.filter { !$0.isRead }.count
                pendingReviewCount = vm.pendingReviewCount
            }

            if analyticsVM == nil {
                let vm = AnalyticsViewModel(transactionRepo: c.transactionRepo, budgetRepo: c.budgetRepo)
                analyticsVM = vm
                await vm.load()
            }

            if budgetsVM == nil {
                let vm = BudgetsViewModel(transactionRepo: c.transactionRepo, budgetRepo: c.budgetRepo)
                budgetsVM = vm
                await vm.load()
            }
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
            .badge(unreadInsightCount > 0 ? unreadInsightCount : 0)
            .tag(Tab.home)

            // Transactions
            TransactionFeedView(transactionRepo: container.transactionRepo, accountRepo: container.accountRepo)
            .tabItem {
                Label(Tab.transactions.title, systemImage: Tab.transactions.icon)
            }
            .badge(pendingReviewCount > 0 ? pendingReviewCount : 0)
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
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.bgSecondary)

        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.textSecondary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.textSecondary)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.brandPrimary)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.brandPrimary)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

