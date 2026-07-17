import AVFAudio
import UIKit

@MainActor
final class FeedbackController {
    enum Cue {
        case pickup
        case invalid
        case placement
        case clear
        case combo
        case refill
        case gameOver
    }

    var soundEnabled = true
    var hapticsEnabled = true

    private let engine = AVAudioEngine()
    private let effectsPlayer = AVAudioPlayerNode()
    private let musicPlayer = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private var musicTimer: Timer?
    private var musicStep = 0

    init() {
        engine.attach(effectsPlayer)
        engine.attach(musicPlayer)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.42

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            effectsPlayer.play()
            musicPlayer.play()
        } catch {
            // The game remains fully playable when audio is unavailable.
        }
    }

    func play(_ cue: Cue) {
        guard soundEnabled else { return }
        let notes: [(frequency: Double, duration: Double, volume: Float)]
        switch cue {
        case .pickup:
            notes = [(540, 0.045, 0.16)]
            impact(.soft, intensity: 0.45)
        case .invalid:
            notes = [(170, 0.07, 0.16), (135, 0.09, 0.13)]
            notification(.error)
        case .placement:
            notes = [(290, 0.045, 0.2), (430, 0.055, 0.14)]
            impact(.rigid, intensity: 0.65)
        case .clear:
            notes = [(520, 0.06, 0.18), (680, 0.07, 0.16), (880, 0.1, 0.14)]
            notification(.success)
        case .combo:
            notes = [(660, 0.05, 0.17), (880, 0.05, 0.16), (1_100, 0.12, 0.15)]
            impact(.heavy, intensity: 0.75)
        case .refill:
            notes = [(350, 0.04, 0.1), (440, 0.04, 0.1), (550, 0.06, 0.11)]
            impact(.soft, intensity: 0.35)
        case .gameOver:
            notes = [(330, 0.12, 0.14), (247, 0.14, 0.13), (196, 0.22, 0.12)]
            notification(.warning)
        }
        notes.forEach { scheduleNote($0, on: effectsPlayer) }
    }

    func setMusicEnabled(_ enabled: Bool) {
        musicTimer?.invalidate()
        musicTimer = nil
        guard enabled else { return }

        musicStep = 0
        let timer = Timer(timeInterval: 1.55, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.playMusicStep()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        musicTimer = timer
        playMusicStep()
    }

    func pauseMusic() {
        musicTimer?.invalidate()
        musicTimer = nil
    }

    private func playMusicStep() {
        let sequence = [220.0, 277.18, 329.63, 277.18, 246.94, 329.63, 369.99, 329.63]
        let frequency = sequence[musicStep % sequence.count]
        musicStep += 1
        scheduleNote((frequency, 0.42, 0.025), on: musicPlayer, waveform: .soft)
    }

    private enum Waveform {
        case bright
        case soft
    }

    private func scheduleNote(
        _ note: (frequency: Double, duration: Double, volume: Float),
        on player: AVAudioPlayerNode,
        waveform: Waveform = .bright
    ) {
        guard engine.isRunning else { return }
        let frameCount = AVAudioFrameCount(sampleRate * note.duration)
        guard
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let samples = buffer.floatChannelData?[0]
        else {
            return
        }

        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / Double(max(1, Int(frameCount) - 1))
            let attack = min(1, progress / 0.08)
            let release = pow(max(0, 1 - progress), waveform == .soft ? 2.2 : 1.3)
            let phase = 2 * Double.pi * note.frequency * Double(frame) / sampleRate
            let fundamental = sin(phase)
            let overtone = waveform == .bright ? sin(phase * 2) * 0.16 : 0
            samples[frame] = Float(fundamental + overtone) * note.volume * Float(attack * release)
        }
        player.scheduleBuffer(buffer)
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        guard hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    private func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard hapticsEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

