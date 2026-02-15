import Foundation
import AVFoundation
import Combine

// C-compatible struct for voice data to avoid Swift ARC in render thread
struct VoiceData {
    var note: UInt8
    var phase: Double
    var isActive: Bool
    var envelopeState: Int32 // 0: attack, 1: decay, 2: sustain, 3: release, 4: finished
    var envelopeValue: Float
    var stateTime: Double
    var releaseLevel: Float
    // Vibrato (pitch modulation)
    var vibratoDepth: Float   // 0.0–1.0, from CC value (0–127)
    var vibratoPhase: Double  // LFO phase
    var noteTime: Double      // Total time since note-on (for ramp-in envelope)
}

// Enum mapping for readability (outside render block)
enum EnvelopeState: Int32 {
    case attack = 0
    case decay = 1
    case sustain = 2
    case release = 3
    case finished = 4
}

class AudioMonitorService: ObservableObject {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var reverbNode: AVAudioUnitReverb?
    private var sampleRate: Double = 44100.0
    private var isSetUp = false
    
    @Published var isMuted: Bool = false
    
    // Fixed polyphony limit
    private let maxVoices = 16
    private var voicesPointer: UnsafeMutablePointer<VoiceData>
    
    // Envelope Parameters
    private let attackDuration: Double = 0.01
    private let decayDuration: Double = 0.1
    private let sustainLevel: Float = 0.5
    private let releaseDuration: Double = 0.5
    
    init() {
        // Allocate raw memory for voices
        voicesPointer = UnsafeMutablePointer<VoiceData>.allocate(capacity: maxVoices)
        // Initialize with empty data
        for i in 0..<maxVoices {
            voicesPointer[i] = VoiceData(note: 0, phase: 0, isActive: false, envelopeState: 4, envelopeValue: 0, stateTime: 0, releaseLevel: 0, vibratoDepth: 0, vibratoPhase: 0, noteTime: 0)
        }
        // Preload reverb preset on background thread so it's ready before first note
        let reverb = AVAudioUnitReverb()
        self.reverbNode = reverb
        DispatchQueue.global(qos: .userInitiated).async {
            reverb.loadFactoryPreset(.cathedral)
            reverb.wetDryMix = 25
        }
    }
    
    /// Call to ensure the audio engine is running (lazy setup)
    func ensureStarted() {
        guard !isSetUp else { return }
        setupAudio()
    }
    
    /// Tear down the engine when local audio is disabled
    func tearDown() {
        engine?.stop()
        if let node = sourceNode { engine?.detach(node) }
        if let node = reverbNode { engine?.detach(node) }
        sourceNode = nil
        reverbNode = nil
        engine = nil
        isSetUp = false
    }
    
    deinit {
        voicesPointer.deallocate()
    }
    
    private func setupAudio() {
        let newEngine = AVAudioEngine()
        self.engine = newEngine
        
        let inputFormat = newEngine.outputNode.inputFormat(forBus: 0)
        sampleRate = inputFormat.sampleRate
        
        // Capture parameters locally to avoid self capture in block
        let voices = voicesPointer
        let maxV = maxVoices
        let attack = attackDuration
        let decay = decayDuration
        let sustain = sustainLevel
        let release = releaseDuration
        let sr = sampleRate
        
        // Vibrato constants
        let vibratoRate = 4.5           // Hz — natural singing vibrato
        let vibratoRampTime = 1.0       // seconds to reach full depth
        let vibratoMaxSemitones = 0.5   // ±0.5 semitone at depth=1.0
        
        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let buffers = ablPointer
            let dt = 1.0 / sr
            
            for frame in 0..<Int(frameCount) {
                var sampleValue: Float = 0.0
                
                for i in 0..<maxV {
                    if voices[i].envelopeState == 4 { continue } // Finished
                    
                    // Track total note time (for vibrato ramp-in)
                    voices[i].noteTime += dt
                    
                    // 1. Base frequency
                    let noteDiff = Double(voices[i].note) - 69.0
                    let baseFreq = 440.0 * pow(2.0, noteDiff / 12.0)
                    
                    // 2. Vibrato (pitch modulation)
                    var frequency = baseFreq
                    if voices[i].vibratoDepth > 0 {
                        // Ramp envelope: 0→1 over vibratoRampTime
                        let ramp = min(voices[i].noteTime / vibratoRampTime, 1.0)
                        
                        // LFO: sine wave at vibratoRate Hz
                        voices[i].vibratoPhase += vibratoRate * dt
                        if voices[i].vibratoPhase >= 1.0 { voices[i].vibratoPhase -= 1.0 }
                        let lfo = sin(voices[i].vibratoPhase * 2.0 * .pi)
                        
                        // Pitch deviation in semitones
                        let depthSemitones = Double(voices[i].vibratoDepth) * vibratoMaxSemitones * ramp
                        let pitchMod = depthSemitones * lfo / 12.0
                        frequency = baseFreq * pow(2.0, pitchMod)
                    }
                    
                    // 3. Triangle wave oscillator
                    let increment = frequency / sr
                    voices[i].phase += increment
                    if voices[i].phase >= 1.0 { voices[i].phase -= 1.0 }
                    
                    let oscillator: Float = Float(4.0 * abs(voices[i].phase - 0.5) - 1.0)
                    
                    // 4. ADSR Envelope
                    voices[i].stateTime += dt
                    
                    let state = EnvelopeState(rawValue: voices[i].envelopeState) ?? .finished
                    
                    switch state {
                    case .attack:
                        if voices[i].stateTime >= attack {
                            voices[i].envelopeState = 1 // Decay
                            voices[i].stateTime = 0
                            voices[i].envelopeValue = 1.0
                        } else {
                            voices[i].envelopeValue = Float(voices[i].stateTime / attack)
                        }
                    case .decay:
                        if voices[i].stateTime >= decay {
                            voices[i].envelopeState = 2 // Sustain
                            voices[i].stateTime = 0
                            voices[i].envelopeValue = sustain
                        } else {
                            let progress = Float(voices[i].stateTime / decay)
                            voices[i].envelopeValue = 1.0 - (progress * (1.0 - sustain))
                        }
                    case .sustain:
                        voices[i].envelopeValue = sustain
                    case .release:
                        if voices[i].stateTime >= release {
                            voices[i].envelopeState = 4 // Finished
                            voices[i].envelopeValue = 0.0
                            voices[i].isActive = false
                        } else {
                            let progress = Float(voices[i].stateTime / release)
                            voices[i].envelopeValue = voices[i].releaseLevel * (1.0 - progress)
                        }
                    case .finished:
                        voices[i].envelopeValue = 0.0
                    }
                    
                    sampleValue += oscillator * voices[i].envelopeValue
                }
                
                // Master volume / Polyphony scaling
                sampleValue *= 0.15
                
                for buffer in buffers {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    if frame < buf.count {
                        buf[frame] = sampleValue
                    }
                }
            }
            
            return noErr
        }
        
        // Reverb was pre-created and preset loaded in init()
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
    
    func playNote(note: UInt8, velocity: UInt8 = 100, vibrato: UInt8 = 64, reverb: UInt8 = 32) {
        if isMuted { return }
        ensureStarted()
        
        // Map CC 0–127 → wet/dry 0–50% (keeps it musical, not drenched)
        reverbNode?.wetDryMix = Float(reverb) / 127.0 * 50.0
        
        // Find a free voice or steal one
        var voiceIndex = -1
        
        // 1. Try to find an inactive/finished voice
        for i in 0..<maxVoices {
            if voicesPointer[i].envelopeState == 4 { // Finished
                voiceIndex = i
                break
            }
        }
        
        // 2. If full, steal the oldest release? (Skip for now, just drop note if full)
        if voiceIndex != -1 {
            voicesPointer[voiceIndex] = VoiceData(
                note: note,
                phase: 0.0,
                isActive: true,
                envelopeState: 0, // Attack
                envelopeValue: 0.0,
                stateTime: 0.0,
                releaseLevel: 0.0,
                vibratoDepth: Float(vibrato) / 127.0,
                vibratoPhase: 0.0,
                noteTime: 0.0
            )
        }
    }
    
    func stopNote(note: UInt8) {
        // Find the voice playing this note
        for i in 0..<maxVoices {
            if voicesPointer[i].note == note && voicesPointer[i].envelopeState != 4 && voicesPointer[i].envelopeState != 3 {
                // Trigger release
                voicesPointer[i].envelopeState = 3 // Release
                voicesPointer[i].stateTime = 0
                voicesPointer[i].releaseLevel = voicesPointer[i].envelopeValue
            }
        }
    }
}
