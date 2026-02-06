import SwiftUI

struct KeyboardView: View {
    var midiService: MidiService // Not observed
    @StateObject private var audioMonitor = AudioMonitorService()
    @State private var localAudioEnabled = false  // Default OFF
    
    // Choir vocal range: E2 (40) to A5 (81)
    let startNote = 40  // E2 - Bogdan (bass) lowest
    let endNote = 81    // A5 - Leila (soprano) highest
    let middleC = 60
    
    var body: some View {
        VStack(spacing: 8) {
            // Local audio toggle
            HStack {
                Spacer()
                Toggle("Local Audio Monitor", isOn: $localAudioEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .leading) {
                        // "Ghost" track for robust scrolling
                        HStack(spacing: 0) {
                            ForEach(startNote...endNote, id: \.self) { note in
                                if !isBlackKey(note) {
                                    Color.clear
                                        .frame(width: 40, height: 1)
                                        .id(note) // ID on linear layout element
                                }
                            }
                        }
                        
                        // Actual Piano Layout
                        PianoKeyboardLayout(startNote: startNote, endNote: endNote, midiService: midiService, audioMonitor: audioMonitor, localAudioEnabled: localAudioEnabled)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                }
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .onAppear {
                    // Scroll to Middle C
                    // We scroll to note 60 (Middle C) which is a white key and exists in the Ghost HStack
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            proxy.scrollTo(middleC, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    // Helper to identify black keys for the ghost track loop logic
    func isBlackKey(_ note: Int) -> Bool {
        let noteInOctave = note % 12
        return [1, 3, 6, 8, 10].contains(noteInOctave)
    }
}

struct PianoKeyboardLayout: View {
    let startNote: Int
    let endNote: Int
    var midiService: MidiService // Not observed
    @ObservedObject var audioMonitor: AudioMonitorService
    let localAudioEnabled: Bool
    
    let whiteKeyWidth: CGFloat = 40
    let blackKeyWidth: CGFloat = 24
    let whiteKeyHeight: CGFloat = 120
    let blackKeyHeight: CGFloat = 80
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Draw all keys
            ForEach(startNote...endNote, id: \.self) { note in
                let isBlack = isBlackKey(note)
                let xPos = xPosition(for: note)
                
                PianoKey(note: UInt8(note), isBlack: isBlack, midiService: midiService, audioMonitor: audioMonitor, localAudioEnabled: localAudioEnabled)
                    .frame(width: isBlack ? blackKeyWidth : whiteKeyWidth, height: isBlack ? blackKeyHeight : whiteKeyHeight)
                    .offset(x: xPos)
                    .zIndex(isBlack ? 1 : 0) // Black keys on top
                    .id(note) // Important for ScrollViewReader
            }
        }
        .frame(width: totalWidth(), height: whiteKeyHeight, alignment: .leading)
    }
    
    func isBlackKey(_ note: Int) -> Bool {
        let noteInOctave = note % 12
        return [1, 3, 6, 8, 10].contains(noteInOctave)
    }
    
    func totalWidth() -> CGFloat {
        let whiteKeyCount = (startNote...endNote).filter { !isBlackKey($0) }.count
        return CGFloat(whiteKeyCount) * whiteKeyWidth
    }
    
    func xPosition(for note: Int) -> CGFloat {
        // Count white keys before this note
        var whiteKeyIndex = 0
        for n in startNote..<note {
            if !isBlackKey(n) {
                whiteKeyIndex += 1
            }
        }
        
        if !isBlackKey(note) {
            return CGFloat(whiteKeyIndex) * whiteKeyWidth
        } else {
            return (CGFloat(whiteKeyIndex) * whiteKeyWidth) - (blackKeyWidth / 2)
        }
    }
}

struct PianoKey: View {
    let note: UInt8
    let isBlack: Bool
    var midiService: MidiService // Don't observe, just reference to call methods
    @ObservedObject var audioMonitor: AudioMonitorService
    let localAudioEnabled: Bool
    @State private var isPressed = false
    
    var body: some View {
        Rectangle()
            .fill(keyColor)
            .border(Color.black, width: isBlack ? 0 : 1)
            .cornerRadius(isBlack ? 2 : 4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            midiService.sendNoteOn(note: note)
                            if localAudioEnabled {
                                audioMonitor.playNote(note: note)
                            }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        midiService.sendNoteOff(note: note)
                        if localAudioEnabled {
                            audioMonitor.stopNote(note: note)
                        }
                    }
            )
    }
    
    var keyColor: Color {
        if isPressed {
            return isBlack ? Color.gray : Color.gray.opacity(0.5)
        } else {
            if note == 60 { // Middle C
                return .yellow
            }
            return isBlack ? .black : .white
        }
    }
}
