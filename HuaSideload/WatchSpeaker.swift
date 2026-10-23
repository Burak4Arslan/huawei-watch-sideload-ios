import AVFoundation
import CallKit
import SwiftUI

// Phone audio through the watch speaker. The GT 3 SE is no A2DP (music) receiver; it only opens its speaker for a call
// (over HFP). So the app reports an incoming CallKit call: the watch rings, and once it is answered on the watch the
// app keeps the call's audio route open by playing silence (playAndRecord + HFP + mixWithOthers). Whatever the iPhone
// plays now (Spotify, Apple Music, a podcast…) goes down that route to the watch speaker, at phone-call quality.
// The other app's audio is not captured or recorded. Tested: an outgoing call, or HFP routing without a call, plays
// nothing on the watch. Needs UIBackgroundModes voip (CallKit refuses the call without it) and audio.
//
// The watch's call screen can't be left and its buttons send nothing to the phone, but its mic button can be noticed:
// with the mic off the watch sends uninterrupted digital silence. With the mic on it goes silent too in quiet parts of
// a song (its noise suppression), for up to ~3 s, so only long mic-off periods mean something. A feature that wants
// this sets onMicToggled (gets how long the mic was off); only the input level is looked at, nothing is recorded.
// More reliable: the volume panel on the watch changes the iPhone's volume, which the app sees, and the watch never
// changes it on its own. onVolumeGesture gets a wiggle (down and right back up), a double wiggle, or down to the bottom
// and up again.
final class WatchSpeaker: NSObject, ObservableObject, CXProviderDelegate {
    enum State { case idle, ringing, playing }

    @Published private(set) var state: State = .idle
    @Published private(set) var status: String?
    // Whether the mic button is watched (only offered when a feature set onMicToggled)
    @Published var micGestures = true

    // Name shown for the call on the watch and the iPhone
    var callerName = AppInfo.displayName
    // Button title and footer of the section; features can name and explain what they add
    var buttonTitle: String?
    var footer: String?
    var log: (LogKind, String) -> Void = { _, _ in }
    // The speaker is on / the call ended
    var onPlaying: (() -> Void)?
    var onEnded: (() -> Void)?
    // The mic was switched off on the watch and on again; argument: how long it was off (seconds)
    var onMicToggled: ((TimeInterval) -> Void)?
    enum VolumeGesture { case wiggle, doubleWiggle, bottom }
    var onVolumeGesture: ((VolumeGesture) -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private let provider: CXProvider
    private var callID: UUID?
    private var engine: AVAudioEngine?
    private var zeroSince: Date?
    private var nonZeroSince: Date?
    private var micOffSince: Date?
    private var lastVolumeChange = Date.distantPast
    // Route changes (e.g. another app switching devices) also silence the mic for a while: ignore it until then
    private var micIgnoredUntil = Date.distantPast
    private var volumeObservation: NSKeyValueObservation?
    private var lastVolume: Float = 0
    private var gestureStartedAt: Date?
    private var gestureStartLevel: Float = 0
    private var gestureLowest: Float = 0
    private var gestureCooldownUntil = Date.distantPast
    private var wiggles = 0
    private var wiggleTimer: DispatchWorkItem?
    private var routeObserver: NSObjectProtocol?
    // .allowBluetooth (HFP) by raw value; it was renamed in iOS 26
    private let allowHFP = AVAudioSession.CategoryOptions(rawValue: 0x4)

    private var watchesMic: Bool { micGestures && onMicToggled != nil }

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // Rings the watch; once answered there, the watch speaker plays the iPhone's audio
    func ring() {
        guard state == .idle else { return }
        if watchesMic && AVAudioApplication.shared.recordPermission == .undetermined {
            AVAudioApplication.requestRecordPermission { _ in DispatchQueue.main.async { self.ring() } }
            return
        }
        do {
            try configureSession()
        } catch {
            return fail(L("Could not set up audio: ", "Ses ayarlanamadı: ") + error.localizedDescription)
        }
        guard session.availableInputs?.contains(where: { $0.portType == .bluetoothHFP }) == true else {
            return fail(L("The watch is not connected to the iPhone for calls. In the iPhone's Bluetooth settings, tap the watch to connect it.",
                          "Saat aramalar için iPhone'a bağlı değil. iPhone'un Bluetooth ayarlarından saate dokunup bağla."))
        }
        let id = UUID()
        callID = id
        state = .ringing
        status = L("The watch is ringing: answer it on the watch", "Saat çalıyor: saatten aç")
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = false
        provider.reportNewIncomingCall(with: id, update: update) { error in
            DispatchQueue.main.async {
                guard let error else { return }
                self.callID = nil
                self.state = .idle
                self.fail(L("Could not start the call: ", "Arama başlatılamadı: ") + error.localizedDescription)
            }
        }
    }

    func stop() {
        guard let id = callID else { return }
        provider.reportCall(with: id, endedAt: Date(), reason: .remoteEnded)
        finish(L("Ended", "Bitti"))
    }

    // Don't count mic silence for a while (e.g. while a music app moves playback to this phone)
    func ignoreMic(for seconds: TimeInterval) {
        micIgnoredUntil = max(micIgnoredUntil, Date().addingTimeInterval(seconds))
        zeroSince = nil
        nonZeroSince = nil
        micOffSince = nil
    }

    // MARK: - Audio

    private func configureSession() throws {
        // mixWithOthers: other apps keep playing, down the same route (to the watch)
        try session.setCategory(.playAndRecord, mode: .default, options: allowHFP.union(.mixWithOthers))
    }

    // Plays silence: keeps the call's audio route open, the watch only hears the other apps
    private func startSilence() {
        guard state != .playing else { return }
        if let port = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
            try? session.setPreferredInput(port)
        }
        do {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000) else { return }
            silence.frameLength = 16_000
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            if watchesMic && AVAudioApplication.shared.recordPermission == .granted {
                let input = engine.inputNode
                input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                    guard let data = buffer.floatChannelData?[0] else { return }
                    var peak: Float = 0
                    for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
                    DispatchQueue.main.async { self?.micLevel(peak) }
                }
            }
            try engine.start()
            ignoreMic(for: 5)
            lastVolume = session.outputVolume
            gestureStartedAt = nil
            wiggles = 0
            volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
                let volume = session.outputVolume
                DispatchQueue.main.async { self?.volumeChanged(to: volume) }
            }
            routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.ignoreMic(for: 3)
            }
            player.scheduleBuffer(silence, at: nil, options: .loops)
            player.play()
            self.engine = engine
            state = .playing
            let route = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
            status = L("The watch speaker is on (\(route))", "Saatin hoparlörü açık (\(route))")
            log(.info, L("Watch speaker on, output: \(route)", "Saatin hoparlörü açık, çıkış: \(route)"))
            onPlaying?()
        } catch {
            fail(L("Could not open the audio route: ", "Ses yolu açılamadı: ") + error.localizedDescription)
            stop()
        }
    }

    // At least 0.8 s of uninterrupted digital silence = the mic was switched off on the watch
    private func micLevel(_ peak: Float) {
        guard state == .playing else { return }
        let now = Date()
        guard now > micIgnoredUntil else { return }
        if peak == 0 {
            nonZeroSince = nil
            if zeroSince == nil { zeroSince = now }
            if micOffSince == nil, let since = zeroSince, now.timeIntervalSince(since) >= 0.8 {
                micOffSince = since
            }
        } else {
            zeroSince = nil
            guard let off = micOffSince else { return }
            if nonZeroSince == nil { nonZeroSince = now }
            // On again after ~2 readings (64 ms each) with sound
            guard let on = nonZeroSince, now.timeIntervalSince(on) >= 0.12 else { return }
            micOffSince = nil
            nonZeroSince = nil
            let seconds = on.timeIntervalSince(off)
            let text = String(format: "%.1f", seconds)
            // The volume panel on the watch also cuts the mic briefly
            if lastVolumeChange > off.addingTimeInterval(-1) {
                return log(.info, L("Mic was off for \(text) s while the volume changed, ignored", "Mikrofon \(text) sn kapalıydı ama ses de değişti, yok sayıldı"))
            }
            log(.info, L("Mic on the watch was off for \(text) s", "Saatte mikrofon \(text) sn kapalıydı"))
            onMicToggled?(seconds)
        }
    }

    // Gestures with the volume panel on the watch:
    //  - down a little and right back up (within 2.5 s): .wiggle; twice in a row: .doubleWiggle
    //  - down to the bottom (below 20%, at least 30% lower than before) and up again: .bottom (fires on the first step up)
    private func volumeChanged(to volume: Float) {
        lastVolumeChange = Date()
        let previous = lastVolume
        lastVolume = volume
        guard state == .playing, onVolumeGesture != nil, abs(volume - previous) > 0.005 else { return }
        let now = Date()
        if now < gestureCooldownUntil { return }
        if let first = gestureStartedAt, now.timeIntervalSince(first) > 6 { gestureStartedAt = nil }
        if volume < previous {
            if gestureStartedAt == nil {
                gestureStartedAt = now
                gestureStartLevel = previous
                gestureLowest = volume
            } else {
                gestureLowest = min(gestureLowest, volume)
            }
            return
        }
        // Going up
        guard let first = gestureStartedAt else { return }
        if gestureLowest <= 0.2 && gestureStartLevel - gestureLowest >= 0.3 {
            gestureStartedAt = nil
            // The rest of the way up is just the volume
            gestureCooldownUntil = now.addingTimeInterval(4)
            log(.info, L("Volume down to the bottom and up on the watch", "Saatte ses en alta inip açıldı"))
            wiggleTimer?.cancel()
            wiggles = 0
            onVolumeGesture?(.bottom)
        } else if volume >= gestureStartLevel - 0.08, now.timeIntervalSince(first) <= 2.5 {
            gestureStartedAt = nil
            wiggles += 1
            log(.info, L("Volume − + on the watch (\(wiggles))", "Saatte ses − + (\(wiggles))"))
            wiggleTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let gesture: VolumeGesture = self.wiggles >= 2 ? .doubleWiggle : .wiggle
                self.wiggles = 0
                self.onVolumeGesture?(gesture)
            }
            wiggleTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (wiggles >= 2 ? 0 : 1.5), execute: work)
        }
    }

    private func finish(_ text: String) {
        let wasPlaying = state == .playing
        wiggleTimer?.cancel()
        volumeObservation = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        callID = nil
        state = .idle
        status = text
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if wasPlaying { onEnded?() }
    }

    private func fail(_ text: String) {
        status = text
        log(.error, L("Watch speaker: ", "Saatin hoparlörü: ") + text)
    }

    // MARK: - CallKit

    func providerDidReset(_ provider: CXProvider) {
        finish(L("Ended", "Bitti"))
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        try? configureSession()
        action.fulfill()
        status = L("Answered, opening the audio route…", "Açıldı, ses yolu kuruluyor…")
        // If CallKit does not activate the session (no didActivate), activate it here
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard self.callID != nil, self.state == .ringing else { return }
            do {
                try self.session.setActive(true)
                self.startSilence()
            } catch {
                self.fail(L("Could not activate audio: ", "Ses oturumu açılamadı: ") + error.localizedDescription)
                self.stop()
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        finish(state == .ringing ? L("Not answered", "Açılmadı") : L("Ended", "Bitti"))
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        guard callID != nil else { return }
        startSilence()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        if state == .playing { finish(L("Ended", "Bitti")) }
    }
}

struct WatchSpeakerSection: View {
    @ObservedObject var speaker: WatchSpeaker

    var body: some View {
        Section {
            switch speaker.state {
            case .idle:
                Button(speaker.buttonTitle ?? L("Ring the watch and listen on its speaker", "Saati arat, hoparlöründen dinle")) { speaker.ring() }
                    .fontWeight(.semibold)
            case .ringing:
                Label(L("The watch is ringing: answer it on the watch", "Saat çalıyor: saatten aç"), systemImage: "phone.arrow.down.left")
                Button(L("Cancel", "Vazgeç"), role: .destructive) { speaker.stop() }
            case .playing:
                Label(L("The watch speaker is on", "Saatin hoparlörü açık"), systemImage: "speaker.wave.2.fill").foregroundStyle(.green)
                Button(L("End", "Bitir"), role: .destructive) { speaker.stop() }
            }
            if speaker.onMicToggled != nil {
                Toggle(L("Mic button on the watch changes the song", "Saatteki mikrofon tuşuyla şarkı değiştir"), isOn: $speaker.micGestures)
                    .disabled(speaker.state != .idle)
            }
            if let status = speaker.status, speaker.state == .idle {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Watch speaker", "Saatin hoparlörü"))
        } footer: {
            Text(speaker.footer ?? L("The watch rings like a call. Answer it on the watch, then play something in any app on the iPhone (Spotify, Apple Music, a podcast…): it comes out of the watch speaker at phone-call quality. Hang up on the watch to stop. The watch has to be connected to the iPhone for calls.",
                                     "Saat arama gibi çalar. Saatten aç, sonra iPhone'da herhangi bir uygulamada (Spotify, Apple Music, podcast…) bir şey çal: saatin hoparlöründen telefon görüşmesi kalitesinde çıkar. Saatten kapatınca biter. Saatin aramalar için iPhone'a bağlı olması gerekir."))
        }
    }
}
