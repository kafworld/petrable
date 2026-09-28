import SwiftUI

struct WelcomeView: View {
    @AppStorage("hasEntered") private var hasEntered = false
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let scale = min(max(geo.size.height / 852, 0.88), 1.04)

            ZStack {
                LovableBloom()

                VStack(spacing: 0) {
                    Spacer(minLength: 44)

                    Image("LogoMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92 * scale, height: 92 * scale)
                        .shadow(color: Theme.bloomPink.opacity(0.44), radius: 24, y: 8)
                        .scaleEffect(appeared ? 1 : 0.72)
                        .opacity(appeared ? 1 : 0)

                    Text("Petrable")
                        .font(.system(size: 46 * scale, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.82)
                        .lineLimit(1)
                        .padding(.top, 22)

                    Text("Build anything.\nRight from your phone.")
                        .font(.system(size: 17 * scale, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                        .padding(.top, 10)
                        .opacity(appeared ? 1 : 0)

                    Spacer(minLength: 80)

                    Button {
                        Haptics.tap()
                        hasEntered = true
                    } label: {
                        Text("Enter App")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(Theme.lime, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("enterAppButton")
                    .padding(.bottom, 16)

                    Text("One user · No sign-in needed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary.opacity(0.85))
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 28)
                .accessibilityElement(children: .contain)
            }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                    appeared = true
                }
            }
        }
    }
}
