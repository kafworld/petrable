import Combine
import Foundation

enum ProjectTab: String {
    case agent
    case preview
    case code
}

/// Routes forge:// deep links and in-app navigation requests:
///   forge://home                          -> pop to the home screen
///   forge://project/<id>                  -> open a project chat
///   forge://project/<id>?tab=preview      -> open chat + full-screen preview
///   forge://project/<id>?tab=code         -> open chat + details sheet
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var requestedTab: ProjectTab?
    @Published var pendingProjectId: String?
    @Published var pendingHome = false

    private init() {}

    func openProject(_ id: String, tab: ProjectTab? = nil) {
        requestedTab = tab
        pendingProjectId = id
    }

    /// Single entry point for forge:// URLs. Attached at the app root
    /// (ForgeApp) as well as HomeView: on the current iOS beta the
    /// scene receives UIOpenURLAction but a modifier-level .onOpenURL
    /// deep in the tree never fires — registering at the root fixed it.
    func handle(_ url: URL) {
        NSLog("Forge: router got url=\(url.absoluteString) host=\(url.host ?? "nil") last=\(url.lastPathComponent)")
        guard url.scheme == "forge" else { return }
        switch url.host() {
        case "home":
            goHome()
        case "project":
            let id = url.lastPathComponent
            guard !id.isEmpty, id != "/" else { return }
            var tab: ProjectTab?
            if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "tab" })?.value {
                tab = DeepLinkRouter.tab(from: raw)
            }
            openProject(id, tab: tab)
        default:
            break
        }
    }

    func goHome() {
        pendingHome = true
    }

    func consumeTab() -> ProjectTab? {
        let tab = requestedTab
        if tab != nil {
            DispatchQueue.main.async { [weak self] in
                if self?.requestedTab == tab { self?.requestedTab = nil }
            }
        }
        return tab
    }

    func clearPendingProject() {
        DispatchQueue.main.async { [weak self] in
            self?.pendingProjectId = nil
        }
    }

    func clearPendingHome() {
        DispatchQueue.main.async { [weak self] in
            self?.pendingHome = false
        }
    }

    static func tab(from raw: String) -> ProjectTab? {
        ProjectTab(rawValue: raw.lowercased())
    }
}
