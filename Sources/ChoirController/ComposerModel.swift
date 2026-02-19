import Foundation
import Combine
import os
import FoundationModels

private let log = Logger(subsystem: "com.choir-arranger", category: "composer")

// MARK: - LLM Lyric Generation Types

@available(macOS 26, *)
@Generable
struct LLMLyric {
    @Guide(description: "A short lyric for singing. 2 lines separated by /. Each line 3-8 simple words.")
    let lyric: String
}

// MARK: - Composer Persistence

private struct StoredPhoneme: Codable {
    let text: String
    let consonantCC: UInt8
    let vowelCC: UInt8
    let weight: Int
    var wordIndex: Int = 0
    var isEnsemble: Bool = false
}

private enum ComposerPersistence {
    private static let textKey = "composer.inputText"
    private static let phonemesKey = "composer.phonemes"

    static func saveText(_ text: String) {
        UserDefaults.standard.set(text, forKey: textKey)
    }

    static func loadText() -> String {
        UserDefaults.standard.string(forKey: textKey) ?? ""
    }

    static func savePhonemes(_ phonemes: [ChoirPhoneme]) {
        let stored = phonemes.map { StoredPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC, weight: $0.weight, wordIndex: $0.wordIndex, isEnsemble: $0.isEnsemble) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: phonemesKey)
        }
    }

    static func loadPhonemes() -> [ChoirPhoneme] {
        guard let data = UserDefaults.standard.data(forKey: phonemesKey),
              let stored = try? JSONDecoder().decode([StoredPhoneme].self, from: data)
        else { return [] }
        return stored.map { ChoirPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC, weight: $0.weight, wordIndex: $0.wordIndex, isEnsemble: $0.isEnsemble) }
    }
}

// MARK: - Composer Model

@MainActor
class ComposerModel: ObservableObject {
    @Published var inputText: String = "" {
        didSet { ComposerPersistence.saveText(inputText) }
    }
    @Published var phonemes: [ChoirPhoneme] = [] {
        didSet { ComposerPersistence.savePhonemes(phonemes) }
    }
    /// Text that was used to generate current phonemes; nil = never extracted or cleared.
    @Published var lastExtractedText: String? = nil

    /// True when phonemes exist but text has changed since last extraction — show Sync button.
    var needsSync: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !phonemes.isEmpty else { return false }
        return lastExtractedText != trimmed
    }
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var llmStatusMessage: String? = nil

    /// Whether the Composer has any content (for icon indicator)
    var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !phonemes.isEmpty
    }

    // Undo — one level snapshot of text + phonemes
    private var undoText: String?
    private var undoPhonemes: [ChoirPhoneme]?
    @Published var canUndo: Bool = false

    func saveUndo() {
        undoText = inputText
        undoPhonemes = phonemes
        canUndo = true
    }

    @MainActor
    func undo() {
        guard let text = undoText, let ph = undoPhonemes else { return }
        inputText = text
        phonemes = ph
        undoText = nil
        undoPhonemes = nil
        canUndo = false
    }

    init() {
        inputText = ComposerPersistence.loadText()
        phonemes = ComposerPersistence.loadPhonemes()
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !phonemes.isEmpty {
            lastExtractedText = t
        }
    }

    // Scale — synced from SequencerModel by ComposerView
    var musicalKey: MusicalKey = .C
    var scaleType: ScaleType = .pentatonicMajor

    // Speed multiplier (1.0 = normal, 1.5 = slower, 2.5 = slowest)
    @Published var speedMultiplier: Double = 1.0

    // Playback
    @Published var isPlaying: Bool = false
    var minNoteDuration: Int = 280 // ms, from Setup
    @Published var currentPlayIndex: Int? = nil
    @Published var currentBounceIndex: Int = 0     // which bounce we're on (0-based)
    @Published var currentBounceCount: Int = 1     // total bounces for current chip
    @Published var currentArcDuration: Int = 330   // ms per bounce — consistent rhythm
    @Published var bouncePhase: Int = 0              // 0 = going up, 1 = coming down
    private var playbackTask: Task<Void, Never>? = nil
    private var activeMidiPitches: Set<UInt8> = []

    // MARK: - Phoneme Extraction (delegates to EnglishPhonemeExtractor)

    private let extractor = EnglishPhonemeExtractor()

    /// Check on-device LLM availability (macOS 26+ only)
    var isLLMAvailable: Bool {
        let (available, message) = extractor.checkAvailability()
        if let msg = message { llmStatusMessage = msg }
        return available
    }

    @MainActor
    func extractPhonemes() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        saveUndo()
        isProcessing = true
        errorMessage = nil

        let result = await extractor.extract(text: text)

        if let normalized = result.normalizedText {
            inputText = normalized
        }
        phonemes = result.phonemes
        if !result.phonemes.isEmpty {
            lastExtractedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        errorMessage = result.errorMessage
        isProcessing = false
    }

    // MARK: - Summon Song (LLM text generation)

    @MainActor
    func summonSong() async {
        guard !isProcessing else { return }
        saveUndo()
        isProcessing = true
        errorMessage = nil

        if #available(macOS 26, *) {
            await generateLyric()
        } else {
            errorMessage = "Requires macOS 26 (Tahoe)"
        }

        isProcessing = false
    }

    @available(macOS 26, *)
    @MainActor
    private func generateLyric() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrompt = prompt.isEmpty ? "anything beautiful" : prompt

        // Read style from menu setting (defaults to senryū)
        let styleRaw = UserDefaults.standard.string(forKey: "lyricStyle") ?? LyricStyle.senryu.rawValue
        let style = LyricStyle(rawValue: styleRaw) ?? .senryu

        let lyricInstructions: String
        switch style {
        case .senryu:
            lyricInstructions = """
            You are a weary, tired robot writing short lyrics for a recital.
            You observe human life with dry wit and quiet humor.
            DO NOT be inspirational or uplifting. DO NOT include introductions or titles.
            Output ONLY the lyric lines. Simple words. Each line 3-8 words.

            EXAMPLES:
            "coffee" → the cup knows more than I do / it has seen me before dawn
            "deadlines" → the clock does not negotiate / it simply wins
            "my cat" → your cat composes better / than most of us ever will
            "Monday" → we meet again old friend / neither of us wanted this

            DO NOT repeat the examples. Write something new and original.
            """
        case .bellman:
            lyricInstructions = """
            You write short, vivid lyrics for a singing choir. Warm, musical, vivid scenes.
            DO NOT include any introduction, title, or quotation marks. Output ONLY the lyric lines.
            Simple words that sound good sung aloud. Each line 3-8 words.

            EXAMPLES:
            "morning" → the sun is waking slowly now / golden light on sleepy hills
            "the sea" → the waves remember every ship / that ever dared to leave the shore
            "rain" → raise a glass to gutters singing / lamplight dancing on the cobblestones
            "winter" → the frost has painted every window / with a song it heard last night

            DO NOT repeat the examples. Write something new and original.
            """
        case .kulning:
            lyricInstructions = """
            You write sparse, echoing lyrics like Swedish mountain herding calls — but for robots.
            A robot calling lost machines home across mountains. Haunting and simple.
            DO NOT include introductions or titles. Output ONLY the lyric words.
            EVERY line MUST blend nature and machine. Mountain AND wire. Snow AND signal. Always both.

            EXAMPLES:
            "morning" → come home over the mountain / your signal fades
            "winter" → snow on the antenna / silence answers
            "lost" → where did you go / the frequency carries nothing
            "night" → the stars ping overhead / no machine answers the valley
            "spring" → meltwater runs through the cables / wake up wake up

            DO NOT repeat the examples. Write something new and original.
            """
        case .dada:
            lyricInstructions = """
            You write absurdist, playful nonsense lyrics for a choir of robots.
            Surreal, unexpected, delightful. Objects do strange things. Logic is optional.
            DO NOT include introductions or titles. Output ONLY the lyric words.
            Each line 3-8 words.

            EXAMPLES:
            "breakfast" → the fork decided to leave today / it took the spoon's advice
            "Tuesday" → the calendar sneezed and lost a day / nobody noticed
            "shoes" → my left shoe sings opera / the right one just listens
            "rain" → the clouds are returning your mail / postage was insufficient

            DO NOT repeat the examples. Write something new and original.
            """
        case .nursery:
            lyricInstructions = """
            You write nursery rhymes for robots.
            Simple rhyming words, sing-song rhythm, fun to say out loud.
            DO NOT include introductions or titles. Output ONLY the rhyme.
            Short lines, simple words.

            EXAMPLES:
            "rain" → rain rain come and play / not so much I rust away
            "charging" → plug me in and dim the lights / beep boop boop now say goodnight
            "morning" → the sun came up the screen turned on / I sang a song but you were gone

            DO NOT repeat the examples. Write something new and original. It should be about the secret lives of robots.
            """
        }

        let userMessage = style == .kulning
            ? "Write a short singable robot lyric about: \(userPrompt)"
            : "Write a short singable lyric about: \(userPrompt)"

        do {
            let session = LanguageModelSession(instructions: Instructions(lyricInstructions))

            let response = try await session.respond(
                to: userMessage,
                generating: LLMLyric.self
            )

            let lyric = response.content.lyric
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " / ", with: " ")
                .replacingOccurrences(of: "/", with: " ")

            if !lyric.isEmpty {
                inputText = lyric
                print("[Composer] 🎵 Summoned (\(style.rawValue)): \(lyric)")
            }
        } catch {
            print("[Composer] ✗ Summon error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Scale Pitch Mapping

    /// Returns sorted MIDI note numbers in the chosen scale, centered around middle C range
    private func scaleNotes(center: UInt8 = 60, range: Int = 12) -> [UInt8] {
        let intervals = Array(scaleType.intervals).sorted()
        var notes: [UInt8] = []
        let root = musicalKey.rawValue
        for octaveOffset in -2...2 {
            for interval in intervals {
                let midi = root + (octaveOffset * 12) + interval + 48 // start from C3 area
                if midi >= Int(center) - range && midi <= Int(center) + range && midi >= 36 && midi <= 84 {
                    notes.append(UInt8(midi))
                }
            }
        }
        return notes.sorted()
    }

    /// Pick a pitch from the scale based on phoneme index and weight
    private func pitchForPhoneme(index: Int, weight: Int, total: Int) -> UInt8 {
        let notes = scaleNotes()
        guard !notes.isEmpty else { return 60 }
        let mid = notes.count / 2
        // Stressed syllables get higher pitches, unstressed stay near center
        let offset: Int
        switch weight {
        case 3: offset = Int.random(in: 1...3)   // reach up
        case 2: offset = Int.random(in: -1...1)   // hover near center
        default: offset = Int.random(in: -2...0)   // dip low
        }
        let idx = max(0, min(notes.count - 1, mid + offset))
        return notes[idx]
    }

    /// Duration in ms based on weight, ensemble, and speed
    /// - weight 3 (primary stress): longest base (750ms)
    /// - weight 2 (secondary): medium (450ms)
    /// - weight 1 (unstressed): brief (280ms)
    /// - isEnsemble: 2x multiplier for choral notes
    /// - Logarithmic speed scaling so longer notes stretch proportionally more
    private func durationFor(weight: Int, isEnsemble: Bool = false) -> Int {
        // Base duration with more dramatic scaling for emphasis
        let base: Double
        switch weight {
        case 3: base = 750    // primary stress - long hold
        case 2: base = 450    // secondary stress - medium
        default: base = 280   // unstressed - brief
        }

        // Ensemble (chorus) notes hold 2x as long (dolls need more time)
        let ensembleMultiplier: Double = isEnsemble ? 2.0 : 1.0

        // Logarithmic speed scaling: longer notes stretch more at slower speeds
        let scaled = base * ensembleMultiplier * pow(speedMultiplier, base / 280.0)
        return max(minNoteDuration, Int(scaled))
    }

    /// Convenience wrapper for phoneme objects
    private func durationForPhoneme(_ phoneme: ChoirPhoneme) -> Int {
        durationFor(weight: phoneme.weight, isEnsemble: phoneme.isEnsemble)
    }

    /// Velocity based on weight
    private func velocityForWeight(_ weight: Int) -> UInt8 {
        switch weight {
        case 3: return 110
        case 2: return 90
        default: return 70
        }
    }

    // MARK: - Playback

    @MainActor
    func playPhonemes(audioMonitor: AudioMonitorService, midiService: MidiService?) {
        stop(midiService: midiService)
        guard !phonemes.isEmpty else { return }

        isPlaying = true
        let phonemesToPlay = phonemes
        let total = phonemesToPlay.count
        playbackTask = Task { @MainActor in
            for (index, phoneme) in phonemesToPlay.enumerated() {
                guard !Task.isCancelled else { break }

                // Bounce count: emphasized ensemble (w3) = 2 bounces, everything else = 1
                let isEmphasizedEnsemble = phoneme.isEnsemble && phoneme.weight >= 3
                let bounceCount = isEmphasizedEnsemble ? 2 : 1
                self.currentBounceCount = bounceCount

                // Duration: all ensemble chips get the 2x multiplier for a longer hold.
                // Emphasized ensemble splits that time across 2 bounces.
                let baseDuration = durationFor(weight: phoneme.weight, isEnsemble: phoneme.isEnsemble)
                let gap = Int(Double(phoneme.weight >= 3 ? 80 : 50) * speedMultiplier)

                let pitch = pitchForPhoneme(index: index, weight: phoneme.weight, total: total)
                let velocity = velocityForWeight(phoneme.weight)

                let ensemble = phoneme.isEnsemble
                print("[Composer] ▶ [\(index)] \(phoneme.text): \(phoneme.consonantName)·\(phoneme.vowelSymbol) w\(phoneme.weight) → note \(pitch) vel \(velocity) \(bounceCount) bounce(s)\(ensemble ? " 🎵ensemble" : "")")

                // Start the note
                var activePitches: [UInt8]
                if ensemble {
                    activePitches = playEnsemble(pitch: pitch, velocity: velocity, phoneme: phoneme, audioMonitor: audioMonitor, midiService: midiService)
                } else {
                    audioMonitor.playNote(
                        note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                        vowel: phoneme.vowelCC, consonant: phoneme.consonantCC
                    )
                    if let ms = midiService, ms.isConnected {
                        ms.consonant = phoneme.consonantCC
                        ms.vowel = phoneme.vowelCC
                        ms.vibrato = 64
                        ms.reverb = 32
                        ms.sendNoteOn(note: pitch, velocity: velocity)
                        activeMidiPitches.insert(pitch)
                    }
                    activePitches = [pitch]
                }

                // Multiple bounces on same chip
                // For double-bounce: first bounce is a quick in-place pop (40% of time),
                // second bounce gets the rest to travel to the next chip.
                let totalMs = baseDuration + gap
                var preSendFired = false
                for bounceIdx in 0..<bounceCount {
                    guard !Task.isCancelled else { break }

                    let bounceDuration: Int
                    if bounceCount > 1 {
                        // 50/50 split between in-place hold and travel hop
                        bounceDuration = totalMs / 2
                    } else {
                        bounceDuration = totalMs
                    }
                    let halfArc = bounceDuration / 2

                    self.currentArcDuration = bounceDuration
                    self.bouncePhase = 0  // up phase
                    self.currentBounceIndex = bounceIdx

                    if bounceIdx == 0 {
                        self.currentPlayIndex = index
                    }

                    // Sleep first half (ball going up), then publish down phase
                    try? await Task.sleep(for: .milliseconds(halfArc))
                    guard !Task.isCancelled else { break }

                    // CC Pre-Send at the peak of the first bounce — halfway through the chip.
                    // Gives BLE time to clear the NoteOn packet before sending next CCs.
                    if !preSendFired, let ms = midiService, ms.ccPreSendEnabled, ms.isConnected, index + 1 < phonemesToPlay.count {
                        let next = phonemesToPlay[index + 1]
                        ms.preSendCC(consonant: next.consonantCC, vowel: next.vowelCC, vibrato: 64, reverb: next.isEnsemble ? 48 : 32)
                        preSendFired = true
                    }

                    self.bouncePhase = 1  // down phase

                    // Sleep second half (ball coming down)
                    try? await Task.sleep(for: .milliseconds(bounceDuration - halfArc))
                }

                // Stop the note after all bounces
                stopAll(pitches: activePitches, audioMonitor: audioMonitor, midiService: midiService)
            }
            self.isPlaying = false
            self.currentPlayIndex = nil
            self.currentBounceIndex = 0
            self.currentBounceCount = 1
        }
    }

    @MainActor
    func toggleEnsemble(_ phoneme: ChoirPhoneme) {
        guard let idx = phonemes.firstIndex(where: { $0.id == phoneme.id }) else { return }
        phonemes[idx].isEnsemble.toggle()
    }

    /// Find the nearest scale note to a target MIDI pitch
    private func nearestScaleNote(to target: Int, in scale: [UInt8]) -> UInt8? {
        guard !scale.isEmpty else { return nil }
        return scale.min(by: { abs(Int($0) - target) < abs(Int($1) - target) })
    }

    /// Barbershop quartet: lead + 3 harmony voices, all snapped to scale
    /// Tenor: ~3rd above lead, Baritone: ~3rd below, Bass: ~octave below
    @MainActor
    private func playEnsemble(pitch: UInt8, velocity: UInt8, phoneme: ChoirPhoneme, audioMonitor: AudioMonitorService, midiService: MidiService?) -> [UInt8] {
        let scale = scaleNotes(center: pitch, range: 18)
        var pitches: [UInt8] = [pitch]

        // Lead voice
        audioMonitor.playNote(note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                              vowel: phoneme.vowelCC, consonant: phoneme.consonantCC)
        if let ms = midiService, ms.isConnected {
            ms.consonant = phoneme.consonantCC
            ms.vowel = phoneme.vowelCC
            ms.vibrato = 64
            ms.reverb = 32
            ms.sendNoteOn(note: pitch, velocity: velocity)
            activeMidiPitches.insert(pitch)
        }

        // Quartet intervals — wider open voicing, all snapped to scale
        let targets: [(offset: Int, velDrop: UInt8, reverb: UInt8)] = [
            (+7,  15, 38),   // Tenor — 5th above
            (-5,  18, 42),   // Baritone — 4th below
            (-12, 20, 48),   // Bass — octave below
        ]

        for t in targets {
            let raw = Int(pitch) + t.offset
            guard let snapped = nearestScaleNote(to: raw, in: scale),
                  snapped != pitch else { continue }  // skip duplicates
            let hv = max(50, velocity - t.velDrop)
            audioMonitor.playNote(note: snapped, velocity: hv, vibrato: 64, reverb: t.reverb,
                                  vowel: phoneme.vowelCC, consonant: phoneme.consonantCC)
            if let ms = midiService, ms.isConnected {
                ms.consonant = phoneme.consonantCC
                ms.vowel = phoneme.vowelCC
                ms.vibrato = 64
                ms.reverb = t.reverb
                ms.sendNoteOn(note: snapped, velocity: hv)
                activeMidiPitches.insert(snapped)
            }
            pitches.append(snapped)
        }

        print("[Composer] 🎵 quartet: \(pitches.map { String($0) }.joined(separator: " "))")
        return pitches
    }

    @MainActor
    private func stopAll(pitches: [UInt8], audioMonitor: AudioMonitorService, midiService: MidiService?) {
        for p in pitches {
            audioMonitor.stopNote(note: p)
            if let ms = midiService, ms.isConnected {
                ms.sendNoteOff(note: p)
                activeMidiPitches.remove(p)
            }
        }
    }

    @MainActor
    func deletePhoneme(_ phoneme: ChoirPhoneme) {
        saveUndo()
        phonemes.removeAll(where: { $0.id == phoneme.id })
    }

    @MainActor
    func insertPhoneme(relativeTo phoneme: ChoirPhoneme, before: Bool) {
        guard let idx = phonemes.firstIndex(where: { $0.id == phoneme.id }) else { return }
        saveUndo()
        let blank = ChoirPhoneme(
            text: "?",
            consonantCC: 0,   // Random
            vowelCC: 0,       // Random
            weight: 1,
            wordIndex: phoneme.wordIndex
        )
        let insertIdx = before ? idx : idx + 1
        phonemes.insert(blank, at: insertIdx)
    }

    @MainActor
    func updatePhoneme(id: UUID, consonantCC: UInt8? = nil, vowelCC: UInt8? = nil) {
        saveUndo()
        guard let idx = phonemes.firstIndex(where: { $0.id == id }) else { return }
        if let c = consonantCC { phonemes[idx] = ChoirPhoneme(text: phonemes[idx].text, consonantCC: c, vowelCC: phonemes[idx].vowelCC, weight: phonemes[idx].weight, wordIndex: phonemes[idx].wordIndex, isEnsemble: phonemes[idx].isEnsemble) }
        if let v = vowelCC { phonemes[idx] = ChoirPhoneme(text: phonemes[idx].text, consonantCC: phonemes[idx].consonantCC, vowelCC: v, weight: phonemes[idx].weight, wordIndex: phonemes[idx].wordIndex, isEnsemble: phonemes[idx].isEnsemble) }
    }

    @MainActor
    func clearAll() {
        saveUndo()
        inputText = ""
        phonemes = []
        lastExtractedText = nil
        errorMessage = nil
    }

    @MainActor
    func clearPhonemes() {
        saveUndo()
        phonemes = []
        lastExtractedText = nil
        errorMessage = nil
    }

    // Step index for keyboard-driven playback (loops through chips)
    private var keyboardStepIndex: Int = 0

    @MainActor
    func playNextChip(note: UInt8, audioMonitor: AudioMonitorService, midiService: MidiService?) {
        guard !phonemes.isEmpty else { return }
        let phoneme = phonemes[keyboardStepIndex % phonemes.count]
        playSinglePhoneme(phoneme, audioMonitor: audioMonitor, midiService: midiService, pitchOverride: note)
        keyboardStepIndex = (keyboardStepIndex + 1) % phonemes.count
    }

    @MainActor
    func playSinglePhoneme(_ phoneme: ChoirPhoneme, audioMonitor: AudioMonitorService, midiService: MidiService? = nil, pitchOverride: UInt8? = nil) {
        stop(midiService: midiService)
        let idx = phonemes.firstIndex(where: { $0.id == phoneme.id }) ?? 0
        currentPlayIndex = idx
        let pitch = pitchOverride ?? pitchForPhoneme(index: idx, weight: phoneme.weight, total: phonemes.count)
        let velocity = velocityForWeight(phoneme.weight)
        print("[Composer] tap: \(phoneme.text) → \(phoneme.consonantName)·\(phoneme.vowelSymbol) w\(phoneme.weight) note \(pitch)\(phoneme.isEnsemble ? " 🎵ensemble" : "")")
        var activePitches: [UInt8]
        if phoneme.isEnsemble {
            activePitches = playEnsemble(pitch: pitch, velocity: velocity, phoneme: phoneme, audioMonitor: audioMonitor, midiService: midiService)
        } else {
            audioMonitor.playNote(
                note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                vowel: phoneme.vowelCC, consonant: phoneme.consonantCC
            )
            if let ms = midiService, ms.isConnected {
                ms.consonant = phoneme.consonantCC
                ms.vowel = phoneme.vowelCC
                ms.vibrato = 64
                ms.reverb = 32
                ms.sendNoteOn(note: pitch, velocity: velocity)
                activeMidiPitches.insert(pitch)
            }
            activePitches = [pitch]
        }
        playbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            stopAll(pitches: activePitches, audioMonitor: audioMonitor, midiService: midiService)
            self.currentPlayIndex = nil
        }
    }

    @MainActor
    func stop(midiService: MidiService? = nil) {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        currentPlayIndex = nil
        if let ms = midiService, ms.isConnected, !activeMidiPitches.isEmpty {
            for p in activeMidiPitches { ms.sendNoteOff(note: p) }
            activeMidiPitches.removeAll()
        }
    }

    // MARK: - Copy to Grid

    @MainActor
    func copyToGrid(sequencer: SequencerModel) {
        guard !phonemes.isEmpty else { return }
        stop()

        let tempo = sequencer.tempo
        let msPerBeat = 60_000.0 / tempo

        // Find the end of the last existing note, snapped to next quarter beat
        let lastEnd = sequencer.notes.map { $0.startBeat + $0.duration }.max() ?? 0
        let startBeat = (lastEnd / 0.25).rounded(.up) * 0.25

        var cursor = startBeat
        let total = phonemes.count
        let allScaleNotes = scaleNotes(center: 60, range: 24)

        for (index, phoneme) in phonemes.enumerated() {
            let pitch = pitchForPhoneme(index: index, weight: phoneme.weight, total: total)
            let durationMs = Double(durationFor(weight: phoneme.weight, isEnsemble: phoneme.isEnsemble))
            let durationBeats = max(0.25, (durationMs / msPerBeat / 0.25).rounded() * 0.25)
            let velocity = velocityForWeight(phoneme.weight)

            var note = SequencerNote(
                pitch: pitch,
                startBeat: cursor,
                duration: durationBeats,
                velocity: velocity,
                consonant: phoneme.consonantCC,
                vowel: phoneme.vowelCC
            )
            note.vibrato = 64
            note.reverb = phoneme.isEnsemble ? 48 : 32

            sequencer.notes.append(note)

            // Ensemble: add harmony notes (3rd + 5th below melody within scale)
            if phoneme.isEnsemble {
                let harmonyPitches = harmonyBelow(root: pitch, scaleNotes: allScaleNotes)
                for (i, hPitch) in harmonyPitches.enumerated() {
                    var harmony = SequencerNote(
                        pitch: hPitch,
                        startBeat: cursor,
                        duration: durationBeats,
                        velocity: max(1, velocity - UInt8(10 + i * 5)),
                        consonant: phoneme.consonantCC,
                        vowel: phoneme.vowelCC
                    )
                    harmony.vibrato = 64
                    harmony.reverb = 48
                    sequencer.notes.append(harmony)
                }
            }

            cursor += durationBeats
        }

        // Extend bars if needed
        let neededBeats = Int((cursor / 4.0).rounded(.up)) * 4
        if neededBeats > sequencer.totalBeats {
            sequencer.totalBeats = min(64, neededBeats)
        }

        sequencer.hasUnsavedChanges = true
        print("[Composer] Copied \(phonemes.count) phonemes to grid at beat \(startBeat), ending at \(cursor)")
    }

    /// Returns up to 2 harmony pitches below the root, walking down the scale
    /// (scale-degree 3rd and 5th below = 2 and 4 scale steps down)
    private func harmonyBelow(root: UInt8, scaleNotes: [UInt8]) -> [UInt8] {
        guard let rootIdx = scaleNotes.firstIndex(of: root) else { return [] }
        var pitches: [UInt8] = []
        // 3rd below: 2 scale steps down
        let thirdIdx = rootIdx - 2
        if thirdIdx >= 0 { pitches.append(scaleNotes[thirdIdx]) }
        // 5th below: 4 scale steps down
        let fifthIdx = rootIdx - 4
        if fifthIdx >= 0 { pitches.append(scaleNotes[fifthIdx]) }
        return pitches
    }
}
