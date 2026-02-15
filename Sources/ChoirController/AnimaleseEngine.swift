import Foundation
import AVFoundation

// MARK: - Animalese Engine
//
// Sample-based synthesis inspired by Animal Crossing's Animalese speech.
// Phoneme WAV samples (MIT-licensed, equalo-official/animalese-generator)
// are loaded at startup, then played back pitch-shifted to the MIDI note.
// A zero-crossing loop in each sample's sustain region allows indefinite
// note holds with vibrato.

// MARK: - Sample Library

/// Singleton that loads and holds all 30 phoneme samples as Float arrays,
/// along with pre-computed loop points and ear-tuned fundamental frequencies.
final class AnimaleSampleLibrary: @unchecked Sendable {
    static let shared = AnimaleSampleLibrary()

    private(set) var samples: [[Float]] = []
    private(set) var sampleRate: Float = 44100

    /// Pre-computed per-sample data: zero-crossing loop region + fundamental pitch.
    struct SampleInfo {
        let loopStart: Int
        let loopEnd: Int
        let fundamentalHz: Float
    }

    private(set) var info: [SampleInfo] = []

    // MARK: Init

    private init() {
        // Loop points from autocorrelation zero-crossing analysis.
        // Fundamentals from YIN detection, with vowels ear-tuned against each other.
        //
        // Sample mapping: a(0) b(1) c(2) d(3) e(4) f(5) g(6) h(7) i(8) j(9)
        //   k(10) l(11) m(12) n(13) o(14) p(15) q(16) r(17) s(18) t(19)
        //   u(20) v(21) w(22) x(23) y(24) z(25) th(26) sh(27) space(28) period(29)
        info = [
            SampleInfo(loopStart: 3980,  loopEnd: 4774,  fundamentalHz: 56.5),  //  0: a   ear-tuned
            SampleInfo(loopStart: 7945,  loopEnd: 8861,  fundamentalHz: 61.65), //  1: b
            SampleInfo(loopStart: 5882,  loopEnd: 7053,  fundamentalHz: 65.63), //  2: c
            SampleInfo(loopStart: 5596,  loopEnd: 6319,  fundamentalHz: 60.95), //  3: d
            SampleInfo(loopStart: 5522,  loopEnd: 6258,  fundamentalHz: 61.82), //  4: e
            SampleInfo(loopStart: 9439,  loopEnd: 10237, fundamentalHz: 62.0),  //  5: f
            SampleInfo(loopStart: 5603,  loopEnd: 6584,  fundamentalHz: 69.65), //  6: g
            SampleInfo(loopStart: 7393,  loopEnd: 7999,  fundamentalHz: 62.0),  //  7: h
            SampleInfo(loopStart: 4543,  loopEnd: 5266,  fundamentalHz: 62.44), //  8: i
            SampleInfo(loopStart: 5262,  loopEnd: 6346,  fundamentalHz: 61.20), //  9: j
            SampleInfo(loopStart: 7776,  loopEnd: 8589,  fundamentalHz: 62.0),  // 10: k
            SampleInfo(loopStart: 4058,  loopEnd: 4717,  fundamentalHz: 65.33), // 11: l
            SampleInfo(loopStart: 4799,  loopEnd: 5507,  fundamentalHz: 61.51), // 12: m
            SampleInfo(loopStart: 6048,  loopEnd: 6766,  fundamentalHz: 61.62), // 13: n
            SampleInfo(loopStart: 3477,  loopEnd: 4350,  fundamentalHz: 52.0),  // 14: o   ear-tuned
            SampleInfo(loopStart: 6771,  loopEnd: 7620,  fundamentalHz: 62.21), // 15: p
            SampleInfo(loopStart: 5595,  loopEnd: 6701,  fundamentalHz: 65.24), // 16: q
            SampleInfo(loopStart: 11708, loopEnd: 12700, fundamentalHz: 61.93), // 17: r
            SampleInfo(loopStart: 5522,  loopEnd: 6818,  fundamentalHz: 62.0),  // 18: s
            SampleInfo(loopStart: 4474,  loopEnd: 7751,  fundamentalHz: 69.85), // 19: t
            SampleInfo(loopStart: 4034,  loopEnd: 4734,  fundamentalHz: 64.5),  // 20: u   ear-tuned
            SampleInfo(loopStart: 4338,  loopEnd: 7734,  fundamentalHz: 65.41), // 21: v
            SampleInfo(loopStart: 5749,  loopEnd: 6462,  fundamentalHz: 60.34), // 22: w
            SampleInfo(loopStart: 4908,  loopEnd: 6078,  fundamentalHz: 62.0),  // 23: x
            SampleInfo(loopStart: 7362,  loopEnd: 8075,  fundamentalHz: 59.56), // 24: y
            SampleInfo(loopStart: 4181,  loopEnd: 4903,  fundamentalHz: 61.25), // 25: z
            SampleInfo(loopStart: 2531,  loopEnd: 4067,  fundamentalHz: 62.0),  // 26: th
            SampleInfo(loopStart: 5168,  loopEnd: 6188,  fundamentalHz: 62.0),  // 27: sh
            SampleInfo(loopStart: 1261,  loopEnd: 3783,  fundamentalHz: 62.0),  // 28: space
            SampleInfo(loopStart: 7293,  loopEnd: 21879, fundamentalHz: 62.0),  // 29: period
        ]
        loadSamples()
    }

    // MARK: Loading

    private func loadSamples() {
        samples = Array(repeating: [], count: 30)

        for i in 0..<30 {
            let name = String(format: "sound%02d", i + 1)

            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif

            guard let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "AnimaleSounds")
                          ?? bundle.url(forResource: name, withExtension: "wav") else {
                print("AnimaleSampleLibrary: missing \(name).wav")
                samples[i] = makeFallbackSine()
                continue
            }

            do {
                let file = try AVAudioFile(forReading: url)
                sampleRate = Float(file.processingFormat.sampleRate)
                let frameCount = AVAudioFrameCount(file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                    samples[i] = makeFallbackSine()
                    continue
                }
                try file.read(into: buffer)
                if let data = buffer.floatChannelData {
                    samples[i] = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
                }
            } catch {
                print("AnimaleSampleLibrary: error loading \(name).wav: \(error)")
                samples[i] = makeFallbackSine()
            }
        }
        print("AnimaleSampleLibrary: loaded \(samples.count) samples")
    }

    private func makeFallbackSine() -> [Float] {
        (0..<2048).map { Float(sin(Double($0) * 440.0 * 2.0 * .pi / 44100.0)) }
    }

    // MARK: CC → Sample Mapping

    /// Map vowel CC to one of the 5 vowel samples (a, e, i, o, u).
    static func vowelSampleIndex(forCC cc: UInt8) -> Int {
        switch cc {
        case   6...19:  return 0  // open vowels → a
        case  20...34:  return 4  // mid vowels → e
        case  35...57:  return 14 // back rounded → o
        case  58...64:  return 4  // ʌ → e
        case  65...72:  return 20 // uː → u
        case  73...87:  return 8  // front close → i
        case  88...102: return 4  // mid-front → e
        case 103...117: return 20 // rounded → u
        default:        return 0  // fallback → a
        }
    }

    /// Map consonant CC to a letter sample. Returns nil for "no consonant".
    static func consonantSampleIndex(forCC cc: UInt8) -> Int? {
        guard cc < 125 else { return nil }
        switch cc {
        case   4...16:  return 1   // B
        case  17...19:  return 2   // C
        case  20...26:  return 3   // D
        case  27...39:  return 5   // F
        case  40...46:  return 7   // H
        case  47...51:  return 10  // K
        case  52...58:  return 11  // L
        case  59...65:  return 12  // M
        case  66...72:  return 13  // N
        case  73...78:  return 15  // P
        case  79...88:  return 17  // R
        case  89...91:  return 18  // S
        case  92...101: return 27  // Sh
        case 102...108: return 19  // T
        case 109...115: return 21  // V
        case 116...120: return 25  // Z
        case 121...124: return 26  // Th
        default:        return 13  // N
        }
    }
}

// MARK: - Voice

struct AnimaleseVoice {
    var note: UInt8 = 0
    var isActive: Bool = false
    var velocityGain: Float = 1.0

    // Envelope: 0=attack, 1=sustain, 2=release, 3=off
    var envState: Int = 3
    var envValue: Float = 0
    var envTime: Double = 0
    var releaseLevel: Float = 0

    // Sample playback
    var sampleIndex: Int = 0
    var playbackPos: Double = 0
    var playbackRate: Double = 4.0
    var noteTime: Double = 0
    var inLoop: Bool = false
    var loopStart: Double = 0
    var loopEnd: Double = 0

    // Vibrato
    var vibratoDepth: Float = 0
}

// MARK: - Synth

final class AnimaleseSynth: SynthEngine {

    let maxVoices: Int
    let voices: UnsafeMutablePointer<AnimaleseVoice>
    var sampleRate: Float
    var consonantCutoff: Float = 760  // unused, protocol conformance

    private let library: AnimaleSampleLibrary

    init(maxVoices: Int = 16, sampleRate: Float = 44100) {
        self.maxVoices = maxVoices
        self.sampleRate = sampleRate
        self.library = AnimaleSampleLibrary.shared
        voices = .allocate(capacity: maxVoices)
        for i in 0..<maxVoices { voices[i] = AnimaleseVoice() }
    }

    deinit { voices.deallocate() }

    // MARK: Note Events

    func noteOn(note: UInt8, velocity: UInt8, vowel: UInt8, consonant: UInt8, vibrato: UInt8) {
        guard let idx = freeVoice() else { return }

        var v = AnimaleseVoice()
        v.note = note
        v.isActive = true
        v.envState = 0
        v.velocityGain = Float(velocity) / 127.0
        v.vibratoDepth = Float(vibrato) / 127.0

        // Select vowel sample
        let resolvedVowel = vowel == 0 ? FormantSynth.randomVowelCC() : vowel
        v.sampleIndex = AnimaleSampleLibrary.vowelSampleIndex(forCC: resolvedVowel)

        // Playback rate = targetFreq / sampleFundamental
        // Samples are ~62 Hz, so at middle C (261 Hz) this gives ~4.2x — natural Animalese speed.
        let targetFreq = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        v.playbackRate = targetFreq / Double(library.info[v.sampleIndex].fundamentalHz)

        // Zero-crossing loop region
        let si = library.info[v.sampleIndex]
        v.loopStart = Double(si.loopStart)
        v.loopEnd = Double(si.loopEnd)

        voices[idx] = v
    }

    func noteOff(note: UInt8) {
        for i in 0..<maxVoices where voices[i].note == note && voices[i].envState < 2 {
            voices[i].envState = 2
            voices[i].envTime = 0
            voices[i].releaseLevel = voices[i].envValue
        }
    }

    private func freeVoice() -> Int? {
        for i in 0..<maxVoices where voices[i].envState >= 3 || !voices[i].isActive { return i }
        return nil
    }

    // MARK: Sample Reading

    @inline(__always)
    private func readSample(index: Int, pos: Double) -> Float {
        let buf = library.samples[index]
        let iPos = Int(pos)
        guard iPos < buf.count else { return 0 }
        let frac = Float(pos - Double(iPos))
        let s0 = buf[iPos]
        let s1 = (iPos + 1 < buf.count) ? buf[iPos + 1] : 0
        return s0 + (s1 - s0) * frac
    }

    // MARK: Render

    private let attackTime: Double = 0.012
    private let releaseTime: Double = 0.08

    @inline(__always)
    func renderSample(dt: Double) -> Float {
        var out: Float = 0

        for i in 0..<maxVoices {
            guard voices[i].envState < 3 else { continue }

            voices[i].noteTime += dt
            voices[i].envTime += dt

            // ── Envelope ──
            switch voices[i].envState {
            case 0: // Attack
                if voices[i].envTime >= attackTime {
                    voices[i].envState = 1
                    voices[i].envValue = 1.0
                } else {
                    voices[i].envValue = Float(voices[i].envTime / attackTime)
                }
            case 1: // Sustain
                voices[i].envValue = 1.0
            case 2: // Release
                if voices[i].envTime >= releaseTime {
                    voices[i].envState = 3
                    voices[i].envValue = 0
                    voices[i].isActive = false
                } else {
                    voices[i].envValue = voices[i].releaseLevel * (1.0 - Float(voices[i].envTime / releaseTime))
                }
            default:
                break
            }

            // ── Vibrato ──
            var rate = voices[i].playbackRate
            if voices[i].vibratoDepth > 0.1 {
                let vib = sin(voices[i].noteTime * 5.5 * .pi * 2.0) * Double(voices[i].vibratoDepth) * 0.3
                rate *= pow(2.0, vib / 12.0)
            }

            // ── Sample playback with zero-crossing loop ──
            let loopLen = voices[i].loopEnd - voices[i].loopStart
            let sample: Float

            if !voices[i].inLoop {
                // Onset: play naturally until reaching loop end
                sample = readSample(index: voices[i].sampleIndex, pos: voices[i].playbackPos)
                voices[i].playbackPos += rate
                if voices[i].playbackPos >= voices[i].loopEnd && loopLen > 0 {
                    voices[i].inLoop = true
                    voices[i].playbackPos = voices[i].loopStart
                }
            } else if loopLen > 0 {
                // Sustain: loop between matched zero crossings
                sample = readSample(index: voices[i].sampleIndex, pos: voices[i].playbackPos)
                voices[i].playbackPos += rate
                if voices[i].playbackPos >= voices[i].loopEnd {
                    voices[i].playbackPos -= loopLen
                }
            } else {
                sample = 0
            }

            out += sample * voices[i].envValue * voices[i].velocityGain
        }

        return out * 0.55
    }
}
