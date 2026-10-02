import SwiftUI

struct HomeView: View {
    @StateObject private var vm = ProjectsViewModel()
    @StateObject private var voice = VoiceRecorder()
    @State private var prompt = ""
    @State private var platform = "web"
    @AppStorage("selectedModel") private var selectedModel = "free-smart"
    @State private var creating = false
    @State private var path: [String] = []
    @State private var showDrawer = false
    @State private var showToolsSheet = false
    @FocusState private var promptFocused: Bool
    @Namespace private var toggleNamespace

    private let drawerSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)
    private var homeContentMaxWidth: CGFloat {
        #if os(macOS)
        920
        #else
        .infinity
        #endif
    }
    private var drawerWidth: CGFloat {
        #if os(macOS)
        340
        #else
        304
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LovableBloom().onAppear { demoRun() }
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 24)
                    connectPill
                    greeting
                    platformToggle
                    readinessBanner
                    composerCard
                    Spacer(minLength: 48)
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                        Text("Runs on free AI models")
                            .font(.system(size: 13, weight: .medium))
                    }
            .foregroundStyle(Theme.heroMuted)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: homeContentMaxWidth)
                #if os(macOS)
                .padding(.horizontal, 34)
                #endif

                drawerOverlay
            }
            .hiddenNavigationBarWhenAvailable()
            .navigationDestination(for: String.self) { id in
                ChatView(projectId: id)
            }
        }
        .tint(.white)
        .sheet(isPresented: $showToolsSheet) {
            ToolConnectionsSheet(status: vm.systemStatus) { selectedPlatform in
                platform = selectedPlatform
                showToolsSheet = false
                promptFocused = true
            }
        }
        .onOpenURL(perform: handleDeepLink)
        .onReceive(DeepLinkRouter.shared.$pendingProjectId) { id in
            guard let id else { return }
            DeepLinkRouter.shared.clearPendingProject()
            if path.last != id { path = [id] }
        }
        .onReceive(DeepLinkRouter.shared.$pendingHome) { go in
            guard go else { return }
            DeepLinkRouter.shared.clearPendingHome()
            path = []
        }
    }

    // MARK: - Drawer

    @ViewBuilder
    private var drawerOverlay: some View {
        if showDrawer {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture { closeDrawer() }
                .zIndex(1)
            HStack(spacing: 0) {
                ProjectsDrawer(
                    onSelect: { id in
                        closeDrawer()
                        DeepLinkRouter.shared.openProject(id)
                    },
                    onNewBuild: {
                        closeDrawer()
                        promptFocused = true
                    }
                )
                .frame(width: drawerWidth)
                Spacer(minLength: 0)
            }
            .transition(.move(edge: .leading))
            .zIndex(2)
        }
    }

    private func closeDrawer() {
        withAnimation(drawerSpring) { showDrawer = false }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            CircleIconButton(systemName: "line.3.horizontal", onDark: true) {
                Haptics.tap()
                promptFocused = false
                withAnimation(drawerSpring) { showDrawer = true }
            }
            .accessibilityIdentifier("menuButton")
            Spacer()
        }
        .overlay(
            HStack(spacing: 9) {
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("Petrable")
                    .font(.system(size: 27, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var connectPill: some View {
        Button {
            Haptics.tap()
            showToolsSheet = true
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: -5) {
                    toolBadge(systemName: "sparkles")
                    toolBadge(systemName: "terminal")
                    toolBadge(systemName: "globe")
                }
                Text("Connect all your tools")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.onHero)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.heroMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Theme.panel.opacity(0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("connectToolsButton")
    }

    private func toolBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.white.opacity(0.14), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.24), lineWidth: 1))
    }

    private var greeting: some View {
        Text("Got an idea, \(AppConfig.userName)?")
            .font(.system(size: 30, weight: .semibold, design: .serif))
            .foregroundStyle(.white)
            .padding(.top, 20)
    }

    private var platformToggle: some View {
        HStack(spacing: 4) {
            platformButton("Web", icon: "globe", value: "web")
            platformButton("Mobile", icon: "iphone", value: "mobile")
        }
        .padding(4)
        .background(Theme.panel.opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .padding(.top, 16)
    }

    private func platformButton(_ label: String, icon: String, value: String) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.74)) {
                platform = value
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(platform == value ? .white : Theme.onHero.opacity(0.70))
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background {
                if platform == value {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .matchedGeometryEffect(id: "platform-pill", in: toggleNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("platform-\(value)")
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField(
                "",
                text: $prompt,
                prompt: Text("Ask Petrable to build anything…")
                    .foregroundStyle(Theme.heroMuted),
                axis: .vertical
            )
            .font(.system(size: 17))
            .foregroundStyle(Theme.onHero)
            .tint(Theme.blue)
            .lineLimit(1...5)
            .focused($promptFocused)
            .accessibilityIdentifier("promptField")

            HStack(spacing: 18) {
                Menu {
                    Button {
                        Haptics.tap()
                        pasteIntoPrompt()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        Haptics.tap()
                        platform = "mobile"
                        prompt = "Make a polished iPhone app for "
                        promptFocused = true
                    } label: {
                        Label("iPhone App", systemImage: "iphone")
                    }
                    Button {
                        Haptics.tap()
                        platform = "web"
                        prompt = "Make a polished web app for "
                        promptFocused = true
                    } label: {
                        Label("Web App", systemImage: "globe")
                    }
                    Button {
                        Haptics.tap()
                        prompt = "Make a simple todo app with projects, due dates, search and a polished native design"
                        platform = "mobile"
                        promptFocused = true
                    } label: {
                        Label("Todo App Example", systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.onHero)
                }
                .accessibilityIdentifier("homePlusMenu")

                Spacer()

                Menu {
                    ForEach(FreeModels.options, id: \.key) { option in
                        Button {
                            Haptics.tap()
                            selectedModel = option.key
                        } label: {
                            if selectedModel == option.key {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(FreeModels.shortName(for: selectedModel))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.onHero)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.heroMuted)
                    }
                }
                .accessibilityIdentifier("modelMenu")

                VoiceButton(voice: voice) { text in
                    prompt = prompt.isEmpty ? text : prompt + " " + text
                }

                Button(action: submit) {
                    ZStack {
                        Circle()
                            .fill(canSubmit ? Theme.lime : Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .strokeBorder(canSubmit ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
                            )
                        if creating {
                            ProgressView().tint(canSubmit ? .black : .white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(canSubmit ? .black : Theme.heroMuted)
                        }
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSubmit)
                .accessibilityIdentifier("sendButton")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Theme.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func pasteIntoPrompt() {
        guard let pasted = Clipboard.pasteText()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.isEmpty else {
            Haptics.error()
            return
        }
        prompt = prompt.isEmpty ? pasted : prompt + " " + pasted
        promptFocused = true
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !creating && !selectedPlatformBlocked
    }

    private var selectedPlatformBlocked: Bool {
        platform == "mobile" && !vm.systemStatus.mobileBuildsReady
    }

    @ViewBuilder
    private var readinessBanner: some View {
        if selectedPlatformBlocked {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 28, height: 28)
                    .background(Theme.amber.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mobile builds need your Mac")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Web builds are ready. Start the Mac worker to compile native iPhone apps with Xcode.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.amber.opacity(0.28), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func demoRun() {
        guard ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        let phrase = "Build a landing page announcing the release of my short story"
        let words = phrase.split(separator: " ")
        for (i, w) in words.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4 + Double(i) * 0.26) {
                prompt = prompt.isEmpty ? String(w) : prompt + " " + w
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4 + Double(words.count) * 0.26 + 1.1) {
            submit()
        }
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !creating, !selectedPlatformBlocked else {
            Haptics.error()
            return
        }
        creating = true
        Haptics.tap()
        Task {
            if let id = await vm.create(prompt: text, platform: platform, model: selectedModel) {
                prompt = ""
                promptFocused = false
                path.append(id)
            } else {
                Haptics.error()
            }
            creating = false
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Delegate to the shared router (also registered at the app root);
        // pending id/home are consumed by the onReceive handlers above.
        DeepLinkRouter.shared.handle(url)
    }
}

// MARK: - Tool connections

private struct ToolConnectionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let status: SystemStatus
    let onStart: (String) -> Void

    private var connections: [ToolConnection] {
        [
            ToolConnection(
                name: "Free AI",
                detail: "Build reasoning, edits and repair run on free Gemini, Groq and OpenRouter models.",
                status: status.webBuildsReady ? "Ready" : "Needs key",
                icon: "sparkles",
                color: status.webBuildsReady ? Theme.green : Theme.amber
            ),
            ToolConnection(
                name: "Daytona",
                detail: "Web builds run in hosted sandboxes and return live preview links.",
                status: status.webBuildsReady ? "Ready" : "Needs key",
                icon: "globe",
                color: status.webBuildsReady ? Theme.blue : Theme.amber
            ),
            ToolConnection(
                name: "Mac Worker",
                detail: "Native iPhone builds compile with Xcode on your Mac and return IPA files.",
                status: status.mobileBuildsReady ? "Ready" : "Needs setup",
                icon: "desktopcomputer",
                color: status.mobileBuildsReady ? Theme.green : Theme.amber
            ),
            ToolConnection(
                name: "Groq Voice",
                detail: "Voice prompts transcribe free on the server when the Groq key is present.",
                status: status.voiceReady ? "Ready" : "Optional",
                icon: "waveform",
                color: status.voiceReady ? Theme.green : Color(red: 0.80, green: 0.48, blue: 1.00)
            ),
            ToolConnection(
                name: "Free AI Proxy",
                detail: "Generated apps call the keyless proxy for free AI without exposing any key.",
                status: status.aiGatewayReady ? "Ready" : "Optional",
                icon: "sparkles",
                color: status.aiGatewayReady ? Theme.green : Color(red: 0.22, green: 0.62, blue: 1.00)
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusPanel

                    VStack(spacing: 10) {
                        ForEach(connections) { connection in
                            connectionRow(connection)
                        }
                    }

                    VStack(spacing: 12) {
                        startButton(title: "Start web build", icon: "globe", platform: "web")
                        startButton(title: "Start iPhone build", icon: "iphone", platform: "mobile")
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 26)
            }
            .background(Theme.hero.ignoresSafeArea())
            .navigationTitle("Tool connections")
            .navyToolbarBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.onHero)
                }
            }
        }
            .darkNavigationChromeWhenAvailable()
            .desktopSheetFrame(width: 640, height: 720)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .frame(width: 40, height: 40)
                    .background(Theme.green.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(status.mobileBuildsReady ? "Connected through Convex" : "Web builds are ready")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                    Text(status.mobileBuildsReady
                         ? "Petrable uses server-side environment keys, so the phone does not need separate sign-ins for each tool."
                         : "Mobile builds need the Mac worker. Until then, Petrable will steer you to web builds instead of failing late.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.heroMuted)
                Text(AppConfig.convexDeploymentURL.replacingOccurrences(of: "https://", with: ""))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(Color(red:201/255,green:212/255,blue:234/255))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Theme.panel.opacity(0.9), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .padding(16)
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func connectionRow(_ connection: ToolConnection) -> some View {
        HStack(spacing: 13) {
            Image(systemName: connection.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(connection.color)
                .frame(width: 38, height: 38)
                .background(connection.color.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(connection.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(connection.status)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(connection.color)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(connection.color.opacity(0.13), in: Capsule())
                }
                Text(connection.detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card.opacity(0.95), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func startButton(title: String, icon: String, platform: String) -> some View {
        let blocked = platform == "mobile" && !status.mobileBuildsReady
        return Button {
            Haptics.tap()
            onStart(platform)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(blocked ? Theme.textSecondary : .black)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(blocked ? Theme.surfaceLight.opacity(0.65) : .white, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(blocked ? Theme.amber.opacity(0.28) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(blocked)
        .accessibilityIdentifier("toolConnections-\(platform)")
    }
}

private struct ToolConnection: Identifiable {
    let name: String
    let detail: String
    let status: String
    let icon: String
    let color: Color

    var id: String { name }
}

// MARK: - Left drawer

struct ProjectsDrawer: View {
    @StateObject private var vm = ProjectsViewModel()
    let onSelect: (String) -> Void
    let onNewBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text("Your builds")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Button {
                Haptics.tap()
                onNewBuild()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Theme.lime, in: Circle())
                    Text("New build")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            if vm.loaded && vm.projects.isEmpty {
                Text("No builds yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.heroMuted)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(vm.projects) { project in
                            Button {
                                Haptics.tap()
                                onSelect(project.id)
                            } label: {
                                drawerRow(project)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityIdentifier("drawer-\(project.name)")
                            .contextMenu {
                                Button(role: .destructive) {
                                    vm.delete(project)
                                } label: {
                                    Label("Delete build", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    #if os(macOS)
            .padding(.bottom, 46)
#else
            .padding(.bottom, 30)
#endif
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Theme.hero
                .clipShape(.rect(bottomTrailingRadius: 28, topTrailingRadius: 28))
                .ignoresSafeArea()
                .shadow(color: .black.opacity(0.6), radius: 24, x: 8)
        )
    }

    private func drawerRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            OrbIcon(seed: project.id, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.onHero)
                        .lineLimit(1)
                    if project.isMobile {
                        Image(systemName: "iphone")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.lime)
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(statusColor(project)).frame(width: 6, height: 6)
                    Text(project.isBusy ? (project.statusDetail ?? "Working…") : project.statusLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.heroMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.heroMuted.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func statusColor(_ project: Project) -> Color {
        if project.isLive { return Theme.green }
        if project.isError { return Theme.red }
        return Theme.amber
    }
}
