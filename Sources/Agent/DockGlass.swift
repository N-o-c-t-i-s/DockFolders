import SwiftUI

/// Liquid Glass finished the way the Dock finishes its own glass (measured on macOS 26):
/// a thin rim that catches the light from the northwest and southeast — bright across the
/// top-left and along the top, a softer echo along the bottom-right, fading out toward the
/// northeast and southwest corners — and in Dark Mode the Dock's slightly deeper tone.
/// System glass alone renders softer and lighter.
struct DockGlass<S: Shape>: ViewModifier {
    let shape: S
    /// Deepen the glass to the Dock's own (darker) tone in Dark Mode. Off for the folder popup,
    /// which stays clear glass over whatever is behind it.
    var deepen = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            // Above the glass, below the content: deepen the glass to the Dock's tone.
            .background(
                Color.black.opacity(deepen && scheme == .dark ? 0.24 : 0)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            )
            // Reduce Transparency: solid, like the rest of macOS with that setting.
            .background(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(reduceTransparency ? 1 : 0)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            )
            .glassEffect(.regular, in: shape)
            .overlay(
                // Stroked at 2 pt and clipped to the shape: a 1 pt rim just inside the edge.
                shape
                    .stroke(rimGradient, lineWidth: 2)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            )
    }

    /// Light falling from the upper left: brightest a little above due northwest (so it runs
    /// along the top more than down the side), with a dimmer reflection opposite it.
    private var rimGradient: AngularGradient {
        let dark = scheme == .dark
        let northwest = dark ? 0.32 : 0.95
        let southeast = dark ? 0.16 : 0.6
        let base = dark ? 0.02 : 0.12
        // SwiftUI angles: 0° = east, increasing clockwise (90° = south, 180° = west, 270° = north).
        let nwCenter = 240.0, seCenter = 60.0

        func lobe(_ angle: Double, center: Double) -> Double {
            var d = abs(angle - center).truncatingRemainder(dividingBy: 360)
            if d > 180 { d = 360 - d }
            guard d < 80 else { return 0 }
            return pow(cos(d / 80 * .pi / 2), 1.6)
        }

        let stops: [Gradient.Stop] = stride(from: 0.0, through: 360.0, by: 6).map { angle in
            let value = base + (northwest - base) * lobe(angle, center: nwCenter)
                + (southeast - base) * lobe(angle, center: seCenter)
            return Gradient.Stop(color: .white.opacity(min(value, 1)), location: angle / 360)
        }
        return AngularGradient(stops: stops, center: .center, startAngle: .degrees(0), endAngle: .degrees(360))
    }
}

extension View {
    func dockGlass<S: Shape>(in shape: S, deepen: Bool = true) -> some View { modifier(DockGlass(shape: shape, deepen: deepen)) }
}
