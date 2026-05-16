import SwiftUI

struct SourceBadge: View {
    let source: TransactionSource

    private var badgeColor: Color {
        switch source {
        case .sms:    return .warningAmber
        case .email:  return Color(hex: "#3B82F6")
        case .pdf:    return Color(hex: "#A855F7")
        case .manual: return Color(hex: "#8E8E99")
        case .upi:    return .incomeGreen
        case .aa:     return Color(hex: "#06B6D4")
        }
    }

    private var badgeIcon: String {
        switch source {
        case .sms:    return "message.fill"
        case .email:  return "envelope.fill"
        case .pdf:    return "doc.text.fill"
        case .manual: return "pencil"
        case .upi:    return "indianrupeesign.circle.fill"
        case .aa:     return "building.columns.fill"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: badgeIcon)
                .font(.system(size: 9, weight: .medium))

            Text(source.displayName)
                .font(.micro)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(TransactionSource.allCases, id: \.self) { source in
            SourceBadge(source: source)
        }
    }
    .padding()
    .background(Color.bgCard)
    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    .padding()
    .background(Color.bgPrimary)
}
