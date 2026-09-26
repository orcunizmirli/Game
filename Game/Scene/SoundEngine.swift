import AVFoundation

/// Tiny synthesizer for the game's sound effects. Every sound is generated at launch from
/// simple waveforms, so the game ships without audio files.
final class SoundEngine {
    enum Sound: CaseIterable {
        case jump, land, death, trap, door, spikes
    }

    static let shared = SoundEngine()

    var isEnabled = true

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private let sampleRate = 44_100.0

    private init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.6
        for sound in Sound.allCases {
            buffers[sound] = synthesize(sound, format: format)
        }
        // Ambient: respects the silent switch and mixes with the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        start()
    }

    private func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            // No audio available (e.g. simulator without output); stay silent.
        }
    }

    func play(_ sound: Sound) {
        guard isEnabled, !players.isEmpty, let buffer = buffers[sound] else { return }
        if !engine.isRunning { start() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // MARK: Synthesis

    private struct Voice {
        var startFrequency: Double
        var endFrequency: Double
        var duration: Double
        var volume: Double
        var square = true
        var noise = 0.0
        var delay = 0.0
    }

    private func voices(for sound: Sound) -> [Voice] {
        switch sound {
        case .jump:
            return [Voice(startFrequency: 320, endFrequency: 660, duration: 0.09, volume: 0.18)]
        case .land:
            return [Voice(startFrequency: 140, endFrequency: 70, duration: 0.05, volume: 0.12, square: false, noise: 0.6)]
        case .death:
            return [
                Voice(startFrequency: 520, endFrequency: 60, duration: 0.28, volume: 0.22),
                Voice(startFrequency: 90, endFrequency: 40, duration: 0.22, volume: 0.2, square: false, noise: 0.9),
            ]
        case .trap:
            return [Voice(startFrequency: 70, endFrequency: 45, duration: 0.22, volume: 0.22, square: false, noise: 0.8)]
        case .spikes:
            return [Voice(startFrequency: 900, endFrequency: 1400, duration: 0.06, volume: 0.12, noise: 0.3)]
        case .door:
            return [
                Voice(startFrequency: 523, endFrequency: 523, duration: 0.08, volume: 0.16),
                Voice(startFrequency: 659, endFrequency: 659, duration: 0.08, volume: 0.16, delay: 0.08),
                Voice(startFrequency: 784, endFrequency: 784, duration: 0.16, volume: 0.16, delay: 0.16),
            ]
        }
    }

    private func synthesize(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let voices = voices(for: sound)
        let length = voices.map { $0.delay + $0.duration }.max() ?? 0.1
        let frames = AVAudioFrameCount(length * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { channel[i] = 0 }

        var seed: UInt32 = 0x9E37_79B9
        func noise() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            return Double(seed) / Double(UInt32.max) * 2 - 1
        }

        for voice in voices {
            let start = Int(voice.delay * sampleRate)
            let count = Int(voice.duration * sampleRate)
            var phase = 0.0
            for n in 0..<count where start + n < Int(frames) {
                let t = Double(n) / Double(count)
                let frequency = voice.startFrequency + (voice.endFrequency - voice.startFrequency) * t
                phase += frequency / sampleRate
                phase -= phase.rounded(.down)
                let tone = voice.square ? (phase < 0.5 ? 1.0 : -1.0) : sin(phase * 2 * .pi)
                let sample = tone * (1 - voice.noise) + noise() * voice.noise
                // Short attack, linear decay.
                let envelope = min(1, Double(n) / (0.004 * sampleRate)) * (1 - t)
                channel[start + n] += Float(sample * envelope * voice.volume)
            }
        }
        return buffer
    }
}
