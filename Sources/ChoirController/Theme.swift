import SwiftUI
import AppKit

// MARK: - Semantic Theme Colors & Typography

enum Theme {
    
    // MARK: Core Palette
    
    static let accent = Color(red: 0xCA / 255.0, green: 0xB6 / 255.0, blue: 0x1D / 255.0) // #CAB61D
    static let ivory = Color(red: 0xEA/255, green: 0xE8/255, blue: 0xE4/255)   // #EAE8E4
    static let dark = Color(red: 0x32/255, green: 0x32/255, blue: 0x32/255)     // #323232
    static let field = Color(red: 0x8A/255, green: 0x8C/255, blue: 0x7F/255)    // #8A8C7F
    static let fieldLight = Color(red: 0xCC/255, green: 0xCD/255, blue: 0xC2/255) // #CCCDC2 — light mode grid/grey
    static let console = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255)  // near-black
    static let green = Color(red: 0x00/255, green: 0x87/255, blue: 0x38/255)    // #008738
    
    // MARK: Scheme-Aware Helpers
    
    /// Grid / sidebar field color: dark → field, light → fieldLight
    static func fieldColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? field : fieldLight
    }
    /// Primary text color: dark → ivory, light → dark
    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? ivory : dark
    }
    /// Background color: dark → dark, light → ivory
    static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : ivory
    }
    
    // MARK: Grid
    
    static let gridLine = Color.black.opacity(0.15)
    static let gridBar = Color.black.opacity(0.35)       // bar boundaries & piano key column
    static let gridSubdivision = Color.black.opacity(0.08)
    /// Opaque structural divider — piano key column, transport internal
    static let structuralDivider = Color(red: 0x72/255.0, green: 0x73/255.0, blue: 0x69/255.0) // #727369
    
    static let blackKeyRow = Color.black.opacity(0.06)
    
    // MARK: Notes
    
    /// Note color based on pitch: ivory for white keys, dark for black keys
    static func noteColor(pitch: UInt8) -> Color {
        PitchConstants.isBlackKey(pitch) ? dark : ivory
    }
    
    /// Label color (inverted for contrast against note)
    static func noteLabelColor(pitch: UInt8) -> Color {
        PitchConstants.isBlackKey(pitch) ? ivory : dark
    }
    
    // MARK: Status Indicators
    
    static let statusConnected = green
    static let statusWarning = Color.orange
    static let middleC = accent
    
    // MARK: Overlays & Shadows
    
    static func overlay(_ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.3 : 0.1)
    }
    
    // MARK: Keyboard Keys
    
    static func whiteKey(pressed: Bool) -> Color {
        pressed ? ivory.opacity(0.6) : ivory
    }
    
    static func blackKey(pressed: Bool) -> Color {
        pressed ? dark.opacity(0.6) : dark
    }
    
    static func keyBorder(isBlack: Bool) -> Color {
        dark.opacity(isBlack ? 0.3 : 0.15)
    }
    
    // MARK: Typography
    
    static let labelSmall: Font = .caption2
    static let toolbarFont: Font = .system(size: 12)
    static let toolbarIconSize: CGFloat = 20
    
    // MARK: Pill Button Tokens
    
    static let buttonFont: Font = .caption
    static let buttonWeight: Font.Weight = .semibold
    static let buttonPaddingH: CGFloat = 14
    static let buttonPaddingV: CGFloat = 7
    static let buttonRadius: CGFloat = 14
    static let buttonStroke: CGFloat = 1.5
    
    // MARK: Dividers
    
    static let divider = dark.opacity(0.15)
    /// Alias used by explorer grid borders — scheme-aware
    static func explorerGridBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? field : fieldLight
    }
}

// MARK: - Hover Pill Button Style

struct HoverPillStyle: ButtonStyle {
    var colorScheme: ColorScheme
    var textColor: Color = Theme.field
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isHovered ? Theme.text(colorScheme) : textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Theme.fieldColor(colorScheme) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - Circular Slider (NSSlider wrapper)

/// Circular NSSlider with rotated mapping: 0 at ~8 o'clock, 1 at ~4 o'clock,
/// dead zone (~62 ticks) at the bottom (~6 o'clock). Accepts a normalized 0...1 binding.
/// NSSlider circular has ~190 ticks of travel. 128 map to the usable arc,
/// the remaining ~62 are the dead zone which snaps to the nearest end.
struct CircularSlider: NSViewRepresentable {
    @Binding var normalized: Double  // 0...1

    private static let ticks: Double = 190
    private static let usable: Double = 128   // 0-127
    private static let half: Double = 95      // ticks/2 — flips dead zone to bottom
    private static let offset: Double = 31    // nudges 0 from 6 o'clock to 8 o'clock

    /// Convert a logical 0...1 value to the slider's 0...190 position.
    static func toSlider(_ value: Double) -> Double {
        let tick = value * (usable - 1)
        let pos = (tick + half + offset).truncatingRemainder(dividingBy: ticks)
        return pos
    }

    /// Convert the slider's 0...190 position back to logical 0...1.
    static func fromSlider(_ slider: Double) -> Double {
        let raw = slider - half - offset
        let wrapped = ((raw.truncatingRemainder(dividingBy: ticks)) + ticks)
            .truncatingRemainder(dividingBy: ticks)
        return wrapped / (usable - 1)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.sliderType = .circular
        slider.minValue = 0
        slider.maxValue = Self.ticks
        slider.doubleValue = Self.toSlider(normalized)
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.controlSize = .small
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.doubleValue = Self.toSlider(normalized)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: CircularSlider
        init(_ parent: CircularSlider) { self.parent = parent }
        @objc func valueChanged(_ sender: NSSlider) {
            let logical = CircularSlider.fromSlider(sender.doubleValue)
            if logical >= 0 && logical <= 1 {
                parent.normalized = logical
            } else {
                // Dead zone: 6 o'clock is the midpoint — snap to nearest end
                let midpoint = CircularSlider.fromSlider(CircularSlider.half)
                let clamped = logical > midpoint ? 0.0 : 1.0
                parent.normalized = clamped
                sender.doubleValue = CircularSlider.toSlider(clamped)
            }
        }
    }
}

// MARK: - Ivory Switch Toggle Style

struct IvorySwitchStyle: ToggleStyle {
    var onColor: Color = Theme.fieldLight
    var offColor: Color = Theme.dark.opacity(0.10)
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? onColor : offColor)
                    .frame(width: 42, height: 25)
                
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                    .frame(width: 21, height: 21)
                    .offset(x: configuration.isOn ? 9 : -9)
            }
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
