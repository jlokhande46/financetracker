import SwiftUI

struct TransactionRowView: View {
    let transaction: TransactionEntity
    var accountChip: String? = nil
    var onTap: (() -> Void)? = nil
    /// Called when the user taps the intent chip, swipes the row, or picks an
    /// option from the context menu. Pass `nil` to clear any override.
    var onSetIntent: ((CategoryIntent?) -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var didFireHaptic: Bool = false

    /// Distance past which a swipe commits the intent change.
    private let swipeCommitThreshold: CGFloat = 80
    /// Max horizontal travel (prevents the row sliding off-screen).
    private let swipeCap: CGFloat = 140

    private var category: CategoryEntity {
        CategoryEntity.find(slug: transaction.categorySlug)
    }

    /// Cycle order when tapping the intent chip:
    /// (no override) → need → want → saving → (no override)
    private func nextIntent(from current: CategoryIntent?) -> CategoryIntent? {
        switch current {
        case .none:   return .need
        case .need:   return .want
        case .want:   return .saving
        case .saving: return nil
        }
    }

    private var amountColor: Color {
        transaction.isCredit ? .incomeGreen : .textPrimary
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        let str = formatter.string(from: transaction.amount as NSDecimalNumber) ?? "₹\(transaction.amount)"
        return transaction.isCredit ? "+\(str)" : str
    }

    private var formattedTime: String? {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: transaction.date)
        // Hide midnight (PDF imports default to 00:00 — meaningless to display)
        if comps.hour == 0 && comps.minute == 0 { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: transaction.date)
    }

    var body: some View {
        ZStack {
            swipeRevealBackground
            rowContent
                .background(Color.bgCard)
                .offset(x: dragOffset)
                .gesture(swipeGesture, including: transaction.isCredit ? .subviews : .all)
                .onTapGesture { onTap?() }
        }
        .clipped()
        .contextMenu { contextMenuItems }
    }

    // MARK: - Foreground content (the row itself)

    private var rowContent: some View {
        HStack(spacing: Spacing.md) {

            // Pending review left accent
            if transaction.needsReview {
                Rectangle()
                    .fill(Color.warningAmber)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

                // Category Icon
                CategoryIconView(slug: transaction.categorySlug, size: 44)

                // Center content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.xs) {
                        Text(transaction.merchantName.isEmpty ? transaction.merchantRaw : transaction.merchantName)
                            .font(.titleMedium)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        if transaction.isRecurring {
                            Image(systemName: "repeat")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.brandPrimary)
                        }

                        if !transaction.isCredit, let intent = transaction.effectiveIntent {
                            // Always show the row's current need/want/saving label.
                            // Tap cycles through; long-press opens the context menu.
                            Button {
                                onSetIntent?(nextIntent(from: transaction.intentOverride))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: intent.icon)
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(intent.displayName)
                                        .font(.micro)
                                }
                                .foregroundStyle(intent.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(intent.color.opacity(transaction.intentOverride == nil ? 0.10 : 0.20))
                                .overlay(
                                    Capsule().stroke(intent.color.opacity(transaction.intentOverride == nil ? 0 : 0.4), lineWidth: 0.5)
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if transaction.needsReview {
                            Text("Review")
                                .font(.micro)
                                .foregroundStyle(Color.warningAmber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.warningAmber.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    HStack(spacing: Spacing.xs) {
                        SourceBadge(source: transaction.source)

                        if let time = formattedTime {
                            Text(time)
                                .font(.micro)
                                .foregroundStyle(Color.textTertiary)
                        }

                        if let chip = accountChip {
                            if formattedTime != nil {
                                Text("·")
                                    .font(.micro)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Image(systemName: "creditcard")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                            Text(chip)
                                .font(.micro)
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Right: Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formattedAmount)
                        .font(.amount(15))
                        .foregroundStyle(amountColor)
                        .contentTransition(.numericText())
                }
            }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, transaction.needsReview ? 0 : Spacing.base)
        .contentShape(Rectangle())
    }

    // MARK: - Swipe reveal layers

    /// The Need / Want labels that sit behind the row and peek through as the user drags.
    @ViewBuilder
    private var swipeRevealBackground: some View {
        if !transaction.isCredit {
            HStack(spacing: 0) {
                // Drag-right (positive offset) reveals NEED on the left edge.
                HStack(spacing: 8) {
                    Image(systemName: CategoryIntent.need.icon)
                    Text("Need")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(width: max(0, dragOffset), alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(CategoryIntent.need.color)
                .opacity(dragOffset > 0 ? 1 : 0)

                Spacer(minLength: 0)

                // Drag-left (negative offset) reveals WANT on the right edge.
                HStack(spacing: 8) {
                    Text("Want")
                    Image(systemName: CategoryIntent.want.icon)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(width: max(0, -dragOffset), alignment: .trailing)
                .frame(maxHeight: .infinity)
                .background(CategoryIntent.want.color)
                .opacity(dragOffset < 0 ? 1 : 0)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Swipe gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                // Only respond to mostly-horizontal drags so we don't fight the
                // parent scroll view on vertical pans.
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > vertical else { return }

                // Resistance: slow down beyond cap so the row never flies off.
                let clamped: CGFloat
                if horizontal > swipeCap {
                    clamped = swipeCap + (horizontal - swipeCap) * 0.25
                } else if horizontal < -swipeCap {
                    clamped = -swipeCap + (horizontal + swipeCap) * 0.25
                } else {
                    clamped = horizontal
                }
                dragOffset = clamped

                // Single haptic when crossing the commit threshold.
                if !didFireHaptic, abs(horizontal) > swipeCommitThreshold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    didFireHaptic = true
                } else if didFireHaptic, abs(horizontal) < swipeCommitThreshold {
                    didFireHaptic = false
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                if horizontal > swipeCommitThreshold {
                    onSetIntent?(.need)
                } else if horizontal < -swipeCommitThreshold {
                    onSetIntent?(.want)
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    dragOffset = 0
                }
                didFireHaptic = false
            }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if !transaction.isCredit {
            Button {
                onSetIntent?(.need)
            } label: {
                Label("Mark as Need", systemImage: CategoryIntent.need.icon)
            }
            Button {
                onSetIntent?(.want)
            } label: {
                Label("Mark as Want", systemImage: CategoryIntent.want.icon)
            }
            Button {
                onSetIntent?(.saving)
            } label: {
                Label("Mark as Saving", systemImage: CategoryIntent.saving.icon)
            }
            if transaction.intentOverride != nil {
                Divider()
                Button {
                    onSetIntent?(nil)
                } label: {
                    Label("Clear override (use category default)", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}

// MARK: - Section Header
struct TransactionSectionHeader: View {
    let title: String
    let total: Decimal
    let isExpense: Bool

    private var totalColor: Color {
        isExpense ? .expenseRed : .incomeGreen
    }

    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: total as NSDecimalNumber) ?? "₹\(total)"
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .textCase(nil)

            Spacer()

            Text(formattedTotal)
                .font(.amount(13))
                .foregroundStyle(totalColor)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.xs)
        .background(Color.bgPrimary)
        .listRowInsets(EdgeInsets())
    }
}

#Preview {
    let txn = TransactionEntity(
        amount: 450,
        type: .debit,
        merchantRaw: "Swiggy",
        merchantName: "Swiggy",
        categorySlug: "food",
        source: .upi,
        confidence: 0.7,
        isConfirmed: false
    )
    List {
        TransactionRowView(transaction: txn)
            .listRowBackground(Color.bgCard)
            .listRowInsets(EdgeInsets())
    }
    .listStyle(.plain)
    .background(Color.bgPrimary)
}
