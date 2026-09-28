import SwiftUI
import WebKit

/// Full-screen preview of the running app with Lovable's floating bottom bar.
struct PreviewScreen: View {
    @ObservedObject var vm: ProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let project = vm.project,
                   let urlString = project.previewUrl,
                   let url = URL(string: urlString) {
                    PreviewWebView(url: url, version: Int(project.version), reloadToken: reloadToken)
                } else if let project = vm.project,
                          project.isMobile,
                          project.isLive {
                    mobileReadyView(project)
                } else {
                    ZStack {
                        Theme.bg
                        VStack(spacing: 14) {
                            ProgressView().tint(Theme.blue)
                            Text(vm.project?.statusDetail ?? "Getting things ready…")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            bottomBar
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func mobileReadyView(_ project: Project) -> some View {
        ZStack {
            Theme.bg
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Theme.green)

                VStack(spacing: 8) {
                    Text("\(project.name) is Apple-ready")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(project.statusDetail ?? "IPA built on your Mac")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let appUrl = project.appUrl, !appUrl.isEmpty {
                    Button {
                        Clipboard.copy(appUrl)
                        Haptics.tap()
                    } label: {
                        Label("Copy IPA Path", systemImage: "doc.on.doc")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 18)
                            .frame(height: 48)
                            .background(Theme.surfaceLight.opacity(0.85), in: Capsule())
                    }
                    .accessibilityIdentifier("copyIpaPathButton")
                }
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 520)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 11) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Chat")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 20)
                .frame(height: 48)
                .background(Theme.surfaceLight.opacity(0.85), in: Capsule())
            }
            .accessibilityIdentifier("chatBackButton")

            Spacer()

            barCircle(systemName: "mic") { Haptics.tap() }
            barCircle(systemName: "arrow.triangle.2.circlepath") {
                Haptics.tap()
                reloadToken += 1
            }
            if let urlString = vm.project?.previewUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    #if os(macOS)
                    Label("Open in Browser", systemImage: "safari")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(Theme.surfaceLight.opacity(0.85), in: Capsule())
                    #else
                    Image(systemName: "safari")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(Theme.surfaceLight.opacity(0.85), in: Circle())
                    #endif
                }
            }
            if let urlString = vm.project?.previewUrl, let url = URL(string: urlString) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(Theme.surfaceLight.opacity(0.85), in: Circle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Theme.bg)
    }

    private func barCircle(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(Theme.surfaceLight.opacity(0.85), in: Circle())
        }
    }
}

struct PreviewWebView {
    let url: URL
    let version: Int
    let reloadToken: Int
}

extension PreviewWebView {
    private var cacheKey: String {
        "\(url.absoluteString)|v\(version)|r\(reloadToken)"
    }

    private func load(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedKey = cacheKey
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }

    final class Coordinator {
        var loadedKey: String?
    }
}

#if os(macOS)
extension PreviewWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        load(webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedKey != cacheKey else { return }
        load(webView, coordinator: context.coordinator)
    }
}
#else
extension PreviewWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
        load(webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedKey != cacheKey else { return }
        load(webView, coordinator: context.coordinator)
    }
}
#endif
