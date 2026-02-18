import SwiftUI

/// Welcome modal shown on first composer open — explains the writing flow
struct ChipsExplanationModal: View {
    @EnvironmentObject var onboarding: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.overlay(colorScheme)
                .onTapGesture { onboarding.dismissChipsModal() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "eyebrow")
                            .font(.system(size: 14, weight: .semibold))
                        Text("onboarding.welcome.title", bundle: localizedBundle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Theme.text(colorScheme))
                    Text("onboarding.welcome.body", bundle: localizedBundle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                Button {
                    onboarding.dismissChipsModal()
                } label: {
                    Text("onboarding.welcome.dismiss", bundle: localizedBundle)
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
            .frame(width: 340)
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
                    Text("onboarding.firstPlay.title", bundle: localizedBundle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text(colorScheme))
                    Text("onboarding.firstPlay.body", bundle: localizedBundle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                    Text("onboarding.firstPlay.subtitle", bundle: localizedBundle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                HStack(spacing: 12) {
                    Button {
                        onboarding.dismissFirstPlayModal()
                    } label: {
                        Text("onboarding.firstPlay.keepPlaying", bundle: localizedBundle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.ivory)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.green, in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        onboarding.dismissFirstPlayModal()
                        onConnectDolls()
                    } label: {
                        Text("onboarding.firstPlay.connect", bundle: localizedBundle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.ivory)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.dark, in: RoundedRectangle(cornerRadius: 8))
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
                    Text("onboarding.empty.title", bundle: localizedBundle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text(colorScheme))
                        .frame(maxWidth: .infinity)
                    Text("onboarding.empty.composerDesc", bundle: localizedBundle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text("onboarding.empty.rollDesc", bundle: localizedBundle)
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
                            Text("onboarding.empty.rollBtn", bundle: localizedBundle)
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
                        Label {
                            Text("onboarding.empty.composerBtn", bundle: localizedBundle)
                        } icon: {
                            Image(systemName: "eyebrow")
                        }
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

/// Modal shown after user picks "Start with melody" — choose blank roll or load demo
struct PianoRollEntryModal: View {
    @Environment(\.colorScheme) private var colorScheme
    var onStartAdding: () -> Void
    var onLoadDemo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.overlay(colorScheme)
                .onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image("GridIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Theme.text(colorScheme))
                        Text("onboarding.rollEntry.title", bundle: localizedBundle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Theme.text(colorScheme))
                    Text("onboarding.rollEntry.body", bundle: localizedBundle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                HStack(spacing: 12) {
                    Button {
                        onStartAdding()
                    } label: {
                        Text("onboarding.rollEntry.startAdding", bundle: localizedBundle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.text(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.fieldColor(colorScheme), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        onLoadDemo()
                    } label: {
                        Text("onboarding.rollEntry.loadDemo", bundle: localizedBundle)
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
