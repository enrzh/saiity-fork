import AVFoundation
import UIKit
import Combine
import SyllivraKernel

@MainActor final class RecordingReplay: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = RecordingReplay()
    @Published private(set) var available = false
    @Published private(set) var playing = false
    @Published private(set) var trimmed = false
    @Published private(set) var message: String?
    private var buffer = RecordingReplayBuffer()
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var preparation: Task<Void, Never>?
    private var generation = 0
    private var ownsAudioSession = false

    func retain(_ samples: [Float], session: Int) {
        clear()
        guard UIApplication.shared.applicationState == .active else { return }
        buffer.retain(samples, session: session,
            enabled: AppGroup.defaults.bool(forKey: SharedKeys.recordingReplayEnabled),
            now: ProcessInfo.processInfo.systemUptime)
        available = buffer.isAvailable(now: ProcessInfo.processInfo.systemUptime)
        trimmed = buffer.trimmed
        if available {
            timer = Timer.scheduledTimer(withTimeInterval: RecordingReplayBuffer.lifetime, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.clear() }
            }
        }
    }

    func toggle() {
        if playing || preparation != nil { stop(); return }
        guard UIApplication.shared.applicationState == .active,
              DictationCoordinator.shared.canChangeSpeechRuntime,
              AppGroup.defaults.bool(forKey: SharedKeys.recordingReplayEnabled),
              buffer.isAvailable(now: ProcessInfo.processInfo.systemUptime) else { clear(); return }
        let snapshot = buffer
        let token = generation
        message = nil
        preparation = Task { [weak self] in
            defer {
                if let self, self.generation == token { self.preparation = nil }
            }
            let encoding = Task.detached(priority: .userInitiated) {
                snapshot.wavData(now: ProcessInfo.processInfo.systemUptime, isCancelled: { Task.isCancelled })
            }
            let data = await withTaskCancellationHandler(operation: { await encoding.value },
                                                         onCancel: { encoding.cancel() })
            guard let self, !Task.isCancelled, self.generation == token,
                  UIApplication.shared.applicationState == .active,
                  AppGroup.defaults.bool(forKey: SharedKeys.recordingReplayEnabled),
                  self.buffer.isAvailable(now: ProcessInfo.processInfo.systemUptime),
                  DictationCoordinator.shared.canChangeSpeechRuntime, let data else { return }
            do {
                if !DictationCoordinator.shared.keyboardSessionEnabled {
                    DictationCoordinator.shared.deactivateAudioIfIdle()
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.ownsAudioSession = true
                }
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                self.playing = player.play()
                if !self.playing { self.stop(); self.message = "The recording couldn’t be played. Try again." }
            } catch {
                self.stop()
                self.message = "The recording couldn’t be played. Try again."
            }
        }
    }

    func stop() {
        generation &+= 1
        preparation?.cancel(); preparation = nil
        player?.stop(); player = nil; playing = false
        if ownsAudioSession {
            if !DictationCoordinator.shared.keyboardSessionEnabled,
               DictationCoordinator.shared.canChangeSpeechRuntime,
               AVAudioSession.sharedInstance().category == .playback {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            ownsAudioSession = false
        }
    }

    func clear() {
        stop()
        timer?.invalidate(); timer = nil
        buffer.clear(); available = false; trimmed = false; message = nil
    }

    func refreshAvailability() {
        if !AppGroup.defaults.bool(forKey: SharedKeys.recordingReplayEnabled)
            || !buffer.isAvailable(now: ProcessInfo.processInfo.systemUptime) { clear() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.player === player else { return }
            self.stop()
            if !flag { self.message = "The recording couldn’t be played. Try again." }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.player === player else { return }
            self.stop()
            self.message = "The recording couldn’t be played. Try again."
        }
    }
}
