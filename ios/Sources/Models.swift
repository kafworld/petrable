import Foundation

struct Project: Decodable, Identifiable, Equatable {
    let id: String
    let creationTime: Double
    let name: String
    let emoji: String
    let prompt: String
    let status: String
    let statusDetail: String?
    let platform: String?
    let model: String?
    let sandboxId: String?
    let previewUrl: String?
    let appUrl: String?
    let installUrl: String?
    let version: Double
    let error: String?
    let updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case creationTime = "_creationTime"
        case name, emoji, prompt, status, statusDetail, platform, model, sandboxId
        case previewUrl, appUrl, installUrl, version, error, updatedAt
    }

    static let busyStatuses: Set<String> = [
        "queued", "generating", "sandbox", "uploading", "starting", "waking",
        "updating", "building", "signing", "mac_queued", "mac_building",
    ]

    var isBusy: Bool { Project.busyStatuses.contains(status) }
    var isLive: Bool { status == "live" }
    var isError: Bool { status == "error" }
    var isMobile: Bool { platform == "mobile" }

    var statusLabel: String {
        switch status {
        case "live": return "Live"
        case "error": return "Failed"
        case "queued": return "Queued"
        case "generating": return "Generating"
        case "sandbox": return "Sandbox"
        case "uploading": return "Uploading"
        case "starting": return "Starting"
        case "waking": return "Waking"
        case "updating": return "Updating"
        case "building": return "Building"
        case "signing": return "Signing"
        case "mac_queued": return "Queued for Mac"
        case "mac_building": return "Building on Mac"
        default: return status.capitalized
        }
    }

    /// 0-based build step for the progress indicator, out of `buildStepCount`.
    var buildStep: Int {
        switch status {
        case "queued": return 0
        case "generating", "updating": return 1
        case "sandbox", "waking": return 2
        case "uploading": return 3
        case "starting", "mac_queued", "mac_building": return 4
        default: return 0
        }
    }
    static let buildStepCount = 5
}

struct Message: Decodable, Identifiable, Equatable {
    let id: String
    let creationTime: Double
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case creationTime = "_creationTime"
        case role, content
    }
}

struct ProjectFile: Decodable, Identifiable, Equatable {
    let id: String
    let path: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case path, content
    }

    var lineCount: Int { content.components(separatedBy: "\n").count }

    var language: String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html": return "HTML"
        case "js": return "JavaScript"
        case "css": return "CSS"
        case "json": return "JSON"
        case "md": return "Markdown"
        default: return "Text"
        }
    }
}

struct SystemStatus: Decodable, Equatable {
    let webBuildsReady: Bool
    let mobileBuildsReady: Bool
    let voiceReady: Bool
    let aiGatewayReady: Bool

    static let unknown = SystemStatus(
        webBuildsReady: true,
        mobileBuildsReady: true,
        voiceReady: true,
        aiGatewayReady: true
    )
}
