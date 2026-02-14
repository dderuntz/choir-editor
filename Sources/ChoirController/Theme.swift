import SwiftUI
import AppKit

// MARK: - Semantic Theme Colors & Typography

enum Theme {
    
    // MARK: Brand Accent
    
    static let accent = Color(red: 0xCA / 255.0, green: 0xB6 / 255.0, blue: 0x1D / 255.0) // #CAB61D
    
    // MARK: Playhead & Transport
    
    static let playhead = accent
    
    // MARK: Grid
    
    static func gridLine(_ scheme: ColorScheme) -> Color {
        Color.gray.opacity(scheme == .dark ? 0.4 : 0.3)
    }
    
    static func gridSubdivision(_ scheme: ColorScheme) -> Color {
        Color.gray.opacity(scheme == .dark ? 0.25 : 0.15)
    }
    
    static func blackKeyRow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.08)
    }
    
    static func outOfScale(_ scheme: ColorScheme, isBlackKey: Bool) -> Color {
        let base: Double = scheme == .dark ? 0.10 : 0.06
        return Color.red.opacity(isBlackKey ? base * 2 : base)
    }
    
    // MARK: Notes
    
    static func noteColor(vowel: UInt8, colorScheme: ColorScheme) -> Color {
        let hue = Double(vowel) / 127.0
        let sat = colorScheme == .dark ? 0.65 : 0.6
        let brt = colorScheme == .dark ? 0.75 : 0.85
        return Color(hue: hue, saturation: sat, brightness: brt)
    }
    
    static let noteStroke = Color.white
    
    // MARK: Status Indicators
    
    static let statusConnected = accent
    static let statusWarning = Color.orange
    static let middleC = accent
    
    // MARK: Surfaces (auto-adapt via NSColor)
    
    static let surface = Color(NSColor.controlBackgroundColor)
    static let window = Color(NSColor.windowBackgroundColor)
    
    // MARK: Overlays & Shadows
    
    static func overlay(_ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.3 : 0.1)
    }
    
    static func keyboardShadow(_ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.4 : 0.12)
    }
    
    // MARK: Keyboard Keys
    
    static func whiteKey(_ scheme: ColorScheme, pressed: Bool) -> Color {
        if pressed {
            return scheme == .dark ? Color(white: 0.55) : Color.gray.opacity(0.4)
        }
        return scheme == .dark ? Color(white: 0.85) : .white
    }
    
    static func blackKey(_ scheme: ColorScheme, pressed: Bool) -> Color {
        if pressed {
            return scheme == .dark ? Color(white: 0.30) : Color(white: 0.35)
        }
        return scheme == .dark ? Color(white: 0.10) : Color(white: 0.15)
    }
    
    static func keyBorder(_ scheme: ColorScheme, isBlack: Bool) -> Color {
        if isBlack {
            return scheme == .dark ? Color(white: 0.05) : Color.black
        }
        return scheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.3)
    }
    
    // MARK: Typography
    
    static let labelSmall: Font = .caption2
    static let label: Font = .caption
    
    // MARK: Toolbar Icons
    
    static let toolbarActive = Color.white.opacity(0.85)
    static let toolbarInactive = Color.secondary
    
    // MARK: Pill Button Tokens
    
    static let buttonFont: Font = .caption
    static let buttonWeight: Font.Weight = .semibold
    static let buttonPaddingH: CGFloat = 14
    static let buttonPaddingV: CGFloat = 7
    static let buttonRadius: CGFloat = 14
    static let buttonStroke: CGFloat = 1.5
    
    // MARK: Explorer Panel
    
    static let explorerText = Color(red: 0xEA/255, green: 0xE8/255, blue: 0xE4/255)     // #EAE8E4
    static let explorerHeader = Color(red: 0x32/255, green: 0x32/255, blue: 0x32/255)   // #323232
    static let explorerField = Color(red: 0x8A/255, green: 0x8C/255, blue: 0x7F/255)    // #8A8C7F
    static let explorerConsole = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255)  // near-black
    static let explorerGridBorder = Color.black.opacity(0.15)
}
