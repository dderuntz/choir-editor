import SwiftUI

/// Modal explaining what chips (phonemes) are
struct ChipsExplanationModal: View {
    @EnvironmentObject var onboarding: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.overlay(colorScheme)
                .onTapGesture { onboarding.dismissChipsModal() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("About Chips")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text(colorScheme))
                    Text("The choir sings using phonemes — we call them chips. Each chip pairs a consonant with a vowel to make a sound.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                    Text("Click any chip to hear it and tweak its sound.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                Button {
                    onboarding.dismissChipsModal()
                } label: {
                    Text("Got it")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

/// Modal shown on first play when dolls aren't connected
struct FirstPlayGuideModal: View {
    @EnvironmentObject var onboarding: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme
    var onConnectDolls: () -> Void

    var body: some View {
        ZStack {
            Theme.overlay(colorScheme)
                .onTapGesture { onboarding.dismissFirstPlayModal() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("You're hearing the local synth")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text(colorScheme))
                    Text("Connect your Choir dolls via Bluetooth to play on hardware.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                    Text("Local sound turns off automatically when dolls connect. Change this in Preferences → Audio.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                HStack(spacing: 12) {
                    Button {
                        onboarding.dismissFirstPlayModal()
                    } label: {
                        Text("Keep playing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.text(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.fieldColor(colorScheme), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        onboarding.dismissFirstPlayModal()
                        onConnectDolls()
                    } label: {
                        Text("Connect dolls")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.dark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

/// Modal shown when document is empty to help users get started
struct EmptyStateHelperModal: View {
    @Environment(\.colorScheme) private var colorScheme
    var onStartWithMelody: () -> Void
    var onStartWithIdeas: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.overlay(colorScheme)
                .onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("Where to start?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text(colorScheme))
                        .frame(maxWidth: .infinity)
                    Text("Open the composer to craft a lyric for the choir and quickly test it out.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text("Challenge — Start manually arranging phonemes and notes on a piano roll and hit play!")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
                HStack(spacing: 12) {
                    Button {
                        onStartWithMelody()
                    } label: {
                        Label {
                            Text("Start with melody")
                        } icon: {
                            Image("GridIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .foregroundStyle(Theme.text(colorScheme))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.fieldColor(colorScheme), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        onStartWithIdeas()
                    } label: {
                        Label("Start with ideas", systemImage: "eyebrow")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.dark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
