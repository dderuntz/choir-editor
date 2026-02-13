import SwiftUI

/// Transient instruction panel that slides in from the right to guide users through
/// Bluetooth MIDI pairing. Auto-dismisses when MidiService detects a connection.
struct BluetoothSetupPanel: View {
    @ObservedObject var midiService: MidiService
    @Binding var isPresented: Bool
    var onOpenBluetoothWindow: () -> Void
    
    @State private var showSuccess = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(Theme.accent)
                Text("Connect Your Choir")
                    .font(.headline)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Theme.surface)
            
            Divider()
            
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
        .onChange(of: midiService.isConnected) { connected in
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
                Text("Follow these steps to pair your Choir doll via Bluetooth.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                stepRow(number: 1, icon: "power", text: "Turn on your Choir doll")
                
                stepRow(number: 2, icon: "rectangle.on.rectangle", text: "In the Bluetooth window that opened, click **\"Advertise\"**")
                
                stepRow(number: 3, icon: "lock.shield", text: "When macOS asks for a PIN, enter:")
                
                // PIN display
                HStack {
                    Spacer()
                    Text("000000")
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.accent.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                                )
                        )
                    Spacer()
                }
                
                stepRow(number: 4, icon: "checkmark.circle", text: "Wait for connection — this panel will close automatically")
                
                Divider()
                    .padding(.vertical, 4)
                
                // Re-open button in case user closed the Apple window
                Button(action: onOpenBluetoothWindow) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reopen Bluetooth Window")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
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
                .foregroundColor(Theme.accent)
            
            Text("Connected!")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let device = midiService.selectedInput {
                Text(device.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Status Footer
    
    private var statusFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(midiService.isConnected ? Theme.statusConnected : Theme.statusWarning)
                    .frame(width: 8, height: 8)
                
                if midiService.isConnected, let device = midiService.selectedInput {
                    Text(device.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Waiting for connection...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Theme.surface)
        }
    }
    
    // MARK: - Helpers
    
    private func stepRow(number: Int, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number circle
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary))
            
            // Step text (supports markdown bold via Text(AttributedString))
            Text(try! AttributedString(markdown: text))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
