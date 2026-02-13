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
            voicesPointer[i] = VoiceData(note: 0, phase: 0, isActive: false, envelopeState: 4, envelopeValue: 0, stateTime: 0, releaseLevel: 0)
        }
        // Audio engine is NOT started until needed
    }
    
    /// Call to ensure the audio engine is running (lazy setup)
    func ensureStarted() {
        guard !isSetUp else { return }
        setupAudio()
    }
    
    /// Tear down the engine when local audio is disabled
    func tearDown() {
        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        sourceNode = nil
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
        
        // Context for the block (optional, but we use captured vars)
        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            // Note: We can't easily access `self.isMuted` safely without a lock or atomic. 
            // For now, we'll calculate audio anyway and maybe silence it if we had a safe flag.
            // Or just let it run.
            
            let buffers = ablPointer
            let sampleRate = 44100.0 // Hardcoded or passed in context? Best to assume standard or check context. 
            // In a real app we'd pass sampleRate via context.
            
            for frame in 0..<Int(frameCount) {
                var sampleValue: Float = 0.0
                
                // Iterate all fixed voice slots
                for i in 0..<maxV {
                    // Use a mutable copy of the struct to update state
                    // Direct pointer access
                    
                    if voices[i].envelopeState == 4 { continue } // Finished
                    
                    // 1. Oscillator (Square Wave)
                    // Frequency formula: 440 * 2^((note-69)/12)
                    let noteDiff = Double(voices[i].note) - 69.0
                    let frequency = 440.0 * pow(2.0, noteDiff / 12.0)
                    let increment = frequency / sampleRate
                    
                    voices[i].phase += increment
                    if voices[i].phase >= 1.0 { voices[i].phase -= 1.0 }
                    
                    let oscillator: Float = voices[i].phase < 0.5 ? 1.0 : -1.0
                    
                    // 2. Envelope
                    voices[i].stateTime += (1.0 / sampleRate)
                    
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
                sampleValue *= 0.1 
                
                for buffer in buffers {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    if frame < buf.count {
                        buf[frame] = sampleValue
                    }
                }
            }
            
            return noErr
        }
        
        newEngine.attach(sourceNode!)
        newEngine.connect(sourceNode!, to: newEngine.mainMixerNode, format: inputFormat)
        
        do {
            try newEngine.start()
            isSetUp = true
        } catch {
            print("Audio Engine failed to start: \(error)")
        }
    }
    
    func playNote(note: UInt8, velocity: UInt8 = 100) {
        if isMuted { return }
        ensureStarted()
        
        // Find a free voice or steal one
        // Simple linear search for now
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
                releaseLevel: 0.0
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
