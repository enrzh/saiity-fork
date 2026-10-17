import SwiftUI
import UIKit
import AVKit
import Combine
import SyllivraKernel

/// One observer owns setup permission state across all onboarding pages.
@MainActor final class KeyboardSetupModel: ObservableObject {
    static let shared = KeyboardSetupModel()
    @Published private(set) var keyboardInstalled = false
    @Published private(set) var fullAccessVerified = false
    @Published private(set) var fullAccessDenied = false

    private init() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged) {
            DispatchQueue.main.async { Self.shared.refresh() }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessDenied) {
            DispatchQueue.main.async {
                let model = Self.shared
                model.keyboardInstalled = true
                model.fullAccessVerified = false
                model.fullAccessDenied = true
                AppGroup.defaults.set(false, forKey: SharedKeys.onboardingFullAccessVerified)
                AppGroup.defaults.synchronize()
            }
        }
        refresh()
    }

    func refresh() {
        AppGroup.defaults.synchronize()
        let installed = UITextInputMode.activeInputModes.contains {
            KeyboardSetupStatus.isDictusKeyboardIdentifier($0.value(forKey: "identifier") as? String)
        }
        let verified = KeyboardSetupStatus.isCurrentFullAccessHandshake(
            verified: AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified),
            probe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessProbe),
            acknowledgedProbe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessAcknowledgedProbe))
        keyboardInstalled = installed || verified
        fullAccessVerified = verified
        if verified { fullAccessDenied = false }
    }

    func beginVerification() {
        AppGroup.defaults.set(UUID().uuidString, forKey: SharedKeys.onboardingFullAccessProbe)
        AppGroup.defaults.removeObject(forKey: SharedKeys.onboardingFullAccessAcknowledgedProbe)
        AppGroup.defaults.synchronize()
        fullAccessVerified = false
        fullAccessDenied = false
    }

    func requestProbe() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessProbeRequested)
        refresh()
    }
}

/// Native, silent instructional video. PiP starts before opening Settings;
/// unavailable PiP falls back to the same inline guide and written steps.
@MainActor final class KeyboardSetupGuide: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let player: AVPlayer
    let layer: AVPlayerLayer
    let supportsPictureInPicture = AVPictureInPictureController.isPictureInPictureSupported()
    private var loop: AVPlayerLooper?
    private var pip: AVPictureInPictureController?
    private var possible: NSKeyValueObservation?
    private var pendingOpen: (() -> Void)?
    private var timeout: DispatchWorkItem?
    private var restoreKeyboardSession = false
    private var startingPiP = false
    @Published var message: String?

    override init() {
        let queue = AVQueuePlayer()
        player = queue
        layer = AVPlayerLayer(player: player)
        super.init()
        guard let url = Bundle.main.url(forResource: "KeyboardSetupGuide", withExtension: "mp4") else {
            message = "Follow the written steps below."
            return
        }
        loop = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        layer.videoGravity = .resizeAspect
        #if DEBUG
        NSLog("SETUP_GUIDE PiP supported: %@", supportsPictureInPicture.description)
        #endif
        if supportsPictureInPicture {
            pip = AVPictureInPictureController(playerLayer: layer)
            pip?.delegate = self
            pip?.requiresLinearPlayback = true
            possible = pip?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.startIfReady() }
            }
        } else {
            message = "Picture in Picture is not supported on this device. Watch the guide here, then follow the steps in Settings."
        }
    }

    func openSettings(withVideo: Bool, action: @escaping () -> Void) {
        guard pendingOpen == nil else { return }
        guard withVideo, pip != nil else { action(); return }
        let coordinator = DictationCoordinator.shared
        guard !DictationSessionLivenessPolicy.isActive(coordinator.status) else { action(); return }
        restoreKeyboardSession = coordinator.keyboardSessionEnabled
        coordinator.disableKeyboardSession()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            message = "The video stays here. Follow the written steps in Settings."
            restoreSession()
            action()
            return
        }
        player.seek(to: .zero)
        player.play()
        pendingOpen = action
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingOpen != nil else { return }
            self.message = "Picture in Picture is unavailable. Follow the written steps in Settings."
            self.finishOpening()
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        startIfReady()
    }

    private func startIfReady() {
        guard pendingOpen != nil, !startingPiP, pip?.isPictureInPicturePossible == true else { return }
        if pip?.isPictureInPictureActive != true { startingPiP = true; pip?.startPictureInPicture() }
    }

    private func finishOpening() {
        timeout?.cancel()
        timeout = nil
        let action = pendingOpen
        pendingOpen = nil
        action?()
    }

    func stopUnlessInPictureInPicture() {
        guard pip?.isPictureInPictureActive != true else { return }
        stop()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        startingPiP = false
        #if DEBUG
        NSLog("SETUP_GUIDE PiP started")
        #endif
        finishOpening()
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        message = "Picture in Picture is unavailable. Follow the written steps in Settings."
        startingPiP = false
        #if DEBUG
        NSLog("SETUP_GUIDE PiP unavailable: %@", error.localizedDescription)
        #endif
        finishOpening()
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        player.pause()
        restoreSession()
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    func stop() {
        timeout?.cancel()
        startingPiP = false
        pendingOpen = nil
        pip?.stopPictureInPicture()
        player.pause()
        restoreSession()
    }

    private func restoreSession() {
        if AVAudioSession.sharedInstance().category == .playback {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        let restore = restoreKeyboardSession
        restoreKeyboardSession = false
        if restore && AppGroup.defaults.bool(forKey: SharedKeys.serviceEnabled) {
            DictationCoordinator.shared.enableKeyboardSession()
        }
    }
}

private struct KeyboardSetupVideo: UIViewRepresentable {
    let guide: KeyboardSetupGuide
    func makeUIView(context: Context) -> UIView {
        let view = VideoSurface()
        view.layer.addSublayer(guide.layer)
        view.videoLayer = guide.layer
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { guide.layer.frame = uiView.bounds }
    private final class VideoSurface: UIView {
        weak var videoLayer: AVPlayerLayer?
        override func layoutSubviews() { super.layoutSubviews(); videoLayer?.frame = bounds }
    }
}

struct KeyboardSetupCard: View {
    @ObservedObject private var setup = KeyboardSetupModel.shared
    @StateObject private var guide = KeyboardSetupGuide()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showVideo = true
    @State private var returningFromSettings = false
    @State private var testText = ""
    @FocusState private var checkingKeyboard: Bool

    var body: some View {
        GroupBox {
        VStack(alignment: .leading, spacing: 16) {
            status("Syllivra keyboard", done: setup.keyboardInstalled, detail: "Add it in iPhone Settings")
            status("Full Access", done: setup.fullAccessVerified,
                   detail: setup.fullAccessDenied ? "Off · enable Allow Full Access in Settings" : "Choose Syllivra below to verify the current permission")
            KeyboardSetupVideo(guide: guide).aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Keyboard setup video: Settings, General, Keyboard, Keyboards, Syllivra, Allow Full Access")
            HStack {
                Button("Play guide", systemImage: "play.fill") { guide.player.play() }
                Button("Pause", systemImage: "pause.fill") { guide.player.pause() }
            }.buttonStyle(.bordered)
            if guide.supportsPictureInPicture { Toggle("Show video over Settings", isOn: $showVideo) }
            Button("Open Keyboard Settings", systemImage: "gearshape") {
                setup.beginVerification()
                checkingKeyboard = false
                guide.openSettings(withVideo: showVideo) {
                    returningFromSettings = true
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("Settings → General → Keyboard → Keyboards → Add New Keyboard → Syllivra. Then open Syllivra and enable Allow Full Access.")
                .font(.footnote).foregroundStyle(.secondary)
            if let message = guide.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            TextField("Tap here, then choose Syllivra with the globe", text: $testText)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled().focused($checkingKeyboard)
                .accessibilityIdentifier("setup.keyboard-check")
            Text("Permission is confirmed by the actual keyboard. No recording is needed for this check.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        }
        .onAppear { setup.beginVerification(); setup.refresh() }
        .onDisappear { guide.stopUnlessInPictureInPicture() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            setup.refresh()
            if returningFromSettings { checkingKeyboard = true; returningFromSettings = false }
        }
        .task(id: checkingKeyboard && scenePhase == .active) {
            guard checkingKeyboard, scenePhase == .active else { return }
            while !Task.isCancelled && !setup.fullAccessVerified {
                setup.requestProbe()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func status(_ title: String, done: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(done ? "Verified" : detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct KeyboardSetupPage: View {
    let onNext: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Set up your keyboard").font(.title2.bold())
                KeyboardSetupCard()
                Button("Continue", action: onNext).buttonStyle(.borderedProminent)
            }.padding(20).frame(maxWidth: 560)
        }.navigationTitle("Keyboard setup")
    }
}
