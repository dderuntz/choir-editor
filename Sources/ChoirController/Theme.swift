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
    
    static func outOfScale(_ scheme: ColorScheme, isBlackKey: Bool) -> Color {
        let base: Double = 0.08
        return Color.red.opacity(isBlackKey ? base * 2 : base)
    }
    
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
    
    // MARK: Pill Button Tokens
    
    static let buttonFont: Font = .caption
    static let buttonWeight: Font.Weight = .semibold
    static let buttonPaddingH: CGFloat = 14
    static let buttonPaddingV: CGFloat = 7
    static let buttonRadius: CGFloat = 14
    static let buttonStroke: CGFloat = 1.5
    
    // MARK: Dividers
    
    static let divider = dark.opacity(0.15)
    /// Alias used by explorer grid borders
    static let explorerGridBorder = divider
}
