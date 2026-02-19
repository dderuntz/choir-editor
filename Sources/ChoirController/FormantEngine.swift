import Foundation

// DeFormant — formant synthesis engine for Choir Arranger
// by Danny DeRuntz & Claude (Anthropic), 2025–2026
//
// Source-filter vocal model: PolyBLEP sawtooth through biquad bandpass
// formant filters, with vowel/consonant spectral shaping from
// Peterson & Barney (1952) data.

// MARK: - Synth Engine Protocol

/// Common interface for all synth engines.
/// Each engine manages its own voice allocation internally.
/// `renderSample` is called from the audio render thread — must be lock-free.
protocol SynthEngine: AnyObject {
    var sampleRate: Float { get set }
    var consonantCutoff: Float { get set }
    func noteOn(note: UInt8, velocity: UInt8, vowel: UInt8, consonant: UInt8, vibrato: UInt8)
    func noteOff(note: UInt8)
    func renderSample(dt: Double) -> Float
}

/// Local playback mode — automatic follows BLE connection state.
enum LocalAudioMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case on = "On"
    case off = "Off"
    var id: String { rawValue }
}

/// Selectable synth engine types, persisted via @AppStorage.
enum SynthEngineType: String, CaseIterable, Identifiable {
    case formant = "Formant"
    case animalese = "Animalese"
    case lpc = "LPC"
    case fof = "FOF"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .formant: return "DeFormant"
        case .animalese: return "Animalese"
        case .fof: return "FOF (Grain)"
        case .lpc: return "Speak & Spell"
        }
    }
    var blurb: String {
        switch self {
        case .formant: return L("settings.engine.formant")
        case .animalese: return L("settings.engine.animalese")
        case .fof: return L("settings.engine.fof")
        case .lpc: return L("settings.engine.lpc")
        }
    }
}

// Formant data: Peterson & Barney (1952), "Control Methods Used in a Study of the Vowels"
// Biquad filters: Robert Bristow-Johnson, "Audio EQ Cookbook"
// PolyBLEP antialiasing: Välimäki & Franck, "Virtual Analog Oscillators"
// Source-filter model: Julius O. Smith III, "Physical Audio Signal Processing", CCRMA Stanford
//   https://ccrma.stanford.edu/~jos/pasp/Formant_Synthesis_Models.html

// MARK: - DSP Primitives

/// Biquad filter coefficients (bandpass).
struct BiquadCoeffs {
    var b0: Float = 0, b1: Float = 0, b2: Float = 0
    var a1: Float = 0, a2: Float = 0
}

/// Biquad filter delay line.
struct BiquadDelay {
    var x1: Float = 0, x2: Float = 0
    var y1: Float = 0, y2: Float = 0
}

// MARK: - Voice

/// Per-voice state for one sounding note.
/// All value types, no ARC — safe for the audio render thread.
struct FormantVoice {
    var note: UInt8 = 0
    var isActive: Bool = false
    var phase: Double = 0              // sawtooth oscillator phase [0,1)
    var velocityGain: Float = 1.0

    // ADSR envelope (0=attack 1=decay 2=sustain 3=release 4=off)
    var envState: Int32 = 4
    var envValue: Float = 0
    var envTime: Double = 0
    var releaseLevel: Float = 0

    // Vibrato LFO
    var vibratoDepth: Float = 0
    var vibratoPhase: Double = 0
    var noteTime: Double = 0           // total time since note-on

    // Vowel formant filters — 3 parallel bandpass biquads
    var useFormant: Bool = false
    var c1: BiquadCoeffs = .init(); var d1: BiquadDelay = .init()
    var c2: BiquadCoeffs = .init(); var d2: BiquadDelay = .init()
    var c3: BiquadCoeffs = .init(); var d3: BiquadDelay = .init()

    // Consonant noise burst
    var noiseDur: Float = 0            // hold duration (seconds)
    var noiseAmp: Float = 0            // amplitude
    var noiseSeed: UInt32 = 1          // xorshift PRNG state
    var cc: BiquadCoeffs = .init()     // place-of-articulation bandpass coeffs
    var cd: BiquadDelay = .init()      // place-of-articulation bandpass state
    var noiseLpPrev: Float = 0         // one-pole lowpass state (cutoff slider)
}

// MARK: - Formant Synth

/// Polyphonic formant synthesizer (sawtooth → parallel bandpass formants).
/// Conforms to `SynthEngine` for hot-swappable engine selection.
final class FormantSynth: SynthEngine {

    let maxVoices: Int
    let voices: UnsafeMutablePointer<FormantVoice>
    var sampleRate: Float

    /// Lowpass cutoff applied to consonant noise (Hz). Adjustable from UI.
    var consonantCutoff: Float = 760

    init(maxVoices: Int = 16, sampleRate: Float = 44100) {
        self.maxVoices = maxVoices
        self.sampleRate = sampleRate
        voices = .allocate(capacity: maxVoices)
        for i in 0..<maxVoices { voices[i] = FormantVoice() }
    }

    deinit { voices.deallocate() }

    // MARK: - Note Events (main thread)

    func noteOn(note: UInt8, velocity: UInt8, vowel: UInt8, consonant: UInt8, vibrato: UInt8) {
        guard let i = freeVoice() else { return }

        var v = FormantVoice()
        v.note = note
        v.isActive = true
        v.envState = 0
        v.velocityGain = Float(velocity) / 127.0
        v.vibratoDepth = Float(vibrato) / 127.0
        v.noiseSeed = UInt32(note) &+ UInt32(vowel) &+ 1

        // Vowel — "None" (CC ≥ 118) means consonant-only, no pitched voice
        let resolvedVowel = vowel == 0 ? Self.randomVowelCC() : vowel
        if resolvedVowel < 118 {
            v.useFormant = true
            let f = Self.formants(forCC: resolvedVowel)
            v.c1 = Self.bandpass(freq: f.f1, bw: f.bw1, sr: sampleRate)
            v.c2 = Self.bandpass(freq: f.f2, bw: f.bw2, sr: sampleRate)
            v.c3 = Self.bandpass(freq: f.f3, bw: f.bw3, sr: sampleRate)
        }

        // Consonant — "None" (CC 125-127) means no noise burst
        let resolvedCons = consonant == 0 ? Self.randomConsonantCC() : consonant
        let cp = Self.consonantParams(forCC: resolvedCons)
        v.noiseDur = cp.duration
        v.noiseAmp = cp.amplitude
        if cp.duration > 0 {
            v.cc = Self.bandpass(freq: cp.centerFreq, bw: cp.bandwidth, sr: sampleRate)
        }

        voices[i] = v
    }

    func noteOff(note: UInt8) {
        for i in 0..<maxVoices {
            if voices[i].note == note && voices[i].envState < 3 {
                voices[i].envState = 3
                voices[i].envTime = 0
                voices[i].releaseLevel = voices[i].envValue
            }
        }
    }

    private func freeVoice() -> Int? {
        for i in 0..<maxVoices where voices[i].envState == 4 { return i }
        return nil
    }

    // MARK: - Audio Render (real-time thread)

    @inline(__always)
    func renderSample(dt: Double) -> Float {
        let sr = sampleRate
        let atk: Double = 0.01, dec: Double = 0.1, sus: Float = 0.5, rel: Double = 0.5
        let vRate: Double = 4.5, vRamp: Double = 1.0, vMax: Double = 0.5

        // One-pole lowpass coefficient for consonant cutoff
        let rc = 1.0 / (2.0 * Float.pi * consonantCutoff)
        let lpAlpha = (1.0 / sr) / (rc + 1.0 / sr)

        var out: Float = 0

        for i in 0..<maxVoices {
            if voices[i].envState == 4 { continue }
            voices[i].noteTime += dt

            // ── Pitch + vibrato ──
            let baseFreq = 440.0 * pow(2.0, (Double(voices[i].note) - 69.0) / 12.0)
            var freq = baseFreq
            if voices[i].vibratoDepth > 0 {
                let ramp = min(voices[i].noteTime / vRamp, 1.0)
                voices[i].vibratoPhase += vRate * dt
                if voices[i].vibratoPhase >= 1.0 { voices[i].vibratoPhase -= 1.0 }
                let lfo = sin(voices[i].vibratoPhase * .pi * 2.0)
                freq = baseFreq * pow(2.0, Double(voices[i].vibratoDepth) * vMax * ramp * lfo / 12.0)
            }

            // ── Sawtooth oscillator (PolyBLEP) ──
            let inc = freq / Double(sr)
            voices[i].phase += inc
            if voices[i].phase >= 1.0 { voices[i].phase -= 1.0 }
            var source = Float(2.0 * voices[i].phase - 1.0)
            source -= Float(Self.polyBLEP(voices[i].phase, dt: inc))

            // ── Vowel formants (or silence) ──
            var voiced: Float
            if voices[i].useFormant {
                let f1 = Self.biquad(source, &voices[i].c1, &voices[i].d1)
                let f2 = Self.biquad(source, &voices[i].c2, &voices[i].d2)
                let f3 = Self.biquad(source, &voices[i].c3, &voices[i].d3)
                voiced = f1 + f2 * 0.7 + f3 * 0.4
            } else {
                voiced = 0  // no vowel selected → consonant only
            }

            // ── Consonant noise (bypasses ADSR) ──
            // Hold at full amplitude for `noiseDur`, then exponential decay.
            var noise: Float = 0
            let cTime = Float(voices[i].noteTime)
            let dur = voices[i].noiseDur
            if dur > 0 && voices[i].noiseAmp > 0 {
                let fade: Float
                if cTime < dur {
                    fade = 1.0
                } else {
                    fade = exp(-(cTime - dur) / (dur * 0.33))
                }
                if fade > 0.01 {
                    let raw = Self.xorshift(&voices[i].noiseSeed)
                    let shaped = Self.biquad(raw, &voices[i].cc, &voices[i].cd)
                    voices[i].noiseLpPrev += lpAlpha * (shaped - voices[i].noiseLpPrev)
                    noise = voices[i].noiseLpPrev * voices[i].noiseAmp * fade
                }
            }

            // ── ADSR envelope (voiced sound only) ──
            voices[i].envTime += dt
            switch voices[i].envState {
            case 0:
                if voices[i].envTime >= atk {
                    voices[i].envState = 1; voices[i].envTime = 0; voices[i].envValue = 1.0
                } else { voices[i].envValue = Float(voices[i].envTime / atk) }
            case 1:
                if voices[i].envTime >= dec {
                    voices[i].envState = 2; voices[i].envTime = 0; voices[i].envValue = sus
                } else {
                    voices[i].envValue = 1.0 - Float(voices[i].envTime / dec) * (1.0 - sus)
                }
            case 2:
                voices[i].envValue = sus
            case 3:
                if voices[i].envTime >= rel {
                    voices[i].envState = 4; voices[i].envValue = 0; voices[i].isActive = false
                } else {
                    voices[i].envValue = voices[i].releaseLevel * (1.0 - Float(voices[i].envTime / rel))
                }
            default:
                voices[i].envValue = 0
            }

            out += (voiced * voices[i].envValue + noise) * voices[i].velocityGain
        }

        return out * 0.35
    }

    // MARK: - DSP Helpers

    static func bandpass(freq: Float, bw: Float, sr: Float) -> BiquadCoeffs {
        let w = 2.0 * Float.pi * freq / sr
        let sinW = sin(w), cosW = cos(w)
        let alpha = sinW / (2.0 * freq / max(bw, 1.0))
        let a0 = 1.0 + alpha
        return BiquadCoeffs(
            b0:  alpha / a0, b1: 0, b2: -alpha / a0,
            a1: -2.0 * cosW / a0, a2: (1.0 - alpha) / a0
        )
    }

    @inline(__always)
    static func biquad(_ x: Float, _ c: inout BiquadCoeffs, _ d: inout BiquadDelay) -> Float {
        let y = c.b0 * x + c.b1 * d.x1 + c.b2 * d.x2 - c.a1 * d.y1 - c.a2 * d.y2
        d.x2 = d.x1; d.x1 = x
        d.y2 = d.y1; d.y1 = y
        return y
    }

    @inline(__always)
    static func polyBLEP(_ t: Double, dt: Double) -> Double {
        if t < dt {
            let x = t / dt; return x + x - x * x - 1.0
        } else if t > 1.0 - dt {
            let x = (t - 1.0) / dt; return x * x + x + x + 1.0
        }
        return 0.0
    }

    @inline(__always)
    static func xorshift(_ seed: inout UInt32) -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(Int32(bitPattern: seed)) / Float(Int32.max)
    }

    // MARK: - Vowel Formant Table

    struct FormantSet {
        let f1: Float, f2: Float, f3: Float
        let bw1: Float, bw2: Float, bw3: Float
    }

    /// Vowel formant frequencies and bandwidths mapped from Choir CC3 values.
    /// Data: Peterson & Barney (1952).
    static func formants(forCC cc: UInt8) -> FormantSet {
        switch cc {
        //                          F1    F2     F3    BW1  BW2  BW3
        case   6...12:  return .init(f1: 730, f2: 1090, f3: 2440, bw1: 100, bw2: 120, bw3: 200) // ɑː  star
        case  13...19:  return .init(f1: 660, f2: 1220, f3: 2550, bw1: 100, bw2: 120, bw3: 200) // aɪ  buy
        case  20...27:  return .init(f1: 660, f2: 1720, f3: 2410, bw1:  90, bw2: 130, bw3: 200) // æ   pat
        case  28...34:  return .init(f1: 500, f2: 1500, f3: 2500, bw1: 100, bw2: 130, bw3: 200) // ə   the
        case  35...42:  return .init(f1: 400, f2:  680, f3: 2400, bw1:  70, bw2:  80, bw3: 200) // ɔː  store ("ohw")
        case  43...49:  return .init(f1: 450, f2:  730, f3: 2400, bw1:  80, bw2:  90, bw3: 200) // ɔɪ  coy
        case  50...57:  return .init(f1: 360, f2:  640, f3: 2400, bw1:  60, bw2:  70, bw3: 200) // ɒ   pot (deep round)
        case  58...64:  return .init(f1: 640, f2: 1190, f3: 2390, bw1: 100, bw2: 130, bw3: 200) // ʌ   cut
        case  65...72:  return .init(f1: 280, f2:  720, f3: 2240, bw1:  60, bw2:  80, bw3: 200) // uː  zoo ("oooh")
        case  73...79:  return .init(f1: 270, f2: 2290, f3: 3010, bw1:  80, bw2: 130, bw3: 200) // iː  free
        case  80...87:  return .init(f1: 390, f2: 1990, f3: 2550, bw1:  90, bw2: 130, bw3: 200) // ɪə  hear
        case  88...94:  return .init(f1: 530, f2: 1840, f3: 2480, bw1:  90, bw2: 130, bw3: 200) // eɪ  stray
        case  95...102: return .init(f1: 530, f2: 1840, f3: 2480, bw1:  90, bw2: 130, bw3: 200) // ɛə  stair
        case 103...109: return .init(f1: 370, f2: 1150, f3: 2400, bw1:  80, bw2: 130, bw3: 200) // ʊə  cure
        case 110...117: return .init(f1: 300, f2: 1000, f3: 2500, bw1:  60, bw2: 120, bw3: 200) // m̩   nasal
        default:        return .init(f1: 500, f2: 1500, f3: 2500, bw1: 100, bw2: 130, bw3: 200) // ə   default
        }
    }

    // MARK: - Consonant Table

    struct ConsonantParams {
        let duration: Float      // hold time before decay (seconds)
        let amplitude: Float     // peak noise amplitude
        let centerFreq: Float    // bandpass center (Hz)
        let bandwidth: Float     // bandpass width (Hz)
    }

    /// Consonant noise parameters mapped from Choir CC2 values.
    /// Each consonant is modeled as filtered white noise with a hold + exponential decay envelope.
    /// The global `consonantCutoff` lowpass is applied on top in the render.
    static func consonantParams(forCC cc: UInt8) -> ConsonantParams {
        switch cc {
        // ── None ──
        case 125...127: return .init(duration: 0, amplitude: 0, centerFreq: 0, bandwidth: 0)

        // ── Bilabial plosives (B, P) ──
        // B is voiced — very brief, very low-frequency pop (~300 Hz)
        case 4...6:     return .init(duration: 0.008, amplitude: 0.6, centerFreq:  300, bandwidth: 250) // B
        case 7...9:     return .init(duration: 0.010, amplitude: 0.5, centerFreq:  350, bandwidth: 280) // Bj
        case 10...13:   return .init(duration: 0.010, amplitude: 0.5, centerFreq:  300, bandwidth: 250) // Bl
        case 14...16:   return .init(duration: 0.010, amplitude: 0.5, centerFreq:  300, bandwidth: 280) // Br
        // P is unvoiced — slightly brighter, crisper pop
        case 79...82:   return .init(duration: 0.010, amplitude: 0.8, centerFreq:  500, bandwidth: 350) // P
        case 83...85:   return .init(duration: 0.012, amplitude: 0.7, centerFreq:  500, bandwidth: 350) // Pl
        case 86...88:   return .init(duration: 0.012, amplitude: 0.7, centerFreq:  500, bandwidth: 400) // Pr

        // ── Alveolar plosives (D, T) ──
        case 20...22:   return .init(duration: 0.010, amplitude: 0.8, centerFreq: 3000, bandwidth: 1000) // D
        case 23...26:   return .init(duration: 0.012, amplitude: 0.7, centerFreq: 3000, bandwidth: 1100) // Dr
        case 102...105: return .init(duration: 0.008, amplitude: 1.0, centerFreq: 3500, bandwidth: 1000) // T
        case 106...108: return .init(duration: 0.010, amplitude: 0.8, centerFreq: 3500, bandwidth: 1100) // Tr

        // ── Velar plosives (G, K) ──
        case 40...42:   return .init(duration: 0.012, amplitude: 0.8, centerFreq: 1800, bandwidth: 700) // G
        case 43...45:   return .init(duration: 0.015, amplitude: 0.7, centerFreq: 1800, bandwidth: 700) // Gl
        case 46...49:   return .init(duration: 0.015, amplitude: 0.7, centerFreq: 1800, bandwidth: 800) // Gr
        case 56...59:   return .init(duration: 0.010, amplitude: 1.0, centerFreq: 2000, bandwidth: 700) // K
        case 60...62:   return .init(duration: 0.012, amplitude: 0.8, centerFreq: 2000, bandwidth: 700) // Kl
        case 63...65:   return .init(duration: 0.012, amplitude: 0.8, centerFreq: 2000, bandwidth: 800) // Kr

        // ── Palatal plosive ──
        case 53...55:   return .init(duration: 0.012, amplitude: 0.7, centerFreq: 2200, bandwidth: 800) // Dj

        // ── Affricate ──
        case 17...19:   return .init(duration: 0.080, amplitude: 0.7, centerFreq: 3500, bandwidth: 1200) // Tsh

        // ── Fricatives ──
        case 27...29:   return .init(duration: 0.180, amplitude: 0.6, centerFreq: 5000, bandwidth: 1200) // F
        case 30...32:   return .init(duration: 0.180, amplitude: 0.5, centerFreq: 5000, bandwidth: 1200) // Fj
        case 33...36:   return .init(duration: 0.180, amplitude: 0.5, centerFreq: 5000, bandwidth: 1200) // Fl
        case 37...39:   return .init(duration: 0.180, amplitude: 0.5, centerFreq: 5000, bandwidth: 1200) // Fr
        case 115...118: return .init(duration: 0.150, amplitude: 0.5, centerFreq: 4000, bandwidth: 1000) // V
        case 92...95:   return .init(duration: 0.200, amplitude: 0.7, centerFreq: 7000, bandwidth: 1500) // S
        case 96...98:   return .init(duration: 0.180, amplitude: 0.6, centerFreq: 6500, bandwidth: 1400) // Sl
        case 99...101:  return .init(duration: 0.200, amplitude: 0.6, centerFreq: 3500, bandwidth: 1200) // Sh
        case 109...111: return .init(duration: 0.120, amplitude: 0.4, centerFreq: 6000, bandwidth: 1000) // Th
        case 112...114: return .init(duration: 0.120, amplitude: 0.4, centerFreq: 6000, bandwidth: 1000) // Thr

        // ── Nasals (M, N) — low-frequency tonal hum ──
        case 69...72:   return .init(duration: 0.080, amplitude: 0.6, centerFreq: 280, bandwidth: 50)  // M
        case 73...75:   return .init(duration: 0.060, amplitude: 0.6, centerFreq: 400, bandwidth: 60)  // N
        case 76...78:   return .init(duration: 0.060, amplitude: 0.6, centerFreq: 500, bandwidth: 70)  // Nj

        // ── Glottal (H) ──
        case 50...52:   return .init(duration: 0.120, amplitude: 0.5, centerFreq: 1500, bandwidth: 800) // H

        // ── Approximants ──
        case 66...68:   return .init(duration: 0.050, amplitude: 0.4, centerFreq: 1200, bandwidth: 300) // L
        case 89...91:   return .init(duration: 0.050, amplitude: 0.4, centerFreq: 1800, bandwidth: 300) // R

        // ── Glides ──
        case 119...121: return .init(duration: 0.040, amplitude: 0.3, centerFreq:  600, bandwidth: 200) // W
        case 122...124: return .init(duration: 0.040, amplitude: 0.3, centerFreq: 2200, bandwidth: 300) // Y

        default:        return .init(duration: 0.020, amplitude: 0.5, centerFreq: 2000, bandwidth: 500)
        }
    }

    // MARK: - Random Helpers

    static func randomVowelCC() -> UInt8 {
        [8, 16, 23, 31, 38, 53, 61, 68, 76, 91].randomElement()!
    }

    static func randomConsonantCC() -> UInt8 {
        [4, 20, 27, 40, 50, 56, 66, 69, 73, 79, 89, 92, 102, 119, 122, 125].randomElement()!
    }
}
