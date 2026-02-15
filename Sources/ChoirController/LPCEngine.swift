import Foundation

// LPC synthesis modeled on the TMS5220 (Speak & Spell).
//
// Uses the correct interleaved lattice filter and float-point coefficient
// tables derived from the official TMS5220 datasheet.
//
// Key characteristics:
// 1. 8 kHz internal sample rate (resampled to output rate)
// 2. Chirp ROM excitation (41-sample patented glottal pulse)
// 3. 10-coefficient lattice filter with quantized reflection coefficients
// 4. Noise excitation for unvoiced consonants through the same lattice filter
//
// References:
//   TMS-Express (GPLv3, Joseph Bellahcen) — CodingTable.hpp, Synthesizer.cpp
//   Arduino Talkie (GPLv3, Peter Knight / Armin Joachimsmeyer) — TalkieLPC.h
//   MAME tms5220.cpp / tms5110r.hxx (BSD-3-Clause, Frank Palazzolo et al.)

// MARK: - TMS5220 Coding Tables (float, from official datasheet)

/// K1 reflection coefficients (32 levels, 5-bit index).
private let tmsK1: [Float] = [
    -0.97850, -0.97270, -0.97070, -0.96680, -0.96290, -0.95900, -0.95310, -0.94140,
    -0.93360, -0.92580, -0.91600, -0.90620, -0.89650, -0.88280, -0.86910, -0.85350,
    -0.80420, -0.74058, -0.66019, -0.56116, -0.44296, -0.30706, -0.15735, -0.00005,
     0.15725,  0.30696,  0.44288,  0.56109,  0.66013,  0.74054,  0.80416,  0.85350
]

/// K2 reflection coefficients (32 levels, 5-bit index).
private let tmsK2: [Float] = [
    -0.64000, -0.58999, -0.53500, -0.47507, -0.41039, -0.34129, -0.26830, -0.19209,
    -0.11350, -0.03345,  0.04702,  0.12690,  0.20515,  0.28087,  0.35325,  0.42163,
     0.48553,  0.54464,  0.59878,  0.64796,  0.69227,  0.73190,  0.76714,  0.79828,
     0.82567,  0.84965,  0.87057,  0.88875,  0.90451,  0.91813,  0.92988,  0.98830
]

/// K3 reflection coefficients (16 levels, 4-bit index).
private let tmsK3: [Float] = [
    -0.86000, -0.75467, -0.64933, -0.54400, -0.43867, -0.33333, -0.22800, -0.12267,
    -0.01733,  0.08800,  0.19333,  0.29867,  0.40400,  0.50933,  0.61467,  0.72000
]

/// K4 reflection coefficients (16 levels, 4-bit index).
private let tmsK4: [Float] = [
    -0.64000, -0.53145, -0.42289, -0.31434, -0.20579, -0.09723,  0.01132,  0.11987,
     0.22843,  0.33698,  0.44553,  0.55409,  0.66264,  0.77119,  0.87975,  0.98830
]

/// K5 reflection coefficients (16 levels, 4-bit index).
private let tmsK5: [Float] = [
    -0.64000, -0.54933, -0.45867, -0.36800, -0.27733, -0.18667, -0.09600, -0.00533,
     0.08533,  0.17600,  0.26667,  0.35733,  0.44800,  0.53867,  0.62933,  0.72000
]

/// K6 reflection coefficients (16 levels, 4-bit index).
private let tmsK6: [Float] = [
    -0.50000, -0.41333, -0.32667, -0.24000, -0.15333, -0.06667,  0.02000,  0.10667,
     0.19333,  0.28000,  0.36667,  0.45333,  0.54000,  0.62667,  0.71333,  0.80000
]

/// K7 reflection coefficients (16 levels, 4-bit index).
private let tmsK7: [Float] = [
    -0.60000, -0.50667, -0.41333, -0.32000, -0.22667, -0.13333, -0.04000,  0.05333,
     0.14667,  0.24000,  0.33333,  0.42667,  0.52000,  0.61333,  0.70667,  0.80000
]

/// K8 reflection coefficients (8 levels, 3-bit index).
private let tmsK8: [Float] = [
    -0.50000, -0.31429, -0.12857,  0.05714,  0.24286,  0.42857,  0.61429,  0.80000
]

/// K9 reflection coefficients (8 levels, 3-bit index).
private let tmsK9: [Float] = [
    -0.50000, -0.34286, -0.18571,  0.02857,  0.12857,  0.28571,  0.44286,  0.60000
]

/// K10 reflection coefficients (8 levels, 3-bit index).
private let tmsK10: [Float] = [
    -0.40000, -0.25714, -0.11429,  0.02857,  0.17143,  0.31429,  0.45714,  0.60000
]

/// TMS5220 chirp ROM (41 samples, float normalized to [-1, 1]).
/// Original patented chirp from the TMS5100 / Speak & Spell (1978).
private let tmsChirp: [Float] = [
    0, 0.328125, -0.34375, 0.390625, -0.609375, 0.140625, 0.2890625, 0.15625,
    0.015625, -0.2421875, -0.4609375, 0.015625, 0.7421875, 0.703125, 0.0390625,
    0.1171875, 0.296875, -0.03125, -0.7109375, -0.7109375, -0.328125, -0.2734375,
    -0.28125, -0.03125, 0.2890625, 0.3359375, 0.265625, 0.2578125, 0.1171875,
    -0.0078125, -0.0625, -0.140625, -0.1484375, -0.1328125, -0.0703125, -0.078125,
    -0.046875, 0, 0.0234375, 0.015625, 0.0078125
]

/// TMS5220 energy table (16 levels, float normalized).
/// Index 0 = silent, index 15 = stop frame (treated as 0).
private let tmsEnergyTable: [Float] = [
    0, 0.00390625, 0.005859375, 0.0078125, 0.009765625, 0.013671875,
    0.01953125, 0.029296875, 0.0390625, 0.0625, 0.080078125,
    0.111328125, 0.158203125, 0.22265625, 0.314453125, 0
]

// MARK: - LPC Frame (a set of TMS5220 table indices)

/// Represents one set of TMS5220 LPC parameters.
/// Voiced frames use K1-K10; unvoiced frames use only K1-K4 (K5-K10 = 0).
private struct LPCFrame {
    var voiced: Bool = true
    var energyIdx: Int = 12      // index into tmsEnergyTable (0-15)
    var k1i: Int = 23            // index into tmsK1 (0-31)
    var k2i: Int = 9             // index into tmsK2 (0-31)
    var k3i: Int = 8             // index into tmsK3 (0-15)
    var k4i: Int = 8             // index into tmsK4 (0-15)
    var k5i: Int = 8             // index into tmsK5 (0-15)
    var k6i: Int = 8             // index into tmsK6 (0-15)
    var k7i: Int = 8             // index into tmsK7 (0-15)
    var k8i: Int = 4             // index into tmsK8 (0-7)
    var k9i: Int = 4             // index into tmsK9 (0-7)
    var k10i: Int = 4            // index into tmsK10 (0-7)

    /// Resolve indices into float coefficient values.
    var energy: Float { tmsEnergyTable[energyIdx] }

    var k: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) {
        if voiced {
            return (tmsK1[k1i], tmsK2[k2i], tmsK3[k3i], tmsK4[k4i], tmsK5[k5i],
                    tmsK6[k6i], tmsK7[k7i], tmsK8[k8i], tmsK9[k9i], tmsK10[k10i])
        } else {
            // Unvoiced: only K1-K4 are meaningful
            return (tmsK1[k1i], tmsK2[k2i], tmsK3[k3i], tmsK4[k4i], 0, 0, 0, 0, 0, 0)
        }
    }
}

// MARK: - Vowel Frame Lookup

/// Map Choir CC3 vowel values to TMS5220 LPC frames (table indices).
///
/// K1 controls spectral tilt / mouth opening:
///   Very negative (idx 0-8)  → closed/high vowels (/i/, /u/)
///   Near zero (idx 16-23)    → mid vowels (/ɛ/, /ə/)
///   Positive (idx 24-31)     → open/low vowels (/ɑ/, /æ/)
///
/// K2 controls tongue position:
///   Negative (idx 0-9)       → back vowels (/u/, /ɔ/)
///   Near zero (idx 10-15)    → central vowels (/ʌ/, /ə/)
///   Positive (idx 16-31)     → front vowels (/i/, /ɛ/)
private func vowelFrame(forCC cc: UInt8) -> LPCFrame {
    // Coefficients precomputed via Levinson-Durbin from FormantSynth's formant data
    // (F1-F3 from Peterson & Barney 1952, F4=3200, F5=3600, typical bandwidths)
    switch cc {
    //                                               K1  K2  K3  K4  K5  K6  K7  K8  K9  K10
    // ── Open/low vowels ──
    case   6...12:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 27, k2i:  7, k3i:  6, k4i: 11, k5i: 12, k6i:  9, k7i:  6, k8i: 3, k9i: 6, k10i: 6) // ɑː star
    case  13...19:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 29, k2i: 13, k3i:  5, k4i:  8, k5i: 11, k6i:  9, k7i:  5, k8i: 3, k9i: 6, k10i: 6) // aɪ buy
    case  20...27:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 30, k2i: 17, k3i: 10, k4i:  9, k5i:  6, k6i:  6, k7i:  7, k8i: 4, k9i: 6, k10i: 6) // æ  pat

    // ── Mid vowels ──
    case  28...34:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 30, k2i: 17, k3i:  7, k4i:  6, k5i:  7, k6i:  7, k7i:  6, k8i: 3, k9i: 6, k10i: 6) // ə  the
    case  58...64:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 28, k2i: 10, k3i:  6, k4i:  9, k5i: 10, k6i:  8, k7i:  6, k8i: 3, k9i: 5, k10i: 6) // ʌ  cut

    // ── Back rounded vowels ──
    case  35...42:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 20, k2i:  2, k3i: 11, k4i: 13, k5i:  9, k6i:  4, k7i:  3, k8i: 2, k9i: 6, k10i: 6) // ɔː store
    case  43...49:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 21, k2i:  2, k3i: 10, k4i: 13, k5i: 10, k6i:  5, k7i:  3, k8i: 2, k9i: 6, k10i: 6) // ɔɪ coy
    case  50...57:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 18, k2i:  2, k3i: 12, k4i: 13, k5i:  8, k6i:  3, k7i:  3, k8i: 3, k9i: 6, k10i: 6) // ɒ  pot
    case  65...72:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 18, k2i:  1, k3i: 11, k4i: 12, k5i:  6, k6i:  4, k7i:  4, k8i: 3, k9i: 6, k10i: 6) // uː zoo

    // ── Front/close vowels ──
    case  73...79:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 31, k2i: 29, k3i: 15, k4i:  8, k5i:  2, k6i:  0, k7i:  2, k8i: 3, k9i: 7, k10i: 6) // iː free
    case  80...87:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 30, k2i: 21, k3i: 12, k4i:  8, k5i:  3, k6i:  2, k7i:  5, k8i: 4, k9i: 6, k10i: 6) // ɪə hear
    case  88...94:  return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 30, k2i: 19, k3i: 11, k4i:  8, k5i:  5, k6i:  4, k7i:  6, k8i: 4, k9i: 6, k10i: 6) // eɪ stray
    case  95...102: return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 30, k2i: 19, k3i: 11, k4i:  8, k5i:  5, k6i:  4, k7i:  6, k8i: 4, k9i: 6, k10i: 6) // ɛə stair
    case 103...109: return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 28, k2i:  7, k3i:  3, k4i:  8, k5i:  8, k6i:  7, k7i:  5, k8i: 3, k9i: 6, k10i: 6) // ʊə cure
    case 110...117: return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 26, k2i:  3, k3i:  3, k4i:  8, k5i: 10, k6i:  7, k7i:  4, k8i: 3, k9i: 6, k10i: 6) // m̩  nasal

    default:        return LPCFrame(voiced: true, energyIdx: 13,
                        k1i: 30, k2i: 17, k3i:  7, k4i:  6, k5i:  7, k6i:  7, k7i:  6, k8i: 3, k9i: 6, k10i: 6) // ə  default
    }
}

// MARK: - Consonant Frame Lookup

/// Map Choir CC2 consonant values to TMS5220 unvoiced LPC frames.
/// Returns (frame, duration in seconds) or nil for "no consonant".
/// Consonants use pitch=0 (noise excitation) through the lattice filter with K1-K4 only.
private func consonantFrame(forCC cc: UInt8) -> (frame: LPCFrame, duration: Float)? {
    switch cc {
    // ── None ──
    case 125...127: return nil

    // ── Bilabial plosives (B, P) — low-frequency pop ──
    case   4...16:  return (LPCFrame(voiced: false, energyIdx: 8,
                        k1i: 24, k2i:  9, k3i: 10, k4i:  8), 0.015)
    case  79...88:  return (LPCFrame(voiced: false, energyIdx: 9,
                        k1i: 22, k2i: 11, k3i:  9, k4i:  7), 0.015)

    // ── Alveolar plosives (D, T) — mid-high burst ──
    case  20...26:  return (LPCFrame(voiced: false, energyIdx: 8,
                        k1i: 14, k2i: 18, k3i:  5, k4i:  6), 0.015)
    case 102...108: return (LPCFrame(voiced: false, energyIdx: 9,
                        k1i: 12, k2i: 20, k3i:  4, k4i:  5), 0.012)

    // ── Velar plosives (G, K) — mid burst ──
    case  40...49:  return (LPCFrame(voiced: false, energyIdx: 8,
                        k1i: 18, k2i: 14, k3i:  7, k4i:  7), 0.018)
    case  56...65:  return (LPCFrame(voiced: false, energyIdx: 9,
                        k1i: 16, k2i: 15, k3i:  6, k4i:  6), 0.015)

    // ── Affricate (Tsh) — burst + fricative ──
    case  17...19:  return (LPCFrame(voiced: false, energyIdx: 8,
                        k1i: 10, k2i: 22, k3i:  4, k4i:  5), 0.070)

    // ── Fricatives — sustained noise ──
    case  27...39:  return (LPCFrame(voiced: false, energyIdx: 7, // F, Fj, Fl, Fr
                        k1i:  8, k2i: 24, k3i:  3, k4i:  5), 0.12)
    case 115...118: return (LPCFrame(voiced: false, energyIdx: 7, // V
                        k1i: 10, k2i: 22, k3i:  4, k4i:  6), 0.10)
    case  92...98:  return (LPCFrame(voiced: false, energyIdx: 8, // S, Sl
                        k1i:  4, k2i: 28, k3i:  2, k4i:  4), 0.15)
    case  99...101: return (LPCFrame(voiced: false, energyIdx: 8, // Sh
                        k1i:  6, k2i: 24, k3i:  3, k4i:  5), 0.12)
    case 109...114: return (LPCFrame(voiced: false, energyIdx: 7, // Th, Thr
                        k1i: 10, k2i: 20, k3i:  5, k4i:  6), 0.10)

    // ── Nasals (M, N) — voiced through lattice ──
    case  69...72:  return (LPCFrame(voiced: true, energyIdx: 9,
                        k1i: 28, k2i:  6, k3i: 12, k4i:  8, k5i: 8, k6i: 8, k7i: 8, k8i: 4, k9i: 4, k10i: 4), 0.06)
    case  73...78:  return (LPCFrame(voiced: true, energyIdx: 9,
                        k1i: 26, k2i: 10, k3i: 11, k4i:  8, k5i: 8, k6i: 8, k7i: 8, k8i: 4, k9i: 4, k10i: 4), 0.05)

    // ── Glottal (H) — breathy noise ──
    case  50...52:  return (LPCFrame(voiced: false, energyIdx: 7,
                        k1i: 20, k2i: 12, k3i:  8, k4i:  8), 0.08)

    // ── Approximants (L, R) ──
    case  66...68:  return (LPCFrame(voiced: true, energyIdx: 9,
                        k1i: 22, k2i: 12, k3i:  9, k4i:  8, k5i: 8, k6i: 8, k7i: 8, k8i: 4, k9i: 4, k10i: 4), 0.04)
    case  89...91:  return (LPCFrame(voiced: true, energyIdx: 9,
                        k1i: 20, k2i: 16, k3i:  7, k4i:  8, k5i: 8, k6i: 8, k7i: 8, k8i: 4, k9i: 4, k10i: 4), 0.04)

    // ── Glides (W, Y) ──
    case 119...121: return (LPCFrame(voiced: true, energyIdx: 8,
                        k1i: 10, k2i:  4, k3i: 10, k4i:  8, k5i: 8, k6i: 8, k7i: 8, k8i: 4, k9i: 4, k10i: 4), 0.03)
    case 122...124: return (LPCFrame(voiced: true, energyIdx: 8,
                        k1i:  8, k2i: 24, k3i:  5, k4i:  8, k5i: 8, k6i: 8, k7i: 8, k8i: 4, k9i: 4, k10i: 4), 0.03)

    default:        return (LPCFrame(voiced: false, energyIdx: 8,
                        k1i: 18, k2i: 14, k3i:  7, k4i:  7), 0.02)
    }
}

// MARK: - LPC Voice

/// Per-voice state for TMS5220-style LPC synthesis.
struct LPCVoice {
    var note: UInt8 = 0
    var isActive: Bool = false
    var velocityGain: Float = 1.0

    // ADSR envelope
    var envState: Int = 4            // 0=atk, 1=dec, 2=sus, 3=rel, 4=off
    var envValue: Float = 0
    var envTime: Double = 0
    var releaseLevel: Float = 0

    // Vibrato
    var vibratoDepth: Float = 0
    var vibratoPhase: Double = 0
    var noteTime: Double = 0

    // Current LPC parameters (resolved floats, ready for the lattice filter)
    var energy: Float = 0
    var isVoiced: Bool = true
    var k: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    // Vowel target (for consonant → vowel transition)
    var vowelEnergy: Float = 0
    var vowelK: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var vowelVoiced: Bool = true
    var consonantDuration: Float = 0         // seconds
    var hasConsonant: Bool = false

    // Lattice filter state (x0..x9)
    var x: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    // Pitch (in 8kHz samples)
    var pitchPeriod: Int = 0
    var periodCount: Int = 0

    // Noise LFSR (TMS5220-style 16-bit)
    var randNoise: UInt16 = 1

    // 8kHz → output rate resampling
    var resamplePhase: Double = 0
    var lastSample: Float = 0
}

// MARK: - LPC Synth

/// TMS5220-style LPC synthesizer producing a robotic "Speak & Spell" voice.
final class LPCSynth: SynthEngine {

    let maxVoices: Int
    let voices: UnsafeMutablePointer<LPCVoice>
    var sampleRate: Float
    var consonantCutoff: Float = 760         // unused, kept for protocol conformance

    /// Internal synthesis rate — the TMS5220 ran at 8 kHz.
    private let lpcRate: Float = 8000

    init(maxVoices: Int = 16, sampleRate: Float = 44100) {
        self.maxVoices = maxVoices
        self.sampleRate = sampleRate
        voices = .allocate(capacity: maxVoices)
        for i in 0..<maxVoices { voices[i] = LPCVoice() }
    }

    deinit { voices.deallocate() }

    // MARK: - Note Events

    func noteOn(note: UInt8, velocity: UInt8, vowel: UInt8, consonant: UInt8, vibrato: UInt8) {
        guard let i = freeVoice() else { return }

        var v = LPCVoice()
        v.note = note
        v.isActive = true
        v.envState = 0
        v.velocityGain = Float(velocity) / 127.0
        v.vibratoDepth = Float(vibrato) / 127.0
        v.randNoise = UInt16((UInt32(note) &* 1103515245 &+ 12345) & 0x7FFF) | 1

        // ── Vowel frame ──
        let resolvedVowel = vowel == 0 ? FormantSynth.randomVowelCC() : vowel
        let vf: LPCFrame
        if resolvedVowel < 118 {
            vf = vowelFrame(forCC: resolvedVowel)
        } else {
            // High CC = unvoiced / breathy (no clear vowel)
            vf = LPCFrame(voiced: false, energyIdx: 10,
                          k1i: 20, k2i: 12, k3i: 8, k4i: 8)
        }
        v.vowelEnergy = vf.energy
        v.vowelK = vf.k
        v.vowelVoiced = vf.voiced

        // ── Consonant frame ──
        let resolvedCons = consonant == 0 ? FormantSynth.randomConsonantCC() : consonant
        if let cf = consonantFrame(forCC: resolvedCons) {
            v.hasConsonant = true
            v.consonantDuration = cf.duration
            v.energy = cf.frame.energy
            v.k = cf.frame.k
            v.isVoiced = cf.frame.voiced
        } else {
            v.hasConsonant = false
            v.consonantDuration = 0
            v.energy = v.vowelEnergy
            v.k = v.vowelK
            v.isVoiced = v.vowelVoiced
        }

        // Pitch period from MIDI note (in 8kHz samples)
        let freq = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        v.pitchPeriod = max(Int(8000.0 / freq), 10)
        v.periodCount = 0

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

    // MARK: - TMS5220 Noise Generator

    /// TMS5220-style LFSR noise (16-bit, polynomial 0xB800).
    @inline(__always)
    static func tmsNoise(_ seed: inout UInt16) -> Bool {
        seed = (seed >> 1) ^ ((seed & 1) != 0 ? 0xB800 : 0)
        return (seed & 1) != 0
    }

    // MARK: - TMS5220 Lattice Filter

    /// 10-stage lattice filter matching the TMS5220 / Talkie / TMS-Express implementation.
    ///
    /// Algorithm (interleaved forward + reverse):
    ///   Stage 10: u -= K10 * x9            (forward only, no x10 to update)
    ///   Stage  9: u -= K9 * x8; x9 = x8 + K9 * u
    ///   Stage  8: u -= K8 * x7; x8 = x7 + K8 * u
    ///   ...
    ///   Stage  1: u -= K1 * x0; x1 = x0 + K1 * u
    ///   x0 = clip(u)
    @inline(__always)
    static func latticeFilter(
        excitation: Float,
        _ k: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float),
        _ x: inout (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float)
    ) -> Float {
        var u = excitation

        // Stage 10 (K10 = k.9) — forward only
        u -= k.9 * x.9

        // Stage 9 (K9 = k.8)
        u -= k.8 * x.8
        x.9 = x.8 + k.8 * u

        // Stage 8 (K8 = k.7)
        u -= k.7 * x.7
        x.8 = x.7 + k.7 * u

        // Stage 7 (K7 = k.6)
        u -= k.6 * x.6
        x.7 = x.6 + k.6 * u

        // Stage 6 (K6 = k.5)
        u -= k.5 * x.5
        x.6 = x.5 + k.5 * u

        // Stage 5 (K5 = k.4)
        u -= k.4 * x.4
        x.5 = x.4 + k.4 * u

        // Stage 4 (K4 = k.3)
        u -= k.3 * x.3
        x.4 = x.3 + k.3 * u

        // Stage 3 (K3 = k.2)
        u -= k.2 * x.2
        x.3 = x.2 + k.2 * u

        // Stage 2 (K2 = k.1)
        u -= k.1 * x.1
        x.2 = x.1 + k.1 * u

        // Stage 1 (K1 = k.0)
        u -= k.0 * x.0
        x.1 = x.0 + k.0 * u

        // Clip and store
        x.0 = max(-1.0, min(1.0, u))
        return x.0
    }

    // MARK: - Render

    @inline(__always)
    func renderSample(dt: Double) -> Float {
        let atk: Double = 0.005, dec: Double = 0.08, sus: Float = 0.6, rel: Double = 0.3
        let vRate: Double = 4.5, vRamp: Double = 1.0, vMax: Double = 0.5

        var out: Float = 0

        for i in 0..<maxVoices {
            if voices[i].envState == 4 { continue }
            voices[i].noteTime += dt

            // ── Consonant → vowel transition ──
            if voices[i].hasConsonant && Float(voices[i].noteTime) >= voices[i].consonantDuration {
                voices[i].hasConsonant = false
                voices[i].energy = voices[i].vowelEnergy
                voices[i].k = voices[i].vowelK
                voices[i].isVoiced = voices[i].vowelVoiced
                // Clear filter state for cleaner transition
                voices[i].x = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            }

            // ── Pitch + vibrato ──
            let baseFreq = 440.0 * pow(2.0, (Double(voices[i].note) - 69.0) / 12.0)
            var freq = baseFreq
            if voices[i].vibratoDepth > 0 && voices[i].isVoiced {
                let ramp = min(voices[i].noteTime / vRamp, 1.0)
                voices[i].vibratoPhase += vRate * dt
                if voices[i].vibratoPhase >= 1.0 { voices[i].vibratoPhase -= 1.0 }
                let lfo = sin(voices[i].vibratoPhase * .pi * 2.0)
                freq = baseFreq * pow(2.0, Double(voices[i].vibratoDepth) * vMax * ramp * lfo / 12.0)
            }
            voices[i].pitchPeriod = max(Int(8000.0 / freq), 10)

            // ── Generate at 8 kHz, resample to output rate (nearest-neighbor for crunch) ──
            voices[i].resamplePhase += Double(lpcRate) / Double(sampleRate)
            while voices[i].resamplePhase >= 1.0 {
                voices[i].resamplePhase -= 1.0

                let excitation: Float
                if voices[i].isVoiced {
                    // Chirp ROM excitation
                    if voices[i].periodCount >= voices[i].pitchPeriod {
                        voices[i].periodCount = 0
                    }
                    if voices[i].periodCount < tmsChirp.count {
                        excitation = tmsChirp[voices[i].periodCount] * voices[i].energy
                    } else {
                        excitation = 0  // silence between chirps
                    }
                    voices[i].periodCount += 1
                } else {
                    // Noise excitation (TMS5220 LFSR)
                    excitation = Self.tmsNoise(&voices[i].randNoise) ? voices[i].energy : -voices[i].energy
                }

                // Lattice filter
                voices[i].lastSample = Self.latticeFilter(
                    excitation: excitation,
                    voices[i].k,
                    &voices[i].x
                )
            }

            let lpcOut = voices[i].lastSample

            // ── ADSR envelope ──
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

            out += lpcOut * voices[i].envValue * voices[i].velocityGain
        }

        return out * 0.18
    }
}
