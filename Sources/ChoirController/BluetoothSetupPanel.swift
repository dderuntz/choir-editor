import SwiftUI
import MIDIKitIO

/// Transient instruction panel that slides in from the right to guide users through
/// Bluetooth MIDI pairing. Auto-dismisses when MidiService detects a connection.
struct BluetoothSetupPanel: View {
    @ObservedObject var midiService: MidiService
    @Binding var isPresented: Bool
    var onOpenBluetoothWindow: () -> Void
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
                Text("Connect Your Choir")
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
                Text("Follow these steps to pair your Choir doll via Bluetooth.")
                    .font(.subheadline)
                    .foregroundColor(txt)
                    .padding(.bottom, 4)
                
                stepRow(number: 1, icon: "hand.tap", text: "**Wake your dolls** — give each one a tap")
                
                stepRow(number: 2, icon: "antenna.radiowaves.left.and.right", text: "**Choose your lead doll** — long-press its connect button until it sings *\"Searching for controller\"*")
                
                stepRow(number: 3, icon: "rectangle.on.rectangle", text: "In the Bluetooth window, click **\"Advertise\"**. The doll should sing *\"Connected to MIDI controller\"*")
                
                stepRow(number: 4, icon: "lock.shield", text: "When macOS asks for a PIN, enter:")
                
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
                
                stepRow(number: 5, icon: "checkmark.circle", text: "Wait for connection — this panel will close automatically")
                
                // Re-open button in case user closed the Apple window
                Button(action: onOpenBluetoothWindow) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reopen Bluetooth Window")
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
            
            Text("Connected!")
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
                Text("Waiting for connection...")
                    .font(.caption)
                    .foregroundColor(txt)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private func stepRow(number: Int, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number circle
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Theme.bg(colorScheme))
                .frame(width: 22, height: 22)
                .background(Circle().fill(txt))
            
            // Step text (supports markdown bold via Text(AttributedString))
            Text(try! AttributedString(markdown: text))
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
