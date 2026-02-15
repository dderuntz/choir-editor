import SwiftUI
import MIDIKitIO

// Compact connection status for the top-right toolbar area
struct ConnectionStatusView: View {
    @ObservedObject var midiService: MidiService
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 6) {
            if let selected = midiService.selectedInput {
                // Connected — subtle indicator
                Circle()
                    .fill(Theme.statusConnected)
                    .frame(width: 8, height: 8)
                Text(selected.displayName)
                    .font(.caption)
                    .foregroundColor(Theme.text(colorScheme).opacity(0.5))
                    .lineLimit(1)
            } else {
                // Not connected — loud call-to-action
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.dark)
                Text("Connect")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.dark)
            }
        }
        .padding(.horizontal, Theme.buttonPaddingH)
        .padding(.vertical, Theme.buttonPaddingV)
        .background(
            midiService.selectedInput != nil
                ? Theme.bg(colorScheme).opacity(0.5)
                : Theme.accent
        )
        .cornerRadius(Theme.buttonRadius)
        .contentShape(Rectangle()) // Makes entire area tappable
    }
}
