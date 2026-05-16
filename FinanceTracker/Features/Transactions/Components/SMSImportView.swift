import SwiftUI

// MARK: - SMSImportView

struct SMSImportView: View {

    var initialSMS: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @FocusState private var isInputFocused: Bool

    @State private var smsText: String = ""
    @State private var parsedResult: ParsedSMSResult?
    @State private var classifiedResult: ClassificationResult?
    @State private var parseFailed: Bool = false
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var toastType: ToastType = .success
    @State private var isAdding: Bool = false

    // Auto-mode state (deep-linked from Shortcut)
    @State private var autoState: AutoState = .idle
    enum AutoState: Equatable { case idle, saving, saved(String), failed }

    // Editable fields shown after parse
    @State private var editMerchant: String = ""
    @State private var editCategorySlug: String = "others"
    @State private var editAmountString: String = ""
    @State private var editType: TransactionType = .debit
    @State private var editAccountId: UUID? = nil
    @FocusState private var isMerchantFieldFocused: Bool

    private var accounts: [AccountEntity] {
        container?.accountRepo.fetchAll() ?? []
    }

    private var editAmount: Decimal {
        Decimal(string: editAmountString) ?? 0
    }

    private var displayCategories: [CategoryEntity] {
        editType == .credit
            ? CategoryEntity.system.filter { $0.isIncome }
            : CategoryEntity.system.filter { !$0.isIncome && !$0.isTransfer }
    }

    private var isAutoMode: Bool { initialSMS != nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if isAutoMode {
                    autoModeOverlay
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Spacing.xl) {
                            explanationCard
                            inputSection
                            if parseFailed {
                                parseFailedCard
                            }
                            if let parsed = parsedResult, let classified = classifiedResult {
                                editableResultCard(parsed: parsed, classified: classified)
                            }
                            examplesCard
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.top, Spacing.base)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle(isAutoMode ? "Logging Transaction" : "Paste SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .task {
                guard let initial = initialSMS, !initial.isEmpty else { return }
                smsText = initial
                try? await Task.sleep(nanoseconds: 250_000_000)
                autoParseAndSave(initial)
            }
        }
        .toast(isPresented: $showToast, message: toastMessage, type: toastType)
    }

    // MARK: - Auto Mode Overlay

    private var autoModeOverlay: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            switch autoState {
            case .idle, .saving:
                VStack(spacing: Spacing.lg) {
                    ProgressView()
                        .scaleEffect(1.4)
                        .tint(Color.brandPrimary)
                    Text("Reading SMS…")
                        .font(.titleMedium)
                        .foregroundStyle(Color.textSecondary)
                }

            case .saved(let summary):
                VStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.incomeGreen.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.incomeGreen)
                    }
                    Text("Transaction Saved")
                        .font(.titleLarge)
                        .foregroundStyle(Color.textPrimary)
                    Text(summary)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .transition(.scale.combined(with: .opacity))

            case .failed:
                VStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.expenseRed.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.expenseRed)
                    }
                    Text("Couldn't Parse SMS")
                        .font(.titleLarge)
                        .foregroundStyle(Color.textPrimary)
                    Text("Open the app and paste it manually to add this transaction.")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)

                    Button("Add Manually") {
                        autoState = .idle
                        // Switch to manual mode by clearing initialSMS effect
                        // (view stays open, user can type)
                    }
                    .font(.bodyMedium)
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.top, Spacing.sm)
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: autoState == .idle)
    }

    // MARK: - Explanation Card

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.brandPrimary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Paste a bank SMS")
                    .font(.titleMedium)
                    .foregroundColor(.textPrimary)
                Text("We'll parse the amount, merchant, card, and category automatically.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.base)
        .background(Color.brandPrimary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Color.brandPrimary.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Bank SMS Text")
                .font(.titleMedium)
                .foregroundColor(.textPrimary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .stroke(Color.bgElevated, lineWidth: 1)
                    )

                if smsText.isEmpty {
                    Text("Paste your bank SMS here…\n\nExample: \"Dear Customer, INR 1,500.00 debited from A/c XX1234 on 15-May-26...\"")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary.opacity(0.5))
                        .padding(Spacing.base)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $smsText)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(Spacing.sm)
                    .frame(minHeight: 140)
                    .focused($isInputFocused)
                    .onChange(of: smsText) { _, _ in
                        parsedResult = nil
                        classifiedResult = nil
                        parseFailed = false
                    }
            }
            .frame(minHeight: 140)

            HStack(spacing: Spacing.md) {
                if !smsText.isEmpty {
                    Button {
                        smsText = ""
                        parsedResult = nil
                        classifiedResult = nil
                        parseFailed = false
                    } label: {
                        Text("Clear")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                }

                Button {
                    parseSMS()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Parse SMS")
                            .font(.titleMedium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: smsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? [Color.bgElevated, Color.bgElevated]
                                : [.brandPrimary, .brandAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .disabled(smsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Parse Failed Card

    private var parseFailedCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.expenseRed)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Couldn't parse this SMS")
                    .font(.titleMedium)
                    .foregroundColor(.expenseRed)
                Text("Try adding the transaction manually, or check that the SMS is a bank debit/credit alert.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.base)
        .background(Color.expenseRed.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Color.expenseRed.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Editable Result Card

    private func editableResultCard(parsed: ParsedSMSResult, classified: ClassificationResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Text("Review & Edit")
                    .font(.titleMedium)
                    .foregroundColor(.textPrimary)
                Spacer()
                ConfidencePill(confidence: classified.confidence)
            }

            VStack(spacing: Spacing.md) {

                // Amount row
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("AMOUNT")
                        .font(.micro)
                        .foregroundColor(.textSecondary)
                    TextField("Amount", text: $editAmountString)
                        .keyboardType(.decimalPad)
                        .font(.amount(28, weight: .bold))
                        .foregroundColor(editType == .credit ? Color.incomeGreen : Color.textPrimary)
                        .padding(Spacing.base)
                        .background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }

                // Type toggle
                HStack(spacing: 0) {
                    ForEach([TransactionType.debit, TransactionType.credit], id: \.self) { type in
                        Button {
                            withAnimation(.springy) {
                                editType = type
                                editCategorySlug = type == .credit
                                    ? (CategoryEntity.system.first { $0.isIncome }?.slug ?? "salary")
                                    : "others"
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: type == .debit ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text(type == .debit ? "Expense" : "Income")
                                    .font(.bodyMedium)
                            }
                            .foregroundStyle(editType == type ? Color.white : Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                editType == type
                                    ? (type == .debit ? Color.expenseRed : Color.incomeGreen)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                // Merchant row
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("MERCHANT")
                        .font(.micro)
                        .foregroundColor(.textSecondary)
                    TextField("Merchant name", text: $editMerchant)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                        .tint(Color.brandPrimary)
                        .focused($isMerchantFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { isMerchantFieldFocused = false }
                        .padding(Spacing.base)
                        .background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }

                // Category picker
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("CATEGORY")
                        .font(.micro)
                        .foregroundColor(.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(displayCategories) { cat in
                                SMSCategoryChip(
                                    category: cat,
                                    isSelected: editCategorySlug == cat.slug
                                ) {
                                    isMerchantFieldFocused = false
                                    withAnimation(.springy) { editCategorySlug = cat.slug }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                }

                // Account picker (if accounts exist)
                if !accounts.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("ACCOUNT / CARD")
                            .font(.micro)
                            .foregroundColor(.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.sm) {
                                Button {
                                    withAnimation(.springy) { editAccountId = nil }
                                } label: {
                                    Text("None")
                                        .font(.caption)
                                        .foregroundStyle(editAccountId == nil ? Color.white : Color.textSecondary)
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        .background(editAccountId == nil ? Color.brandPrimary : Color.bgElevated)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                ForEach(accounts) { account in
                                    Button {
                                        withAnimation(.springy) { editAccountId = account.id }
                                    } label: {
                                        HStack(spacing: Spacing.xs) {
                                            Image(systemName: account.type.icon)
                                                .font(.system(size: 11))
                                            Text(account.name)
                                                .font(.caption)
                                        }
                                        .foregroundStyle(editAccountId == account.id ? Color.white : Color.textSecondary)
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        .background(editAccountId == account.id ? Color(hex: account.colorHex) : Color.bgElevated)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // Confirm & Add button
            Button {
                confirmAndAdd(parsed: parsed)
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isAdding {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isAdding ? "Adding…" : "Confirm & Add")
                        .font(.titleMedium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [.incomeGreen, .incomeGreen.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
            .disabled(isAdding || editAmount <= 0)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Examples Card

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What does a bank SMS look like?")
                .font(.titleMedium)
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                ExampleSMS(
                    bank: "HDFC",
                    text: "HDFC Bank: Rs.1500.00 debited from A/c XX1234 at SWIGGY on 15-05-26. UPI Ref: 123456789."
                )
                ExampleSMS(
                    bank: "ICICI",
                    text: "Dear Customer, INR 5,000.00 credited to A/c XXXX5678 by NEFT on 15-May-2026. Available Bal: INR 45,230."
                )
            }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Actions

    private func autoParseAndSave(_ text: String) {
        // Guard against double-save if the view re-runs its lifecycle.
        guard autoState == .idle else { return }
        guard let container else {
            withAnimation { autoState = .failed }
            return
        }

        withAnimation { autoState = .saving }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip if we already saved this exact SMS in the last 2 minutes
        // (handles shortcut/automation firing twice, retry loops, etc.)
        let recentMatch = container.transactionRepo.fetchAll().first { txn in
            txn.rawContent == trimmed &&
            abs(Date().timeIntervalSince(txn.createdAt)) < 120
        }
        if recentMatch != nil {
            withAnimation { autoState = .saved("Already saved · skipped duplicate") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
            return
        }

        guard let result = SMSParser.shared.parse(trimmed) else {
            withAnimation { autoState = .failed }
            return
        }

        let merchant = MerchantNormalizer.shared.normalize(result.merchantRaw)
        let classification = CategoryClassifier.shared.classify(
            merchantName: merchant,
            amount: result.amount,
            type: result.type,
            rawContent: trimmed
        )
        let autoAccount = result.last4.flatMap { last4 in
            (container.accountRepo.fetchAll()).first { $0.last4 == last4 }
        }

        let entity = TransactionEntity(
            amount: result.amount,
            type: result.type,
            merchantRaw: result.merchantRaw,
            merchantName: merchant.isEmpty ? result.merchantRaw : merchant,
            categorySlug: classification.categorySlug,
            date: result.date ?? Date(),
            source: .sms,
            confidence: classification.confidence,
            isConfirmed: true,
            accountId: autoAccount?.id,
            upiRef: result.upiRef,
            bankRef: result.bankRef,
            rawContent: trimmed
        )
        container.transactionRepo.save(entity)

        let sign   = result.type == .credit ? "+" : "-"
        let amount = "₹\(result.amount.formatted(.number.precision(.fractionLength(0))))"
        let name   = merchant.isEmpty ? result.merchantRaw : merchant
        let card   = autoAccount.map { " · \($0.name)" } ?? ""
        let summary = "\(sign)\(amount)  \(name)\(card)"

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            autoState = .saved(summary)
        }

        // Auto-dismiss after 1.8 s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            dismiss()
        }
    }

    private func parseSMS() {
        let trimmed = smsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isInputFocused = false

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            parseFailed = false
            parsedResult = nil
            classifiedResult = nil
        }

        if let result = SMSParser.shared.parse(trimmed) {
            let merchant = MerchantNormalizer.shared.normalize(result.merchantRaw)
            let classification = CategoryClassifier.shared.classify(
                merchantName: merchant,
                amount: result.amount,
                type: result.type,
                rawContent: trimmed
            )

            // Auto-link account by last4
            let autoAccount = result.last4.flatMap { last4 in
                accounts.first { $0.last4 == last4 }
            }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                parsedResult = result
                classifiedResult = classification
                editMerchant = merchant.isEmpty ? result.merchantRaw : merchant
                editCategorySlug = classification.categorySlug
                editAmountString = "\(result.amount)"
                editType = result.type
                editAccountId = autoAccount?.id
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                parseFailed = true
            }
        }
    }

    private func confirmAndAdd(parsed: ParsedSMSResult) {
        guard let container else { return }
        guard editAmount > 0 else { return }
        isAdding = true

        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                let entity = TransactionEntity(
                    id: UUID(),
                    amount: editAmount,
                    type: editType,
                    merchantRaw: parsed.merchantRaw,
                    merchantName: editMerchant.isEmpty ? parsed.merchantRaw : editMerchant,
                    categorySlug: editCategorySlug,
                    date: parsed.date ?? Date(),
                    source: .sms,
                    confidence: 1.0,
                    isConfirmed: true,
                    accountId: editAccountId,
                    upiRef: parsed.upiRef,
                    bankRef: parsed.bankRef,
                    rawContent: smsText
                )
                container.transactionRepo.save(entity)
                isAdding = false
                toastMessage = "Transaction added successfully"
                toastType = .success
                showToast = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    smsText = ""
                    parsedResult = nil
                    classifiedResult = nil
                    parseFailed = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct SMSCategoryChip: View {
    let category: CategoryEntity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : category.color)
                Text(category.name)
                    .font(.micro)
                    .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? category.color : Color.bgElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.springy, value: isSelected)
    }
}

private struct ConfidencePill: View {
    let confidence: Double

    private var color: Color {
        if confidence >= 0.85 { return .incomeGreen }
        if confidence >= 0.60 { return .warningAmber }
        return .expenseRed
    }

    private var label: String {
        if confidence >= 0.85 { return "High confidence" }
        if confidence >= 0.60 { return "Medium confidence" }
        return "Low confidence"
    }

    var body: some View {
        Text(label)
            .font(.micro)
            .foregroundColor(color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

private struct ExampleSMS: View {
    let bank: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(bank)
                .font(.micro)
                .foregroundColor(.brandPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background(Color.brandPrimary.opacity(0.15))
                .clipShape(Capsule())

            Text(text)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(Spacing.md)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}
