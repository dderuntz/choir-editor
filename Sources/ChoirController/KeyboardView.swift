import SwiftUI

struct KeyboardView: View {
    var midiService: MidiService
    @StateObject private var audioMonitor = AudioMonitorService()
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    
    // Choir vocal range
    let startNote = 40  // E2
    let endNote = 81    // A5
    let middleC = 60
    
    // Minimum white key width before scrolling kicks in
    static let minWhiteKeyWidth: CGFloat = 28
    static let keyboardHeight: CGFloat = 140
    
    var whiteKeyCount: Int {
        (startNote...endNote).filter { !isBlackKey($0) }.count
    }
    
    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let naturalKeyWidth = availableWidth / CGFloat(whiteKeyCount)
            let whiteKeyWidth = max(naturalKeyWidth, Self.minWhiteKeyWidth)
            let needsScroll = naturalKeyWidth < Self.minWhiteKeyWidth
            
            Group {
                if needsScroll {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            keyboardContent(whiteKeyWidth: whiteKeyWidth, height: geo.size.height)
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation { proxy.scrollTo(middleC, anchor: .center) }
                            }
                        }
                    }
                } else {
                    keyboardContent(whiteKeyWidth: whiteKeyWidth, height: geo.size.height)
                }
            }
            .onChange(of: localAudioEnabled) { enabled in
                if enabled {
                    audioMonitor.ensureStarted()
                } else {
                    audioMonitor.tearDown()
                }
            }
        }
    }
    
    private func keyboardContent(whiteKeyWidth: CGFloat, height: CGFloat) -> some View {
        let blackKeyWidth = whiteKeyWidth * 0.6
        let whiteKeyHeight = max(height, 80)
        let blackKeyHeight = whiteKeyHeight * 0.6
        let totalWidth = CGFloat(whiteKeyCount) * whiteKeyWidth
        
        return ZStack(alignment: .topLeading) {
            ForEach(startNote...endNote, id: \.self) { note in
                let isBlack = isBlackKey(note)
                let xPos = xPosition(for: note, whiteKeyWidth: whiteKeyWidth, blackKeyWidth: blackKeyWidth)
                
                PianoKey(
                    note: UInt8(note),
                    isBlack: isBlack,
                    midiService: midiService,
                    audioMonitor: audioMonitor,
                    localAudioEnabled: localAudioEnabled
                )
                .frame(
                    width: isBlack ? blackKeyWidth : whiteKeyWidth,
                    height: isBlack ? blackKeyHeight : whiteKeyHeight
                )
                .offset(x: xPos)
                .zIndex(isBlack ? 1 : 0)
                .id(note)
            }
        }
        .frame(width: totalWidth, height: whiteKeyHeight, alignment: .leading)
    }
    
    func isBlackKey(_ note: Int) -> Bool {
        let pc = note % 12
        return [1, 3, 6, 8, 10].contains(pc)
    }
    
    func xPosition(for note: Int, whiteKeyWidth: CGFloat, blackKeyWidth: CGFloat) -> CGFloat {
        var whiteKeyIndex = 0
        for n in startNote..<note {
            if !isBlackKey(n) {
                whiteKeyIndex += 1
            }
        }
        if !isBlackKey(note) {
            return CGFloat(whiteKeyIndex) * whiteKeyWidth
        } else {
            return CGFloat(whiteKeyIndex) * whiteKeyWidth - blackKeyWidth / 2
        }
    }
}

// MARK: - Piano Key

struct PianoKey: View {
    let note: UInt8
    let isBlack: Bool
    var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
    let localAudioEnabled: Bool
    @State private var isPressed = false
    
    var body: some View {
        Rectangle()
            .fill(keyColor)
            .overlay(
                // Stroke only sides and bottom, not the top edge
                GeometryReader { geo in
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: h))
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.addLine(to: CGPoint(x: w, y: 0))
                    }
                    .stroke(keyBorderColor, lineWidth: 1)
                }
            )
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
            return isBlack ? Color(white: 0.35) : Color.gray.opacity(0.4)
        }
        if note == 60 { return .yellow }
        return isBlack ? Color(white: 0.15) : .white
    }
    
    var keyBorderColor: Color {
        Color.gray.opacity(0.3)
    }
}
