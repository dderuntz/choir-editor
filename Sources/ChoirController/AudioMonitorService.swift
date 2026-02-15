import Foundation
@preconcurrency import AVFoundation
import Combine

/// Manages the AVAudioEngine plumbing and active synth engine.
/// Supports hot-swapping between SynthEngine implementations.
class AudioMonitorService: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var reverbNode: AVAudioUnitReverb?
    private var sampleRate: Double = 44100.0
    private var isSetUp = false

    @Published var isMuted: Bool = false
    @Published var engineType: SynthEngineType = .formant

    /// The active synth engine. Accessed by SoundPadView for cutoff, etc.
    private(set) var synth: SynthEngine

    init() {
        // Restore persisted engine choice from UserDefaults
        let savedRaw = UserDefaults.standard.string(forKey: "synthEngine") ?? SynthEngineType.formant.rawValue
        let savedType = SynthEngineType(rawValue: savedRaw) ?? .formant
        switch savedType {
        case .formant:   self.synth = FormantSynth()
        case .lpc:       self.synth = LPCSynth()
        case .fof:       self.synth = FOFSynth()
        case .animalese: self.synth = AnimaleseSynth()
        }
        self.engineType = savedType

        // Preload reverb preset on background thread (blocks if called on main)
        let reverb = AVAudioUnitReverb()
        self.reverbNode = reverb
        DispatchQueue.global(qos: .userInitiated).async {
            reverb.loadFactoryPreset(.cathedral)
            reverb.wetDryMix = 25
        }
    }

    // MARK: - Engine Swap

    /// Switch to a new synth engine type. Tears down and rebuilds the audio graph.
    func setEngine(_ type: SynthEngineType) {
        guard type != engineType else { return }
        let wasRunning = isSetUp
        if wasRunning { tearDown() }

        switch type {
        case .formant:   synth = FormantSynth(sampleRate: Float(sampleRate))
        case .lpc:       synth = LPCSynth(sampleRate: Float(sampleRate))
        case .fof:       synth = FOFSynth(sampleRate: Float(sampleRate))
        case .animalese: synth = AnimaleseSynth(sampleRate: Float(sampleRate))
        }
        engineType = type
        UserDefaults.standard.set(type.rawValue, forKey: "synthEngine")

        if wasRunning { setupAudio() }
    }

    /// Lazily start the audio engine on first use.
    func ensureStarted() {
        guard !isSetUp else { return }
        setupAudio()
    }

    /// Tear down the engine when local audio is disabled.
    func tearDown() {
        audioEngine?.stop()
        if let node = sourceNode { audioEngine?.detach(node) }
        // Only detach reverb if it's currently attached
        if let reverb = reverbNode, reverb.engine != nil {
            audioEngine?.detach(reverb)
        }
        sourceNode = nil
        audioEngine = nil
        isSetUp = false
    }

    // MARK: - Setup

    private func setupAudio() {
        let newEngine = AVAudioEngine()
        self.audioEngine = newEngine

        let inputFormat = newEngine.outputNode.inputFormat(forBus: 0)
        sampleRate = inputFormat.sampleRate
        synth.sampleRate = Float(sampleRate)

        // Capture synth reference for render block (class pointer stays valid)
        let engineRef = synth
        let sr = Float(sampleRate)

        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let dt = 1.0 / Double(sr)

            for frame in 0..<Int(frameCount) {
                let sample = engineRef.renderSample(dt: dt)
                for buffer in buffers {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    if frame < buf.count { buf[frame] = sample }
                }
            }
            return noErr
        }

        // Ensure reverb node exists for re-attachment
        if reverbNode == nil {
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.cathedral)
            reverb.wetDryMix = 25
            reverbNode = reverb
        }

        // Connect: source → reverb → mixer
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        newEngine.attach(sourceNode!)
        if let reverb = reverbNode {
            newEngine.attach(reverb)
            newEngine.connect(sourceNode!, to: reverb, format: nil)
            newEngine.connect(reverb, to: newEngine.mainMixerNode, format: stereoFormat)
        } else {
            newEngine.connect(sourceNode!, to: newEngine.mainMixerNode, format: nil)
        }

        do {
            try newEngine.start()
            isSetUp = true
        } catch {
            print("Audio Engine failed to start: \(error)")
        }
    }

    // MARK: - Note Control

    func playNote(note: UInt8, velocity: UInt8 = 100, vibrato: UInt8 = 64, reverb: UInt8 = 32,
                  vowel: UInt8 = 0, consonant: UInt8 = 125) {
        if isMuted { return }
        ensureStarted()
        reverbNode?.wetDryMix = Float(reverb) / 127.0 * 50.0
        synth.noteOn(note: note, velocity: velocity, vowel: vowel, consonant: consonant, vibrato: vibrato)
    }

    func stopNote(note: UInt8) {
        synth.noteOff(note: note)
    }
}
