import AVFoundation
import Combine
import SwiftUI

final class TBPlayer: ObservableObject {
    enum Sound {
        case windup, ding, ticking
    }

    @Published var windupVolume: Double {
        didSet {
            defaults.set(windupVolume, forKey: TBPreferences.windupVolume)
            applyVolume(windupSound, windupVolume)
        }
    }

    @Published var dingVolume: Double {
        didSet {
            defaults.set(dingVolume, forKey: TBPreferences.dingVolume)
            applyVolume(dingSound, dingVolume)
        }
    }

    @Published var tickingVolume: Double {
        didSet {
            defaults.set(tickingVolume, forKey: TBPreferences.tickingVolume)
            applyVolume(tickingSound, tickingVolume)
        }
    }

    @Published private(set) var isPreviewingTicking = false
    @Published private(set) var isTicking = false

    private let defaults: UserDefaults
    private var windupSound: AVAudioPlayer?
    private var dingSound: AVAudioPlayer?
    private var tickingSound: AVAudioPlayer?
    private var tickingPreviewWorkItem: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        windupVolume = Self.clamp(defaults.object(forKey: TBPreferences.windupVolume) as? Double ?? 1)
        dingVolume = Self.clamp(defaults.object(forKey: TBPreferences.dingVolume) as? Double ?? 1)
        tickingVolume = Self.clamp(defaults.object(forKey: TBPreferences.tickingVolume) as? Double ?? 1)

        windupSound = Self.makePlayer(named: "windup")
        dingSound = Self.makePlayer(named: "ding")
        tickingSound = Self.makePlayer(named: "ticking")

        tickingSound?.numberOfLoops = -1
        windupSound?.prepareToPlay()
        dingSound?.prepareToPlay()
        tickingSound?.prepareToPlay()

        applyVolumes()
    }

    deinit {
        tickingPreviewWorkItem?.cancel()
    }

    // MARK: - Playback

    func playWindup() {
        windupSound?.stop()
        windupSound?.currentTime = 0
        windupSound?.play()
    }

    func playDing() {
        dingSound?.stop()
        dingSound?.currentTime = 0
        dingSound?.play()
    }

    func startTicking() {
        tickingPreviewWorkItem?.cancel()
        tickingPreviewWorkItem = nil
        isPreviewingTicking = false
        guard let tickingSound else {
            isTicking = false
            return
        }
        isTicking = true
        tickingSound.currentTime = 0
        tickingSound.play()
    }

    func stopTicking() {
        tickingPreviewWorkItem?.cancel()
        tickingPreviewWorkItem = nil
        isPreviewingTicking = false
        isTicking = false
        tickingSound?.stop()
        tickingSound?.currentTime = 0
    }

    func stopAll() {
        tickingPreviewWorkItem?.cancel()
        tickingPreviewWorkItem = nil
        isPreviewingTicking = false
        isTicking = false
        [windupSound, dingSound, tickingSound].forEach {
            $0?.stop()
            $0?.currentTime = 0
        }
    }

    func preview(_ sound: Sound) {
        switch sound {
        case .windup:
            playWindup()
        case .ding:
            playDing()
        case .ticking:
            toggleTickingPreview()
        }
    }

    private func toggleTickingPreview() {
        if isPreviewingTicking {
            stopTicking()
            return
        }

        // Never let a short preview cancel the ticking of an active focus
        // interval.
        guard !isTicking else {
            return
        }

        tickingPreviewWorkItem?.cancel()
        guard let tickingSound else {
            return
        }
        tickingSound.stop()
        tickingSound.currentTime = 0
        tickingSound.play()
        isPreviewingTicking = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.stopTicking()
        }
        tickingPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    // MARK: - Volume

    private func applyVolumes() {
        applyVolume(windupSound, windupVolume)
        applyVolume(dingSound, dingVolume)
        applyVolume(tickingSound, tickingVolume)
    }

    private func applyVolume(_ player: AVAudioPlayer?, _ volume: Double) {
        player?.setVolume(Float(Self.clamp(volume)), fadeDuration: 0)
    }

    private static func clamp(_ volume: Double) -> Double {
        min(max(volume, 0), 2)
    }

    private static func makePlayer(named name: String) -> AVAudioPlayer? {
        guard let asset = NSDataAsset(name: name) else {
            print("sound asset missing: \(name)")
            return nil
        }

        do {
            return try AVAudioPlayer(data: asset.data, fileTypeHint: AVFileType.wav.rawValue)
        } catch {
            print("cannot create audio player for \(name): \(error)")
            return nil
        }
    }
}
