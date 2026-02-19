import SwiftUI
import MIDIKitIO

/// Localized string lookup + markdown parsing helper
private func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: localizedBundle, comment: "")
}

/// Transient instruction panel that slides in from the right to guide users through
/// Bluetooth MIDI pairing. Auto-dismisses when MidiService detects a connection.
struct BluetoothSetupPanel: View {
    @ObservedObject var midiService: MidiService
    @Binding var isPresented: Bool
    var onOpenBluetoothWindow: () -> Void
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @Environment(\.colorScheme) private var colorScheme

    @State private var showSuccess = false

    /// Scheme-aware text color
    private var txt: Color { Theme.text(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(txt)
                Text("bluetooth.title", bundle: localizedBundle)
                    .font(.headline)
                    .foregroundColor(txt)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(txt)
                }
                .buttonStyle(.plain)
            }
            .padding()

            if showSuccess {
                // Success state
                successView
            } else {
                // Instructions
                instructionsView
            }

            Spacer()

            // Live status at the bottom
            statusFooter
        }
        .background(Theme.bg(colorScheme))
        .onChange(of: midiService.isConnected) { _, connected in
            if connected {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSuccess = true
                }
                // Auto-dismiss after a brief pause
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("bluetooth.subtitle", bundle: localizedBundle)
                    .font(.subheadline)
                    .foregroundColor(txt)
                    .padding(.bottom, 4)

                stepRow(number: 1, icon: "hand.tap", key: "bluetooth.step1")

                stepRow(number: 2, icon: "antenna.radiowaves.left.and.right", key: "bluetooth.step2")

                stepRow(number: 3, icon: "rectangle.on.rectangle", key: "bluetooth.step3")

                stepRow(number: 4, icon: "lock.shield", key: "bluetooth.step4")

                // PIN display
                HStack {
                    Spacer()
                    Text("000000")
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.dark)
                        )
                    Spacer()
                }

                stepRow(number: 5, icon: "checkmark.circle", key: "bluetooth.step5")

                // Re-open button in case user closed the Apple window
                Button(action: onOpenBluetoothWindow) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("bluetooth.reopenWindow", bundle: localizedBundle)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.bg(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(txt)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.green)

            Text("bluetooth.connected", bundle: localizedBundle)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(txt)

            if let device = midiService.selectedInput {
                Text(device.displayName)
                    .font(.subheadline)
                    .foregroundColor(txt)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Status Footer

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(midiService.isConnected ? Theme.statusConnected : Theme.statusWarning)
                .frame(width: 8, height: 8)

            if midiService.isConnected, let device = midiService.selectedInput {
                Text(device.displayName)
                    .font(.caption)
                    .foregroundColor(txt)
            } else {
                Text("bluetooth.waiting", bundle: localizedBundle)
                    .font(.caption)
                    .foregroundColor(txt)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func stepRow(number: Int, icon: String, key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number circle
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Theme.bg(colorScheme))
                .frame(width: 22, height: 22)
                .background(Circle().fill(txt))

            // Step text (supports markdown bold via localized string)
            Text(try! AttributedString(markdown: L(key)))
                .font(.subheadline)
                .foregroundColor(txt)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
