import SwiftUI

// Reusable slider with a default-position dot indicator
struct SliderWithDefault: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let displayText: String
    var displayWidth: CGFloat = 30
    var snap: ((Double) -> Double)? = nil
    
    var body: some View {
        HStack {
            Text(label)
                .font(Theme.toolbarFont)
                .frame(width: 80, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(Theme.ivory)
                .accentColor(Theme.ivory)
                .onChange(of: value) { val in
                    if let snap = snap { value = snap(val) }
                }
                .background(defaultDot)
            Text(displayText)
                .font(Theme.toolbarFont)
                .monospacedDigit()
                .frame(width: displayWidth)
        }
    }
    
    private var nearDefault: Bool {
        let totalRange = range.upperBound - range.lowerBound
        return abs(value - defaultValue) / totalRange < 0.03
    }
    
    private var defaultDot: some View {
        GeometryReader { geo in
            let trackInset: CGFloat = 10
            let trackWidth = geo.size.width - trackInset * 2
            let fraction = (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = trackInset + trackWidth * CGFloat(fraction)
            Circle()
                .fill(Color.white.opacity(nearDefault ? 0 : 0.35))
                .frame(width: 6, height: 6)
                .position(x: x, y: geo.size.height / 2)
                .allowsHitTesting(false)
        }
    }
}
