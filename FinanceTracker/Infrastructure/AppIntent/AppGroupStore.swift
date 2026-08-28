import Foundation

/// Resolves the shared-defaults store used by the SMS pipeline, with a
/// graceful fallback when the App Group entitlement isn't available.
///
/// Why this exists: sideloading tools (AltStore / SideStore) re-sign the app
/// with a free personal team, which generally cannot vend arbitrary App Group
/// entitlements — so `UserDefaults(suiteName:)` returns nil. Release builds
/// compile out `assert`, so the previous code silently no-oped: SMS capture
/// stopped working AND the audit log meant to diagnose that stayed empty,
/// which is the worst possible failure mode.
///
/// Falling back to `.standard` keeps everything that runs inside the app
/// process working — the `financetracker://import?sms=` URL scheme, manual
/// paste, and the audit trail. Only `LogBankSMSIntent` (which executes in a
/// separate process while the phone is locked) genuinely needs the shared
/// container; without it that one path can't hand data across, but the rest of
/// the app no longer breaks in silence.
enum AppGroupStore {

    static let suiteName = "group.com.sovinnour.FinanceTracker"

    /// True when the App Group container is actually reachable. Surfaced in
    /// Developer Options so the degraded state is visible rather than silent.
    static var isAppGroupAvailable: Bool {
        UserDefaults(suiteName: suiteName) != nil
    }

    /// Shared defaults when entitled, otherwise the app's own defaults.
    /// Never nil, so callers don't need a failure path that silently drops data.
    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
