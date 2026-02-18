import SwiftUI

// MARK: - Phoneme Chip

enum WordPosition {
    case only      // single-chip word → fully rounded
    case first     // left rounded, right sharp
    case middle    // both sides sharp
    case last      // left sharp, right rounded
}

struct PhonemeChip: View {
    let phoneme: ChoirPhoneme
    let isActive: Bool
    var wordPosition: WordPosition = .only
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var bump: CGFloat = 0
    @State private var flashGreen = false

    private var isRandomCons: Bool { phoneme.consonantCC == 0 }
    private var isRandomVowel: Bool { phoneme.vowelCC == 0 }

    private var phonemeLabel: String {
        let c = Consonant.all.first { $0.ccValue == phoneme.consonantCC }
        let v = Vowel.all.first { $0.ccValue == phoneme.vowelCC }
        let isNone = (c?.name == "None")
        let cPart = (isNone || isRandomCons) ? "" : (c?.name ?? "")
        let vPart = isRandomVowel ? "" : (v?.symbol ?? "")
        return cPart + vPart
    }

    var body: some View {
        VStack(spacing: 2) {
            if isRandomCons && isRandomVowel {
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text(colorScheme))
            } else {
                Text(phoneme.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.text(colorScheme))
            }

            if !phonemeLabel.isEmpty || isRandomCons || isRandomVowel || phoneme.isEnsemble {
                HStack(spacing: 3) {
                    if isRandomCons && !isRandomVowel {
                        Image(systemName: "shuffle")
                            .font(.system(size: 8))
                    }
                    if !phonemeLabel.isEmpty {
                        Text(phonemeLabel)
                            .font(.system(size: 10))
                    }
                    if isRandomVowel && !isRandomCons {
                        Image(systemName: "shuffle")
                            .font(.system(size: 8))
                    }
                    if phoneme.isEnsemble {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 7))
                    }
                }
                .foregroundColor(Theme.text(colorScheme).opacity(0.4))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: wordPosition == .middle || wordPosition == .last ? 6 : 14,
                bottomLeadingRadius: wordPosition == .middle || wordPosition == .last ? 6 : 14,
                bottomTrailingRadius: wordPosition == .middle || wordPosition == .first ? 6 : 14,
                topTrailingRadius: wordPosition == .middle || wordPosition == .first ? 6 : 14
            )
            .fill(flashGreen ? Theme.green : Theme.fieldColor(colorScheme))
            .animation(.easeOut(duration: 0.3), value: flashGreen)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.dark)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Theme.ivory))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .offset(y: bump)
        .onChange(of: isActive) { _, active in
            if active {
                bump = 3
                flashGreen = true
                withAnimation(.interpolatingSpring(stiffness: 1500, damping: 20)) {
                    bump = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    flashGreen = false
                }
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: phoneme.isEnsemble)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Phoneme Inspector Popover

struct PhonemeInspector: View {
    let phoneme: ChoirPhoneme
    var onUpdate: (UInt8?, UInt8?) -> Void
    var onToggleEnsemble: () -> Void

    @State private var consonant: UInt8
    @State private var vowel: UInt8

    init(phoneme: ChoirPhoneme, onUpdate: @escaping (UInt8?, UInt8?) -> Void, onToggleEnsemble: @escaping () -> Void) {
        self.phoneme = phoneme
        self.onUpdate = onUpdate
        self.onToggleEnsemble = onToggleEnsemble
        _consonant = State(initialValue: phoneme.consonantCC)
        _vowel = State(initialValue: phoneme.vowelCC)
    }

    private var comboLabel: String {
        let c = Consonant.all.first { $0.ccValue == consonant }
        let v = Vowel.all.first { $0.ccValue == vowel }
        let isNone = (c?.name == "None")
        let isRandomCons = consonant == 0
        let isRandomVowel = vowel == 0
        let cPart = (isNone || isRandomCons) ? "" : (c?.name ?? "")
        let vPart = isRandomVowel ? "" : (v?.symbol ?? "")
        let label = cPart + vPart
        return label.isEmpty ? "Random" : label
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            // Title + combo sound (like the chips)
            VStack(spacing: 2) {
                Text(phoneme.text)
                    .font(.system(size: 13, weight: .bold))
                Text(comboLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Text("Consonant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $consonant) {
                    ForEach(Consonant.all) { c in
                        Text(c.name).tag(c.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                .controlSize(.small)
                .onChange(of: consonant) { _, val in onUpdate(val, nil) }
            }

            HStack {
                Text("Vowel")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $vowel) {
                    ForEach(Vowel.all) { v in
                        Text(v.ccValue == 0 ? "Random" : "\(v.symbol) \(v.example)").tag(v.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                .controlSize(.small)
                .onChange(of: vowel) { _, val in onUpdate(nil, val) }
            }

            HStack {
                Text("Harmony")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "person.3.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Toggle("", isOn: Binding(
                    get: { phoneme.isEnsemble },
                    set: { _ in onToggleEnsemble() }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
        }
        .frame(width: 160)
        .padding(12)
    }
}
