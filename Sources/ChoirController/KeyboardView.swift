import SwiftUI

struct KeyboardView: View {
    @ObservedObject var midiService: MidiService
    @StateObject private var audioMonitor = AudioMonitorService()
    
    // Full 88-key piano range: A0 (21) to C8 (108)
    let startNote = 21
    let endNote = 108
    let middleC = 60
    
    var body: some View {
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
                    PianoKeyboardLayout(startNote: startNote, endNote: endNote, midiService: midiService, audioMonitor: audioMonitor)
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
    
    // Helper to identify black keys for the ghost track loop logic
    func isBlackKey(_ note: Int) -> Bool {
        let noteInOctave = note % 12
        return [1, 3, 6, 8, 10].contains(noteInOctave)
    }
}

struct PianoKeyboardLayout: View {
    let startNote: Int
    let endNote: Int
    @ObservedObject var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
    
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
                
                PianoKey(note: UInt8(note), isBlack: isBlack, midiService: midiService, audioMonitor: audioMonitor)
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
    @ObservedObject var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
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
                            audioMonitor.playNote(note: note)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        midiService.sendNoteOff(note: note)
                        audioMonitor.stopNote(note: note)
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
