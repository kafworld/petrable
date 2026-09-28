import Combine
import ConvexMobile
import Foundation

final class ConvexService {
    static let shared = ConvexService()
    let client: ConvexClient

    private init() {
        client = ConvexClient(deploymentUrl: AppConfig.convexDeploymentURL)
    }
}

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var systemStatus = SystemStatus.unknown
    @Published var loaded = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        let client = ConvexService.shared.client

        client
            .subscribe(to: "projects:list", yielding: [Project].self)
            .replaceError(with: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] projects in
                self?.projects = projects
                self?.loaded = true
            }
            .store(in: &cancellables)

        client
            .subscribe(to: "system:status", yielding: SystemStatus.self)
            .replaceError(with: .unknown)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.systemStatus = status
            }
            .store(in: &cancellables)
    }

    func create(prompt: String, platform: String, model: String) async -> String? {
        do {
            let id: String = try await ConvexService.shared.client
                .mutation("projects:create", with: [
                    "prompt": prompt, "platform": platform, "model": model,
                ])
            return id
        } catch {
            print("Forge: create failed: \(error)")
            return nil
        }
    }

    func delete(_ project: Project) {
        Task {
            do {
                try await ConvexService.shared.client
                    .mutation("projects:remove", with: ["id": project.id])
            } catch {
                print("Forge: delete failed: \(error)")
            }
        }
    }
}

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var project: Project?
    @Published var messages: [Message] = []
    @Published var files: [ProjectFile] = []
    let projectId: String
    private var cancellables = Set<AnyCancellable>()

    init(projectId: String) {
        self.projectId = projectId
        let client = ConvexService.shared.client

        client
            .subscribe(to: "projects:get", with: ["id": projectId], yielding: Project?.self)
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.project = $0 }
            .store(in: &cancellables)

        client
            .subscribe(to: "messages:list", with: ["projectId": projectId], yielding: [Message].self)
            .replaceError(with: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.messages = $0 }
            .store(in: &cancellables)

        client
            .subscribe(to: "files:list", with: ["projectId": projectId], yielding: [ProjectFile].self)
            .replaceError(with: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.files = $0 }
            .store(in: &cancellables)
    }

    func send(_ text: String) async -> Bool {
        do {
            try await ConvexService.shared.client
                .mutation("messages:send", with: ["projectId": projectId, "content": text])
            return true
        } catch {
            print("Forge: send failed: \(error)")
            return false
        }
    }

    func setModel(_ model: String) {
        Task {
            try? await ConvexService.shared.client
                .mutation("projects:setModel", with: ["id": projectId, "model": model])
        }
    }

    /// Wakes the sandbox if it auto-stopped while the project sat idle.
    func wake() {
        Task {
            try? await ConvexService.shared.client
                .mutation("projects:wake", with: ["id": projectId])
        }
    }

    func retry() {
        Task {
            try? await ConvexService.shared.client
                .mutation("projects:retry", with: ["id": projectId])
        }
    }
}
