import SwiftUI

struct KeyboardView: View {
    var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
    @EnvironmentObject var model: SequencerModel
    @EnvironmentObject var composerModel: ComposerModel
    var isComposerActive: Bool = false
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    
    // Choir vocal range (from PitchConstants)
    let startNote = Int(PitchConstants.minPitch)
    let endNote = Int(PitchConstants.maxPitch)
    let middleC = 60
    
    // Minimum white key width before scrolling kicks in
    static let minWhiteKeyWidth: CGFloat = 28
    static let keyboardHeight: CGFloat = 150
    
    var whiteKeyCount: Int {
        (startNote...endNote).filter { !isBlackKey($0) }.count
    }

    /// Whether any scale guide is active (sequencer's toggle or composer mode)
    private var scaleActive: Bool {
        isComposerActive || model.showScaleHelper
    }

    /// Check if a pitch is in the active scale (shared between sequencer and composer)
    private func noteInScale(_ pitch: UInt8) -> Bool {
        model.isInScale(pitch)
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
            // Audio setup/teardown handled by ContentView
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
                    model: model,
                    audioMonitor: audioMonitor,
                    localAudioEnabled: localAudioEnabled,
                    outOfScale: scaleActive && !noteInScale(UInt8(note)),
                    onComposerPress: isComposerActive && !composerModel.phonemes.isEmpty
                        ? { composerModel.playNextChip(note: UInt8(note), audioMonitor: audioMonitor) }
                        : nil
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
        PitchConstants.isBlackKey(UInt8(note))
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
    @ObservedObject var model: SequencerModel
    @ObservedObject var audioMonitor: AudioMonitorService
    let localAudioEnabled: Bool
    var outOfScale: Bool = false
    var onComposerPress: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Group {
            if isBlack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 2,
                    bottomTrailingRadius: 2,
                    topTrailingRadius: 0
                )
                .fill(keyColor)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 2,
                        bottomTrailingRadius: 2,
                        topTrailingRadius: 0
                    )
                    .stroke(keyBorderColor, lineWidth: 1)
                )
            } else {
                Rectangle()
                    .fill(keyColor)
                    .overlay(
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
            }
        }
            .overlay {
                if outOfScale {
                    HatchShape(spacing: 6)
                        .stroke(
                            isBlack
                                ? Color.white.opacity(0.15)
                                : Theme.dark.opacity(0.12),
                            lineWidth: 1.0
                        )
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if note == 60 {
                    Text("C")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.dark.opacity(0.4))
                        .padding(.bottom, 6)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            if let composerPress = onComposerPress {
                                composerPress()
                            } else {
                                model.highlightedPitch = note
                                midiService.sendNoteOn(note: note)
                                if localAudioEnabled {
                                    audioMonitor.playNote(note: note)
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        if onComposerPress == nil {
                            model.highlightedPitch = nil
                            midiService.sendNoteOff(note: note)
                            if localAudioEnabled {
                                audioMonitor.stopNote(note: note)
                            }
                        }
                    }
            )
    }
    
    var keyColor: Color {
        if isBlack {
            return Theme.blackKey(pressed: isPressed)
        }
        return Theme.whiteKey(pressed: isPressed)
    }
    
    var keyBorderColor: Color {
        Theme.keyBorder(isBlack: isBlack)
    }
}
