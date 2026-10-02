import Foundation

// Safe public schema: upstream credentials and raw monitor responses never belong here.
struct ServiceSnapshot: Codable {
    let geminiHealth: String?
    let gemini: [GeminiKeyStatus]?
    let classera: [ClasseraStatus]?
    let padel: [PadelComponent]?
}
struct GeminiKeyStatus: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let lastAuthenticationCheck: String?
    let lastGenerationCheck: String?
    let canTest: Bool?
}
struct ClasseraStatus: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let schedulerStatus: String?
    let webhookStatus: String?
    let lastRun: String?
    let lastReport: String?
    let canFire: Bool?
}
struct PadelComponent: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let deliveryStatus: String?
    let lastNotification: String?
}
struct ServiceCommand: Identifiable {
    enum Kind { case testGeminiKey, fireClasseraReport }
    let kind: Kind
    let id: String
    let name: String
    var title: String { kind == .fireClasseraReport ? "Send a real WhatsApp report?" : "Test \(name)?" }
    var explanation: String {
        kind == .fireClasseraReport
            ? "This sends real WhatsApp messages for \(name). Confirm, then authorize on your iPhone."
            : "Your server will test \(name). Its credentials stay on the server."
    }
}
