import SwiftUI

/// Custom macOS traffic light buttons (close, minimize, maximize).
/// Used because we hide the native title bar entirely.
struct TrafficLightsView: View {
    @Binding var isHovering: Bool
    
    private let dotSize: CGFloat = 12
    private let spacing: CGFloat = 8
    
    var body: some View {
        HStack(spacing: spacing) {
            trafficDot(color: Color(red: 1.0, green: 0.38, blue: 0.35), symbol: "xmark") {
                NSApp.keyWindow?.close()
            }
            trafficDot(color: Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            trafficDot(color: Color(red: 0.15, green: 0.78, blue: 0.26), symbol: "plus") {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func trafficDot(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                
                if isHovering {
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
