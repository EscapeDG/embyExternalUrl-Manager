import Foundation

// MARK: - Certificate summary (dashboard-safe)

struct CertificateSummary: Equatable {
    var directory: String
    var subject: String
    var issuer: String
    var daysRemaining: Int?
    var isExpired: Bool
    var statusTitle: String
    var level: Level

    enum Level: Equatable {
        case ok
        case warning
        case error
        case unknown
    }
}

// MARK: - System Status Store

/// Single source for Docker/container/certificate status shared by dashboard, generate, menu bar.
@MainActor
final class SystemStatusStore: ObservableObject {
    static let shared = SystemStatusStore()

    @Published private(set) var dockerAvailable: Bool = false
    @Published private(set) var containerRunning: Bool = false
    @Published private(set) var containerStatus: String = ""
    @Published private(set) var certificateSummary: CertificateSummary?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing: Bool = false

    private var lastRefreshAttempt: Date?
    private let minInterval: TimeInterval = 2

    private init() {}

    /// Debounced refresh of Docker engine + container. Pass `force` for toolbar buttons.
    func refreshDocker(mediaServerType: MediaServerType, force: Bool = false) async {
        if !force, let last = lastRefreshAttempt, Date().timeIntervalSince(last) < minInterval {
            return
        }
        lastRefreshAttempt = Date()
        isRefreshing = true
        defer { isRefreshing = false }

        await DockerService.shared.detect()
        _ = await DockerService.shared.ps(mediaServerType: mediaServerType)

        dockerAvailable = DockerService.shared.isAvailable
        containerRunning = DockerService.shared.containerRunning
        containerStatus = DockerService.shared.containerStatus
        lastRefresh = Date()
    }

    /// Inspect certificate under nginx conf.d/cert (or custom directory).
    func refreshCertificate(certDirectory: String) async {
        let trimmed = certDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            certificateSummary = CertificateSummary(
                directory: "",
                subject: "",
                issuer: "",
                daysRemaining: nil,
                isExpired: false,
                statusTitle: "未配置证书目录",
                level: .unknown
            )
            return
        }

        let inspection = await CertificateService.shared.inspectCertificate(certDirectory: trimmed)
        if inspection.commandResult.exitCode != 0 {
            certificateSummary = CertificateSummary(
                directory: trimmed,
                subject: "",
                issuer: "",
                daysRemaining: nil,
                isExpired: false,
                statusTitle: "未检测到可用证书",
                level: .warning
            )
            return
        }

        let days = inspection.daysRemaining
        let level: CertificateSummary.Level
        let title: String
        if inspection.isExpired {
            level = .error
            title = "证书已过期"
        } else if let days, days <= 14 {
            level = .warning
            title = "即将到期（\(days) 天）"
        } else if let days {
            level = .ok
            title = "有效（剩余 \(days) 天）"
        } else {
            level = .ok
            title = "已安装"
        }

        certificateSummary = CertificateSummary(
            directory: trimmed,
            subject: inspection.subject,
            issuer: inspection.issuer,
            daysRemaining: days,
            isExpired: inspection.isExpired,
            statusTitle: title,
            level: level
        )
    }

    /// Full refresh used by dashboard / pipeline.
    func refreshAll(configService: ConfigService, force: Bool = false) async {
        let type = configService.config.mediaServerType
        await refreshDocker(mediaServerType: type, force: force)

        let nginxDir = configService.nginxConfigDirectory()
        let certDir = configService.config.certificateDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (certDir?.isEmpty == false) ? certDir! : (nginxDir + "/conf.d/cert")
        await refreshCertificate(certDirectory: resolved)
    }
}
