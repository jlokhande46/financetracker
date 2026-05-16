import Foundation
import LocalAuthentication

@MainActor
final class BiometricAuthService {
    static let shared = BiometricAuthService()
    private init() {}

    enum BiometricKind {
        case none, faceID, touchID, opticID

        var displayName: String {
            switch self {
            case .faceID:  return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            case .none:    return "Passcode"
            }
        }

        var icon: String {
            switch self {
            case .faceID:  return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            case .none:    return "lock.fill"
            }
        }
    }

    /// Detects the device's available biometric type. Returns `.none` if no biometric is enrolled.
    var availableBiometric: BiometricKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:  return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default:       return .none
        }
    }

    /// Prompts the user for biometric (or device passcode as fallback) authentication.
    /// Returns true if the user authenticated successfully.
    func authenticate(reason: String = "Unlock FinanceTracker") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        // Fall back to device passcode if biometric isn't available or fails.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
