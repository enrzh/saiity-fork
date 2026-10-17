import Foundation

public struct DiagnosticResult {
    public let canWrite: Bool
    public let canRead: Bool
    public let appGroupID: String
    public let containerExists: Bool
    public let timestamp: Date
    public var isHealthy: Bool { canRead && canWrite && containerExists }
}

public enum AppGroupDiagnostic {
    public static func run() -> DiagnosticResult {
        let shared = AppGroup.defaults
        // Each process removes only its own probe, even when diagnostics run together.
        let key = "de.aiity.saiity.diagnostic." + UUID().uuidString
        let marker = UUID().uuidString
        shared.set(marker, forKey: key)
        shared.synchronize()
        defer {
            shared.removeObject(forKey: key)
            shared.synchronize()
        }
        let value = shared.string(forKey: key)
        return DiagnosticResult(canWrite: value == marker, canRead: value != nil,
                                appGroupID: AppGroup.identifier, containerExists: AppGroup.containerURL != nil,
                                timestamp: Date())
    }
}
