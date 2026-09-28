import SwiftUI

// Sermo family palette (light) — exact hexes from Sermo's Theme-20260925
// acceptance script (every pair contrast-verified ≥ 4.5):
//   white pages · blue-grey surfaces #D6E0F0 · cobalt headers/links #3D4BEE
//   lime primary actions #C8FF35 on navy text #09111F · secondary text #4C5F78
enum Theme {
    static let bg = Color.white                              // page
    static let surface = Color(red: 214/255, green: 224/255, blue: 240/255)   // #D6E0F0 blue-grey panel
    static let surfaceLight = Color(red: 234/255, green: 245/255, blue: 255/255) // #EAF5FF light accent
    static let card = Color(red: 214/255, green: 224/255, blue: 240/255)      // #D6E0F0 card
    static let composer = Color.white                        // inputs
    static let stroke = Color(red: 199/255, green: 211/255, blue: 230/255)    // #C7D3E6 hairlines
    static let textPrimary = Color(red: 9/255, green: 17/255, blue: 31/255)   // #09111F navy ink
    static let textSecondary = Color(red: 76/255, green: 95/255, blue: 120/255) // #4C5F78 (4.95:1 on #D6E0F0)
    static let blue = Color(red: 61/255, green: 75/255, blue: 238/255)        // #3D4BEE headers/links
    static let lime = Color(red: 200/255, green: 255/255, blue: 53/255)       // #C8FF35 actions (navy text, 16:1)
    static let green = Color(red: 0.290, green: 0.850, blue: 0.550)
    static let red = Color(red: 0.960, green: 0.380, blue: 0.380)
    static let amber = Color(red: 1.000, green: 0.700, blue: 0.300)

    // Home bloom, re-tuned for the light scheme: paper glow, cobalt whisper, lime at the edge
    static let bloomBlue = Color(red: 61/255, green: 75/255, blue: 238/255)   // #3D4BEE
    static let bloomIndigo = Color(red: 214/255, green: 224/255, blue: 240/255) // #D6E0F0
    static let bloomPink = Color(red: 234/255, green: 245/255, blue: 255/255)   // #EAF5FF
    static let bloomOrange = Color(red: 200/255, green: 255/255, blue: 53/255)  // #C8FF35 lime edge

    static let heartGradient = LinearGradient(
        colors: [bloomOrange, bloomPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The Lovable home-screen glow: black up top melting into a blue bloom,
/// then pink, then orange at the very bottom edge.
struct LovableBloom: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Theme.bg

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Theme.bloomBlue.opacity(0.10), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: w * 0.85
                        )
                    )
                    .frame(width: w * 1.8, height: h * 0.56)
                    .position(x: w / 2, y: h * 0.76)
                    .blur(radius: 56)

                Ellipse()
                    .fill(Theme.bloomIndigo.opacity(0.55))
                    .frame(width: w * 1.3, height: h * 0.36)
                    .position(x: w * 0.32, y: h * 0.84)
                    .blur(radius: 70)

                Ellipse()
                    .fill(Theme.bloomPink.opacity(0.70))
                    .frame(width: w * 2.0, height: h * 0.42)
                    .position(x: w / 2, y: h * 0.96)
                    .blur(radius: 60)

                Ellipse()
                    .fill(Theme.bloomOrange.opacity(0.30))
                    .frame(width: w * 2.2, height: h * 0.34)
                    .position(x: w / 2, y: h * 1.16)
                    .blur(radius: 55)
            }
        }
        .ignoresSafeArea()
        #if !os(macOS)
        .ignoresSafeArea(.keyboard)
        #endif
    }
}

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.surface, in: Circle())
        }
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.16), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: phase * geo.size.width * 1.7)
                }
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

enum Haptics {
    static func success() {
        #if !os(macOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func error() {
        #if !os(macOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
    static func tap() {
        #if !os(macOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/// Springy press feedback for tappable surfaces.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A glossy gradient orb whose colors are derived from a stable seed, so every
/// project gets its own slightly different orb.
struct OrbIcon: View {
    let seed: String
    var size: CGFloat = 40

    private var baseHue: Double {
        var hash = 0
        for scalar in seed.unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) & 0xFFFF
        }
        return Double(hash % 360) / 360.0
    }

    var body: some View {
        let h1 = baseHue
        let h2 = (baseHue + 0.11).truncatingRemainder(dividingBy: 1.0)
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hue: h1, saturation: 0.80, brightness: 0.98),
                        Color(hue: h2, saturation: 0.90, brightness: 0.62),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Circle().fill(
                    RadialGradient(
                        colors: [.white.opacity(0.50), .clear],
                        center: UnitPoint(x: 0.32, y: 0.26),
                        startRadius: 1,
                        endRadius: size * 0.6
                    )
                )
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.8))
            .frame(width: size, height: size)
            .shadow(color: Color(hue: h1, saturation: 0.85, brightness: 0.85).opacity(0.40), radius: 5, y: 2)
    }
}
