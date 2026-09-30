import SwiftUI

// KAF World family — logical synthesis of the documented guidelines
// (relo-cobalt.css tokens + Sermo Theme-20260925 acceptance pairs + site :root).
// Structure mirrors the family: NAVY chrome ("part one") + BLUE-GREY working
// surfaces ("part two") + white cards, cobalt links, lime actions. Every
// text pair below is contrast-verified (see docs/BLUEPRINT legibility note).
enum Theme {
    static let hero = Color(red: 11/255, green: 17/255, blue: 31/255)        // #0B131F navy chrome/hero
    static let panel = Color(red: 23/255, green: 38/255, blue: 64/255)       // #172640 dark chip on hero
    static let bg = Color(red: 213/255, green: 223/255, blue: 237/255)       // #D5DFED blue-grey canvas
    static let surface = Color(red: 229/255, green: 238/255, blue: 253/255)  // #E5EFFD surface
    static let surfaceLight = Color(red: 220/255, green: 230/255, blue: 243/255) // #DCE6F3 inset
    static let card = Color.white                                            // white cards
    static let composer = Color.white
    static let stroke = Color(red: 190/255, green: 205/255, blue: 236/255)   // #BED0EC hairline
    static let textPrimary = Color(red: 11/255, green: 21/255, blue: 53/255) // #0B1535 ink
    static let textSecondary = Color(red: 76/255, green: 98/255, blue: 139/255) // #50668F
    static let blue = Color(red: 53/255, green: 72/255, blue: 235/255)       // #3548EB primary links
    static let lime = Color(red: 201/255, green: 252/255, blue: 76/255)      // #C9FC4C actions (navy text)
    static let onHero = Color(red: 231/255, green: 238/255, blue: 247/255)   // #E7EEF7 text on navy
    static let heroMuted = Color(red: 143/255, green: 161/255, blue: 196/255) // #8FA1C4 secondary on navy
    static let green = Color(red: 0.290, green: 0.850, blue: 0.550)
    static let red = Color(red: 0.960, green: 0.380, blue: 0.380)
    static let amber = Color(red: 1.000, green: 0.700, blue: 0.300)

    // Home bloom — KAF colours over the navy hero
    static let bloomBlue = Color(red: 53/255, green: 72/255, blue: 235/255)    // #3548EB
    static let bloomIndigo = Color(red: 70/255, green: 83/255, blue: 244/255)  // #4653F4
    static let bloomPink = Color(red: 196/255, green: 166/255, blue: 255/255)  // #C4A6FF
    static let bloomOrange = Color(red: 201/255, green: 252/255, blue: 76/255) // #C9FC4C lime edge

    static let heartGradient = LinearGradient(
        colors: [bloomOrange, bloomPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The home-screen glow: a single focused cobalt ambient behind the hero
/// content. (The old four-hue "sunset" bloom read as a muddy lilac bruise —
/// independent review and owner feedback both called it out; kept to the
/// navy/cobalt/lime family only.)
struct LovableBloom: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Theme.hero

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Theme.bloomBlue.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: w * 0.75
                        )
                    )
                    .frame(width: w * 1.7, height: h * 0.60)
                    .position(x: w / 2, y: h * 0.78)
                    .blur(radius: 70)
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
    /// true when the button sits on navy/hero chrome (dark treatment);
    /// false (default) for the light blue-grey canvas.
    var onDark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(onDark ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.textPrimary))
                .frame(width: size, height: size)
                .background(
                    onDark ? AnyShapeStyle(Color.white.opacity(0.10)) : AnyShapeStyle(Theme.surface),
                    in: Circle()
                )
                .overlay(
                    Circle().strokeBorder(
                        onDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                        lineWidth: 1
                    )
                )
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
