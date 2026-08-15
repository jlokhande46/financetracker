import SwiftUI

/// Chronological trace of every SMS the app's pipeline has touched —
/// from automation receipt through queueing, parsing, and saving (or
/// dedup/skip). Surfaced in Developer Options to answer "I sent an SMS
/// but the transaction never appeared — what happened?"
struct SMSActivityView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var events: [SMSAuditStore.Event] = []
    @State private var selected: SMSAuditStore.Event? = nil
    @State private var showClearConfirm = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM · HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if events.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("SMS Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
                if !events.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear", role: .destructive) {
                            showClearConfirm = true
                        }
                        .foregroundStyle(Color.expenseRed)
                    }
                }
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
            .alert("Clear SMS activity log?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    SMSAuditStore.clear()
                    reload()
                }
            } message: {
                Text("Removes every audit entry. Future SMS will start logging fresh.")
            }
            .sheet(item: $selected) { event in
                eventDetail(event)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                summaryBar
                    .padding(.horizontal, Spacing.base)
                    .padding(.vertical, Spacing.sm)

                VStack(spacing: 0) {
                    ForEach(events) { event in
                        Button { selected = event } label: {
                            row(event)
                        }
                        .buttonStyle(.plain)
                        if event.id != events.last?.id {
                            Divider()
                                .background(Color.textTertiary.opacity(0.15))
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .padding(.horizontal, Spacing.base)
                .padding(.bottom, Spacing.xl)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: Spacing.sm) {
            // `filter { }.count` rather than `count(where:)` — the latter is
            // Swift 6 only and this target builds on Swift 5.x.
            stat(label: "Received", count: events.filter { $0.kind == .receivedViaIntent || $0.kind == .receivedViaURL }.count, color: .brandPrimary)
            stat(label: "Saved", count: events.filter { $0.kind == .savedAsTransaction }.count, color: .incomeGreen)
            stat(label: "Failed", count: events.filter { $0.kind == .parseFailed }.count, color: .expenseRed)
            stat(label: "Skipped", count: events.filter { $0.kind == .enqueueDeduped || $0.kind == .savedDeduped }.count, color: .warningAmber)
        }
    }

    private func stat(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.amount(18, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func row(_ event: SMSAuditStore.Event) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(color(for: event.kind).opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: event.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color(for: event.kind))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(event.kind.label)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text("·")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                    Text(Self.timeFormatter.string(from: event.timestamp))
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                }
                Text(event.textPreview)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Spacing.base)
        .contentShape(Rectangle())
    }

    private func color(for kind: SMSAuditStore.Kind) -> Color {
        switch kind {
        case .receivedViaIntent, .receivedViaURL: return .brandPrimary
        case .enqueued:                           return .brandAccent
        case .enqueueDeduped, .savedDeduped:      return .warningAmber
        case .parseFailed:                        return .expenseRed
        case .savedAsTransaction:                 return .incomeGreen
        }
    }

    // MARK: - Detail sheet

    private func eventDetail(_ event: SMSAuditStore.Event) -> some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(color(for: event.kind).opacity(0.18))
                                    .frame(width: 44, height: 44)
                                Image(systemName: event.kind.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(color(for: event.kind))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.kind.label)
                                    .font(.titleMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Text(Self.timeFormatter.string(from: event.timestamp))
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }

                        section(title: "SMS Preview") {
                            Text(event.textPreview)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let detail = event.detail, !detail.isEmpty {
                            section(title: "Detail") {
                                Text(detail)
                                    .font(.bodyMedium)
                                    .foregroundStyle(Color.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(Spacing.base)
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            content()
                .padding(Spacing.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No SMS activity yet")
                .font(.titleLarge)
                .foregroundStyle(Color.textPrimary)
            Text("Once the Shortcut automation or the URL deep-link fires, every step from receipt to save will show up here.")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
    }

    private func reload() {
        events = SMSAuditStore.snapshot()
    }
}
