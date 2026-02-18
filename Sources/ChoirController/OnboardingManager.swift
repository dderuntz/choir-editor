import SwiftUI
import Combine
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "onboarding")

/// Manages first-time user onboarding state.
/// Consolidates all onboarding flags and provides reset functionality.
@MainActor
class OnboardingManager: ObservableObject {

    // MARK: - Onboarding Flags

    /// User has seen the composer welcome modal
    @AppStorage("hasSeenChipsExplanation") var hasSeenChipsExplanation = false

    /// User has seen the first-play guidance (local synth vs dolls)
    @AppStorage("hasSeenFirstPlayGuide") var hasSeenFirstPlayGuide = false

    /// User has seen the Recompose button tip
    @AppStorage("hasSeenRecomposeTip") var hasSeenRecomposeTip = false

    /// User has seen the timed "Reveal Phonemes" hint
    @AppStorage("hasSeenRevealHint") var hasSeenRevealHint = false

    /// User has seen the post-reveal phoneme interaction guide
    @AppStorage("hasSeenPhonemeRevealGuide") var hasSeenPhonemeRevealGuide = false

    /// User has seen the "copy to piano roll" hint
    @AppStorage("hasSeenCopyToRollHint") var hasSeenCopyToRollHint = false

    /// User has seen the scale guide invitation after copy-to-roll
    @AppStorage("hasSeenScaleGuideInvite") var hasSeenScaleGuideInvite = false

    // -- Piano Roll Journey --

    /// User has seen the note inspector tip (first note placed)
    @AppStorage("hasSeenInspectorTip") var hasSeenInspectorTip = false

    /// User has seen the play/transport bar tip
    @AppStorage("hasSeenTransportTip") var hasSeenTransportTip = false

    /// User has seen the keyboard shortcut hint
    @AppStorage("hasSeenKeyboardHint") var hasSeenKeyboardHint = false

    /// User has seen the composer button hint (from piano roll)
    @AppStorage("hasSeenComposerHint") var hasSeenComposerHint = false

    /// User has visited the composer view at least once
    @AppStorage("hasVisitedComposer") var hasVisitedComposer = false

    /// Demo file has been copied to Documents
    @AppStorage("hasCopiedDemoFile") var hasCopiedDemoFile = false

    // MARK: - Modal State

    @Published var showChipsModal = false
    @Published var showFirstPlayModal = false
    @Published var showIntroPicker = false  // force-show the roll/composer picker

    // MARK: - Actions

    /// Reset all onboarding state so user sees tutorials again
    /// Re-shows the intro picker immediately regardless of content
    func reset() {
        log.info("Resetting onboarding state")
        hasSeenChipsExplanation = false
        hasSeenFirstPlayGuide = false
        hasSeenRecomposeTip = false
        hasSeenRevealHint = false
        hasSeenPhonemeRevealGuide = false
        hasSeenCopyToRollHint = false
        hasSeenScaleGuideInvite = false
        hasSeenInspectorTip = false
        hasSeenTransportTip = false
        hasSeenKeyboardHint = false
        hasSeenComposerHint = false
        hasVisitedComposer = false
        // Note: don't reset hasCopiedDemoFile - the file is already there
        withAnimation(.easeInOut(duration: 0.2)) {
            showIntroPicker = true
        }
    }

    /// Dismiss the intro picker (called after user makes a choice)
    func dismissIntroPicker() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showIntroPicker = false
        }
    }

    /// Nuclear reset — clears ALL app state for a true first-launch experience
    /// Dev/testing only. Quits the app after clearing.
    func nukeEverything() {
        log.info("Nuking all app state")
        // Reset onboarding
        hasSeenChipsExplanation = false
        hasSeenFirstPlayGuide = false
        hasCopiedDemoFile = false

        // Clear all UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        // Clear macOS saved application state (window restore)
        if let bundleID = Bundle.main.bundleIdentifier {
            let savedState = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Saved Application State")
                .appendingPathComponent("\(bundleID).savedState")
            if let url = savedState {
                try? FileManager.default.removeItem(at: url)
            }
        }

        log.info("All state cleared — quitting app. Relaunch for fresh experience.")
        NSApplication.shared.terminate(nil)
    }

    /// Show phonemes explanation if user hasn't seen it and composer has no phonemes
    func showChipsExplanationIfNeeded(hasPhonemes: Bool = false) {
        guard !hasSeenChipsExplanation && !hasPhonemes else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.showChipsModal = true
            }
        }
    }

    /// Dismiss chips modal and mark as seen
    func dismissChipsModal() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showChipsModal = false
        }
        hasSeenChipsExplanation = true
    }

    /// Show first-play guidance if user hasn't seen it and dolls aren't connected
    func showFirstPlayGuideIfNeeded(isDollsConnected: Bool) {
        guard !hasSeenFirstPlayGuide && !isDollsConnected else { return }
        // Don't stack on top of chips modal — wait for it
        guard !showChipsModal else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.showFirstPlayModal = true
            }
        }
    }

    /// Dismiss first-play modal and mark as seen
    func dismissFirstPlayModal() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showFirstPlayModal = false
        }
        hasSeenFirstPlayGuide = true
    }

    /// Copy demo file to Documents on first launch
    func copyDemoFileIfNeeded() {
        guard !hasCopiedDemoFile else { return }

        guard let bundleURL = Bundle.main.url(forResource: "Robots", withExtension: "choir") else {
            log.warning("Demo file not found in bundle")
            return
        }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let destURL = documentsURL?.appendingPathComponent("Robots.choir") else { return }

        // Don't overwrite if user already has a Robots.choir
        guard !FileManager.default.fileExists(atPath: destURL.path) else {
            log.info("Demo file already exists at destination")
            hasCopiedDemoFile = true
            return
        }

        do {
            try FileManager.default.copyItem(at: bundleURL, to: destURL)
            log.info("Copied demo file to Documents")
            hasCopiedDemoFile = true
        } catch {
            log.error("Failed to copy demo file: \(error)")
        }
    }
}
