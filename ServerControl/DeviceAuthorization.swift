import Foundation
import LocalAuthentication

@MainActor
enum DeviceAuthorization {
    static func authorize(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel command"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw APIError.message("Set a device passcode in iPhone Settings to authorize server commands. Face ID or Touch ID is optional.")
        }
        let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        guard success else { throw APIError.message("Device authentication failed. No command was sent.") }
    }
    static func isCancellation(_ error: Error) -> Bool {
        guard let la = error as? LAError else { return false }
        return [.userCancel, .appCancel, .systemCancel].contains(la.code)
    }
}
