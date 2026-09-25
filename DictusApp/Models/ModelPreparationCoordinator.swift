import Foundation

/// Serializes Core ML preparation. A timed-out initializer stays quarantined
/// until it exits, and its files are deleted only after that exit.
@MainActor
final class ModelPreparationCoordinator {
    private(set) var isPrewarming = false
    private(set) var prewarmQuarantined = false

    func waitUntilIdle() async throws {
        while isPrewarming {
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        if prewarmQuarantined {
            throw ModelManagerError.prewarmBusy
        }
    }

    func beginPrewarm() {
        isPrewarming = true
    }

    func endPrewarm() {
        isPrewarming = false
    }

    func quarantineFailedPrewarm(
        _ identifier: String,
        releaseWhenFinished: @escaping @Sendable () async -> Void,
        cleanup: @escaping @MainActor (String) -> Void
    ) {
        prewarmQuarantined = true
        Task { @MainActor in
            await releaseWhenFinished()
            cleanup(identifier)
            self.prewarmQuarantined = false
        }
    }
}
