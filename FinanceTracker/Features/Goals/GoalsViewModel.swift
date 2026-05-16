import SwiftUI
import Observation

@Observable
@MainActor
final class GoalsViewModel {
    var goals: [GoalEntity] = []
    var showAddSheet: Bool = false
    var editingGoal: GoalEntity? = nil
    var contributionGoal: GoalEntity? = nil

    private let repo: GoalRepositoryImpl

    init(repo: GoalRepositoryImpl) {
        self.repo = repo
    }

    func load() {
        goals = repo.fetchAll()
    }

    func save(_ goal: GoalEntity) {
        repo.save(goal)
        load()
    }

    func delete(_ id: UUID) {
        repo.delete(id)
        load()
    }

    func addContribution(goalId: UUID, amount: Decimal) {
        repo.addContribution(goalId: goalId, amount: amount)
        load()
    }
}
