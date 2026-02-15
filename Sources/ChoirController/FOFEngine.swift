import Foundation

// FOF (Fonction d'Onde Formantique) synthesis — CHANT model.
//
// Each formant is an exponentially-decaying sinusoid with a half-cosine onset taper,
// triggered once per pitch period. The FOF waveform per formant is:
//
//   s(n) = ½(1 − cos(βn)) · e^(−αn) · sin(ωn),  0 ≤ n ≤ π/β   (onset)
//   s(n) = e^(−αn) · sin(ωn),                      n > π/β       (decay)
//
// Where:  ω = 2π·freq/sr,  α = π·BW/sr,  π/β = skirt duration (from AUTOTEX: 1/(2·BW))
//
// References:
//   Bennett & Rodet (1989), "Synthesis of the Singing Voice", MIT Press.
//   Serafin, "Music 320 Lab 3: Sound synthesis with FOFs", CCRMA Stanford.
//   Formant data: OM-Chant formants.lisp (IRCAM, Bresson & Stroppa, 2010–2019, GPL-3.0).

// MARK: - FOF Grain

/// One FOF grain = one formant, retriggered each pitch period.
struct FOFGrain {
    var phase: Float = 0        // sinusoid phase (radians)
    var omega: Float = 0        // 2π × formantFreq / sampleRate
    var alpha: Float = 0        // decay rate per sample = π × BW / sr
    var amplitude: Float = 0    // peak amplitude for this formant (linear, from CHANT dB table)
    var env: Float = 0          // current exponential envelope value
    var age: Float = 0          // samples since last trigger
    var skirtLen: Float = 0     // onset taper duration in samples (π/β, from AUTOTEX: sr/(2×BW))
}

// MARK: - FOF Voice

/// Per-voice state for FOF synthesis (5 formant grains per CHANT standard).
struct FOFVoice {
    var note: UInt8 = 0
    var isActive: Bool = false
    var phase: Double = 0
    var velocityGain: Float = 1.0

    // ADSR — FOF uses a gentler attack for smooth grain onset
    var envState: Int32 = 4
    var envValue: Float = 0
    var envTime: Double = 0
    var releaseLevel: Float = 0

    // Vibrato
    var vibratoDepth: Float = 0
    var vibratoPhase: Double = 0
    var noteTime: Double = 0

    // 5 formant grains (CHANT standard)
    var g1: FOFGrain = .init()
    var g2: FOFGrain = .init()
    var g3: FOFGrain = .init()
    var g4: FOFGrain = .init()
    var g5: FOFGrain = .init()
    var useFormant: Bool = false

    // Consonant: noise-excited FOF grain
    var cGrain: FOFGrain = .init()
    var noiseDur: Float = 0
    var noiseAmp: Float = 0
    var noiseSeed: UInt32 = 1
    var noiseTriggerPhase: Float = 0
    var noiseTriggerRate: Float = 0
}

// MARK: - FOF Synth

/// FOF synthesizer using the CHANT model (Bennett & Rodet 1989).
final class FOFSynth: SynthEngine {

    let maxVoices: Int
    let voices: UnsafeMutablePointer<FOFVoice>
    var sampleRate: Float
    var consonantCutoff: Float = 760

    init(maxVoices: Int = 16, sampleRate: Float = 44100) {
        self.maxVoices = maxVoices
        self.sampleRate = sampleRate
        voices = .allocate(capacity: maxVoices)
        for i in 0..<maxVoices { voices[i] = FOFVoice() }
    }

    deinit { voices.deallocate() }

    // MARK: - Note Events

    func noteOn(note: UInt8, velocity: UInt8, vowel: UInt8, consonant: UInt8, vibrato: UInt8) {
        guard let i = freeVoice() else { return }

        var v = FOFVoice()
        v.note = note
        v.isActive = true
        v.envState = 0
        v.velocityGain = Float(velocity) / 127.0
        v.vibratoDepth = Float(vibrato) / 127.0
        v.noiseSeed = UInt32(note) &+ UInt32(vowel) &+ 1

        // Vowel → 5 CHANT formant grains
        let resolvedVowel = vowel == 0 ? FormantSynth.randomVowelCC() : vowel
        if resolvedVowel < 118 {
            let f = Self.chantFormants(forCC: resolvedVowel)
            v.useFormant = true
            Self.setupGrain(&v.g1, freq: f.0.freq, amp: f.0.amp, bw: f.0.bw, sr: sampleRate)
            Self.setupGrain(&v.g2, freq: f.1.freq, amp: f.1.amp, bw: f.1.bw, sr: sampleRate)
            Self.setupGrain(&v.g3, freq: f.2.freq, amp: f.2.amp, bw: f.2.bw, sr: sampleRate)
            Self.setupGrain(&v.g4, freq: f.3.freq, amp: f.3.amp, bw: f.3.bw, sr: sampleRate)
            Self.setupGrain(&v.g5, freq: f.4.freq, amp: f.4.amp, bw: f.4.bw, sr: sampleRate)
        }

        // Consonant → noise-excited FOF grain
        let resolvedCons = consonant == 0 ? FormantSynth.randomConsonantCC() : consonant
        let cp = Self.fofConsonant(forCC: resolvedCons)
        v.noiseDur = cp.duration
        v.noiseAmp = cp.amplitude
        if cp.duration > 0 {
            Self.setupGrain(&v.cGrain, freq: cp.centerFreq, amp: 1.0, bw: cp.bandwidth, sr: sampleRate)
            v.noiseTriggerRate = cp.centerFreq / sampleRate
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

    // MARK: - Grain DSP

    /// Configure a grain from CHANT parameters (freq Hz, amp linear, bandwidth Hz).
    @inline(__always)
    static func setupGrain(_ g: inout FOFGrain, freq: Float, amp: Float, bw: Float, sr: Float) {
        g.omega = 2.0 * Float.pi * freq / sr
        g.alpha = Float.pi * bw / sr               // decay rate per sample
        g.amplitude = amp                           // peak amplitude (linear)
        g.env = 0
        g.age = 0
        // Skirt duration: CHANT AUTOTEX rule = 1/(2×BW) seconds → samples
        g.skirtLen = max(sr / (2.0 * max(bw, 1)), 20)
    }

    /// Trigger a grain at the start of a new pitch period.
    @inline(__always)
    static func triggerGrain(_ g: inout FOFGrain) {
        g.phase = 0
        g.env = 1.0
        g.age = 0
    }

    /// Advance one sample: CHANT FOF waveform.
    @inline(__always)
    static func tickGrain(_ g: inout FOFGrain) -> Float {
        guard g.env > 0.0001 else { return 0 }

        // Decaying sinusoid
        let raw = sin(g.phase) * g.env * g.amplitude

        // Onset taper: ½(1 − cos(π·age/skirtLen)) during skirt period
        let taper: Float
        if g.age < g.skirtLen {
            taper = 0.5 * (1.0 - cos(Float.pi * g.age / g.skirtLen))
        } else {
            taper = 1.0
        }

        // Advance state
        g.phase += g.omega
        if g.phase > 2.0 * Float.pi { g.phase -= 2.0 * Float.pi }
        g.env *= (1.0 - g.alpha)  // exponential decay: e^(-α·n) ≈ (1-α)^n for small α
        g.age += 1

        return raw * taper
    }

    // MARK: - Render

    @inline(__always)
    func renderSample(dt: Double) -> Float {
        let sr = sampleRate
        let atk: Double = 0.02, dec: Double = 0.15, sus: Float = 0.55, rel: Double = 0.6
        let vRate: Double = 4.5, vRamp: Double = 1.2, vMax: Double = 0.6

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

            // ── Pitch period → trigger all 5 formant grains ──
            let inc = freq / Double(sr)
            voices[i].phase += inc
            if voices[i].phase >= 1.0 {
                voices[i].phase -= 1.0
                if voices[i].useFormant {
                    Self.triggerGrain(&voices[i].g1)
                    Self.triggerGrain(&voices[i].g2)
                    Self.triggerGrain(&voices[i].g3)
                    Self.triggerGrain(&voices[i].g4)
                    Self.triggerGrain(&voices[i].g5)
                }
            }

            // ── Sum 5 formant grains (amplitudes baked in from CHANT table) ──
            var voiced: Float
            if voices[i].useFormant {
                let s1 = Self.tickGrain(&voices[i].g1)
                let s2 = Self.tickGrain(&voices[i].g2)
                let s3 = Self.tickGrain(&voices[i].g3)
                let s4 = Self.tickGrain(&voices[i].g4)
                let s5 = Self.tickGrain(&voices[i].g5)
                voiced = s1 + s2 + s3 + s4 + s5
            } else {
                voiced = 0
            }

            // ── Consonant: noise-excited FOF grain ──
            var consonantOut: Float = 0
            let cTime = Float(voices[i].noteTime)
            let dur = voices[i].noiseDur
            if dur > 0 && voices[i].noiseAmp > 0 {
                let fade: Float
                if cTime < dur { fade = 1.0 }
                else { fade = exp(-(cTime - dur) / (dur * 0.4)) }

                if fade > 0.01 {
                    let rand = FormantSynth.xorshift(&voices[i].noiseSeed)
                    let randAbs = abs(rand)
                    voices[i].noiseTriggerPhase += voices[i].noiseTriggerRate
                    if voices[i].noiseTriggerPhase >= 1.0 || randAbs > 0.97 {
                        voices[i].noiseTriggerPhase -= 1.0
                        voices[i].cGrain.phase = rand * Float.pi
                        voices[i].cGrain.env = 0.5 + randAbs * 0.5
                        voices[i].cGrain.age = 0
                    }
                    consonantOut = Self.tickGrain(&voices[i].cGrain) * voices[i].noiseAmp * fade * 0.35
                }
            }

            // ── ADSR ──
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

            out += (voiced * voices[i].envValue + consonantOut) * voices[i].velocityGain
        }

        return out * 0.4
    }

    // MARK: - CHANT Formant Table

    /// Single formant parameters: frequency (Hz), amplitude (linear), bandwidth (Hz).
    struct CHANTFormant {
        let freq: Float
        let amp: Float   // linear scale (converted from dB)
        let bw: Float    // Hz
    }

    /// Convert dB to linear amplitude.
    @inline(__always)
    private static func dBtoLin(_ dB: Float) -> Float {
        return pow(10.0, dB / 20.0)
    }

    /// 5-formant CHANT data mapped from Choir CC3 vowel values.
    /// Source: OM-Chant formants.lisp (IRCAM), Bass & Tenor voice types.
    /// Format per formant: (frequency Hz, amplitude dB→linear, bandwidth Hz)
    static func chantFormants(forCC cc: UInt8) -> (CHANTFormant, CHANTFormant, CHANTFormant, CHANTFormant, CHANTFormant) {
        // Helper to build a 5-formant set from (freq, dB, bw) triples
        func f(_ f1: Float, _ a1: Float, _ b1: Float,
               _ f2: Float, _ a2: Float, _ b2: Float,
               _ f3: Float, _ a3: Float, _ b3: Float,
               _ f4: Float, _ a4: Float, _ b4: Float,
               _ f5: Float, _ a5: Float, _ b5: Float
        ) -> (CHANTFormant, CHANTFormant, CHANTFormant, CHANTFormant, CHANTFormant) {
            return (CHANTFormant(freq: f1, amp: dBtoLin(a1), bw: b1),
                    CHANTFormant(freq: f2, amp: dBtoLin(a2), bw: b2),
                    CHANTFormant(freq: f3, amp: dBtoLin(a3), bw: b3),
                    CHANTFormant(freq: f4, amp: dBtoLin(a4), bw: b4),
                    CHANTFormant(freq: f5, amp: dBtoLin(a5), bw: b5))
        }

        switch cc {
        //                         F1    A1   BW1    F2    A2   BW2    F3    A3   BW3    F4    A4   BW4    F5    A5   BW5

        // ── Open vowels ──
        // ɑː (star) — Bass A
        case   6...12:  return f( 600,   0,  60,  1040,  -7,  70,  2250,  -9, 110,  2450,  -9, 120,  2750, -20, 130)
        // aɪ (buy) — between Bass A and Tenor I
        case  13...19:  return f( 650,   0,  80,  1080, -10,  80,  2650,  -9, 110,  2900, -12, 120,  3250, -22, 130)
        // æ (pat) — Countertenor A (brighter open)
        case  20...27:  return f( 660,   0,  80,  1120,  -6,  90,  2750, -23, 120,  3000, -24, 130,  3350, -38, 140)

        // ── Mid vowels ──
        // ə (the) — between Bass E and A (schwa)
        case  28...34:  return f( 500,   0,  50,  1300, -10,  75,  2400, -12, 110,  2800, -14, 120,  3100, -22, 130)

        // ── Back rounded vowels ──
        // ɔː (store) — Tenor O
        case  35...42:  return f( 400,   0,  70,   800, -10,  80,  2600, -12, 100,  2800, -12, 130,  3000, -26, 135)
        // ɔɪ (coy) — Countertenor O
        case  43...49:  return f( 430,   0,  40,   820, -10,  80,  2700, -26, 100,  3000, -22, 120,  3300, -34, 120)
        // ɒ (pot) — Bass O
        case  50...57:  return f( 400,   0,  40,   750, -11,  80,  2400, -21, 100,  2600, -20, 120,  2900, -40, 120)
        // ʌ (cut) — Tenor A (mid-open)
        case  58...64:  return f( 650,   0,  80,  1080,  -6,  90,  2650,  -7, 120,  2900,  -8, 130,  3250, -22, 140)

        // ── Close rounded ──
        // uː (zoo) — Bass U
        case  65...72:  return f( 350,   0,  40,   600, -20,  80,  2400, -32, 100,  2675, -28, 120,  2950, -36, 120)

        // ── Front/close vowels ──
        // iː (free) — Bass I
        case  73...79:  return f( 250,   0,  60,  1750, -30,  90,  2600, -16, 100,  3050, -22, 120,  3340, -28, 120)
        // ɪə (hear) — between Tenor I and E
        case  80...87:  return f( 350,   0,  50,  1780, -18,  85,  2700, -15, 100,  3200, -18, 120,  3540, -26, 120)
        // eɪ (stray) — Bass E
        case  88...94:  return f( 400,   0,  40,  1620, -12,  80,  2400,  -9, 100,  2800, -12, 120,  3100, -18, 120)
        // ɛə (stair) — Tenor E
        case  95...102: return f( 400,   0,  70,  1700, -14,  80,  2600, -12, 100,  3200, -14, 120,  3580, -20, 120)
        // ʊə (cure) — between Bass U and O
        case 103...109: return f( 375,   0,  40,   675, -16,  80,  2400, -26, 100,  2650, -24, 120,  2925, -38, 120)
        // m̩ (nasal) — Male O closed, nasalized
        case 110...117: return f( 325,   0,  73,   700, -12,  80,  2550, -26, 125,  2850, -22, 131,  3100, -28, 135)

        // Default → schwa
        default:        return f( 500,   0,  50,  1300, -10,  75,  2400, -12, 110,  2800, -14, 120,  3100, -22, 130)
        }
    }

    // MARK: - FOF Consonant Table

    /// Consonant parameters for noise-excited FOF grains.
    struct FOFConsonantParams {
        let duration: Float
        let amplitude: Float
        let centerFreq: Float   // grain sinusoid frequency
        let bandwidth: Float    // controls grain decay rate
    }

    static func fofConsonant(forCC cc: UInt8) -> FOFConsonantParams {
        switch cc {
        case 125...127: return .init(duration: 0, amplitude: 0, centerFreq: 0, bandwidth: 0)

        // Bilabial plosives — very short, low-freq grain bursts
        case 4...6:     return .init(duration: 0.010, amplitude: 0.7, centerFreq:  250, bandwidth: 600)
        case 7...9:     return .init(duration: 0.012, amplitude: 0.6, centerFreq:  300, bandwidth: 600)
        case 10...13:   return .init(duration: 0.012, amplitude: 0.6, centerFreq:  280, bandwidth: 600)
        case 14...16:   return .init(duration: 0.012, amplitude: 0.6, centerFreq:  280, bandwidth: 650)
        case 79...82:   return .init(duration: 0.012, amplitude: 0.9, centerFreq:  450, bandwidth: 800)
        case 83...85:   return .init(duration: 0.015, amplitude: 0.8, centerFreq:  450, bandwidth: 800)
        case 86...88:   return .init(duration: 0.015, amplitude: 0.8, centerFreq:  450, bandwidth: 850)

        // Alveolar plosives
        case 20...22:   return .init(duration: 0.012, amplitude: 0.9, centerFreq: 3000, bandwidth: 1200)
        case 23...26:   return .init(duration: 0.015, amplitude: 0.8, centerFreq: 3000, bandwidth: 1300)
        case 102...105: return .init(duration: 0.010, amplitude: 1.0, centerFreq: 3500, bandwidth: 1400)
        case 106...108: return .init(duration: 0.012, amplitude: 0.9, centerFreq: 3500, bandwidth: 1400)

        // Velar plosives
        case 40...42:   return .init(duration: 0.015, amplitude: 0.9, centerFreq: 1800, bandwidth: 1000)
        case 43...45:   return .init(duration: 0.018, amplitude: 0.8, centerFreq: 1800, bandwidth: 1000)
        case 46...49:   return .init(duration: 0.018, amplitude: 0.8, centerFreq: 1800, bandwidth: 1100)
        case 56...59:   return .init(duration: 0.012, amplitude: 1.0, centerFreq: 2000, bandwidth: 1100)
        case 60...62:   return .init(duration: 0.015, amplitude: 0.9, centerFreq: 2000, bandwidth: 1100)
        case 63...65:   return .init(duration: 0.015, amplitude: 0.9, centerFreq: 2000, bandwidth: 1200)

        // Palatal plosive
        case 53...55:   return .init(duration: 0.015, amplitude: 0.8, centerFreq: 2200, bandwidth: 1100)

        // Affricate
        case 17...19:   return .init(duration: 0.100, amplitude: 0.8, centerFreq: 3500, bandwidth: 2000)

        // Fricatives — sustained stochastic grain streams
        case 27...29:   return .init(duration: 0.200, amplitude: 0.7, centerFreq: 5000, bandwidth: 2500)
        case 30...32:   return .init(duration: 0.200, amplitude: 0.6, centerFreq: 5000, bandwidth: 2500)
        case 33...36:   return .init(duration: 0.200, amplitude: 0.6, centerFreq: 5000, bandwidth: 2500)
        case 37...39:   return .init(duration: 0.200, amplitude: 0.6, centerFreq: 5000, bandwidth: 2500)
        case 115...118: return .init(duration: 0.180, amplitude: 0.6, centerFreq: 4000, bandwidth: 2000)
        case 92...95:   return .init(duration: 0.220, amplitude: 0.8, centerFreq: 7000, bandwidth: 3000)
        case 96...98:   return .init(duration: 0.200, amplitude: 0.7, centerFreq: 6500, bandwidth: 2800)
        case 99...101:  return .init(duration: 0.220, amplitude: 0.7, centerFreq: 3500, bandwidth: 2000)
        case 109...111: return .init(duration: 0.150, amplitude: 0.5, centerFreq: 6000, bandwidth: 2500)
        case 112...114: return .init(duration: 0.150, amplitude: 0.5, centerFreq: 6000, bandwidth: 2500)

        // Nasals — low-freq, narrow grains (more tonal)
        case 69...72:   return .init(duration: 0.100, amplitude: 0.7, centerFreq: 280, bandwidth: 100)
        case 73...75:   return .init(duration: 0.080, amplitude: 0.7, centerFreq: 400, bandwidth: 120)
        case 76...78:   return .init(duration: 0.080, amplitude: 0.7, centerFreq: 500, bandwidth: 140)

        // Glottal
        case 50...52:   return .init(duration: 0.140, amplitude: 0.6, centerFreq: 1500, bandwidth: 1200)

        // Approximants
        case 66...68:   return .init(duration: 0.060, amplitude: 0.5, centerFreq: 1200, bandwidth: 500)
        case 89...91:   return .init(duration: 0.060, amplitude: 0.5, centerFreq: 1800, bandwidth: 600)

        // Glides
        case 119...121: return .init(duration: 0.050, amplitude: 0.4, centerFreq:  600, bandwidth: 300)
        case 122...124: return .init(duration: 0.050, amplitude: 0.4, centerFreq: 2200, bandwidth: 500)

        default:        return .init(duration: 0.025, amplitude: 0.6, centerFreq: 2000, bandwidth: 800)
        }
    }
}
