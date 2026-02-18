import SwiftUI
import MIDIKitIO

// Compact connection status label for the top-right toolbar area
struct ConnectionStatusView: View {
    @ObservedObject var midiService: MidiService
    var colorScheme: ColorScheme = .light

    var body: some View {
        if let selected = midiService.selectedInput {
            Label(selected.displayName, systemImage: "checkmark.circle.fill")
                .foregroundColor(Theme.text(colorScheme).opacity(0.6))
                .lineLimit(1)
                .frame(height: 16)
        } else {
            Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundColor(Theme.bg(colorScheme))
                .frame(height: 16)
        }
    }
}
