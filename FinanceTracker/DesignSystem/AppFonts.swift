import SwiftUI

extension Font {
    static let displayLarge  = Font.system(size: 34, weight: .bold)
    static let displayMedium = Font.system(size: 28, weight: .bold)
    static let titleLarge    = Font.system(size: 22, weight: .semibold)
    static let titleMedium   = Font.system(size: 17, weight: .semibold)
    static let bodyLarge     = Font.system(size: 17, weight: .regular)
    static let bodyMedium    = Font.system(size: 15, weight: .regular)
    static let caption       = Font.system(size: 13, weight: .regular)
    static let micro         = Font.system(size: 11, weight: .medium)

    static func amount(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}
