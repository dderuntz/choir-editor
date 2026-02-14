import SwiftUI
import MIDIKitIO

// Compact connection status for the top-right toolbar area
struct ConnectionStatusView: View {
    @ObservedObject var midiService: MidiService
    
    var body: some View {
        HStack(spacing: 6) {
            if let selected = midiService.selectedInput {
                // Connected — subtle indicator
                Circle()
                    .fill(Theme.statusConnected)
                    .frame(width: 8, height: 8)
                Text(selected.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                // Not connected — loud call-to-action
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text("Connect")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
            }
        }
        .padding(.horizontal, Theme.buttonPaddingH)
        .padding(.vertical, Theme.buttonPaddingV)
        .background(
            midiService.selectedInput != nil
                ? Theme.surface.opacity(0.5)
                : Theme.accent
        )
        .cornerRadius(Theme.buttonRadius)
        .contentShape(Rectangle()) // Makes entire area tappable
    }
}
