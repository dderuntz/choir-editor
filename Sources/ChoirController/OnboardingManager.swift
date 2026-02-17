import SwiftUI
import Combine
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "onboarding")

/// Manages first-time user onboarding state.
/// Consolidates all onboarding flags and provides reset functionality.
@MainActor
class OnboardingManager: ObservableObject {

    // MARK: - Onboarding Flags

    /// User has seen the "chips" (phonemes) explanation in Composer
    @AppStorage("hasSeenChipsExplanation") var hasSeenChipsExplanation = false

    /// User has seen the first-play guidance (local synth vs dolls)
    @AppStorage("hasSeenFirstPlayGuide") var hasSeenFirstPlayGuide = false

    /// Demo file has been copied to Documents
    @AppStorage("hasCopiedDemoFile") var hasCopiedDemoFile = false

    // MARK: - Modal State

    @Published var showChipsModal = false
    @Published var showFirstPlayModal = false

    // MARK: - Actions

    /// Reset all onboarding state so user sees tutorials again
    func reset() {
        log.info("Resetting onboarding state")
        hasSeenChipsExplanation = false
        hasSeenFirstPlayGuide = false
        // Note: don't reset hasCopiedDemoFile - the file is already there
    }

    /// Show chips explanation if user hasn't seen it
    func showChipsExplanationIfNeeded() {
        guard !hasSeenChipsExplanation else { return }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            showFirstPlayModal = true
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
