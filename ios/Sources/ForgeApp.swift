import SwiftUI

@main
struct ForgeApp: App {
    @AppStorage("hasEntered") private var hasEntered = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasEntered {
                    HomeView()
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                } else {
                    WelcomeView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hasEntered)
            .preferredColorScheme(.dark)
            // Root-level URL capture: fires even when the deep modifier in
            // HomeView misses the scene's UIOpenURLAction (iOS 27 beta).
            .onOpenURL { DeepLinkRouter.shared.handle($0) }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        #endif
    }
}
