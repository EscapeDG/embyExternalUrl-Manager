import Foundation

// MARK: - Config Service

/// Manages loading/saving AppConfig, rendering templates, and writing deployment files.
/// Single write path for `config.json`; UI should only mutate `config` and call `save()`.
final class ConfigService: ObservableObject {
    static let shared = ConfigService()

    private let appSupportDir: URL
    private let configFileURL: URL
    private let backupDirURL: URL

    /// In-memory configuration. Edits mark `isDirty` until a successful `save()`.
    @Published var config: AppConfig = .init() {
        didSet {
            guard !isApplyingSnapshot else { return }
            isDirty = (config != lastSavedConfig)
        }
    }
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var lastSavedAt: Date?
    @Published var lastReport: DeploymentReport?
    @Published var lastPersistenceError: String?

    private var lastSavedConfig: AppConfig = .init()
    private var isApplyingSnapshot = false

    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = paths.appendingPathComponent("embyExternalUrl-Manager", isDirectory: true)
        configFileURL = appSupportDir.appendingPathComponent("config.json")
        backupDirURL = appSupportDir.appendingPathComponent("Backups")

        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupDirURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Load / Save

    func load() {
        lastPersistenceError = nil
        let fm = FileManager.default
        guard fm.fileExists(atPath: configFileURL.path) else {
            applySnapshot(AppConfig(), markSaved: true)
            return
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            applySnapshot(decoded, markSaved: true)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupURL = backupDirURL.appendingPathComponent("config.corrupt.\(stamp).json")
            do {
                try fm.copyItem(at: configFileURL, to: backupURL)
                applySnapshot(AppConfig(), markSaved: true)
                lastPersistenceError = "配置文件无法解析，已备份并恢复默认。\(backupURL.lastPathComponent)"
            } catch {
                lastPersistenceError = "配置文件无法解析且备份失败，已保留原文件与当前配置：\(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func save() -> Bool {
        lastPersistenceError = nil
        do {
            try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFileURL, options: .atomic)
            lastSavedConfig = config
            isDirty = false
            lastSavedAt = Date()
            return true
        } catch {
            lastPersistenceError = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    /// Saves only when dirty. Returns true if disk matches memory afterward.
    @discardableResult
    func saveIfNeeded() -> Bool {
        if !isDirty { return true }
        return save()
    }

    @discardableResult
    func resetToDefaults() -> Bool {
        applySnapshot(AppConfig(), markSaved: false)
        return save()
    }

    private func applySnapshot(_ value: AppConfig, markSaved: Bool) {
        isApplyingSnapshot = true
        config = value
        isApplyingSnapshot = false
        if markSaved {
            lastSavedConfig = value
            isDirty = false
            lastSavedAt = Date()
        } else {
            isDirty = (config != lastSavedConfig)
        }
    }

    // MARK: - Deployment Directory

    func ensureDeploymentDirectory() -> String {
        let dir: String
        if !config.deploymentDirectory.isEmpty {
            dir = config.deploymentDirectory
        } else {
            dir = appSupportDir.appendingPathComponent(config.mediaServerType.deploymentSubfolder).path
        }
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir + "/logs"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir + "/cache"), withIntermediateDirectories: true)
        return dir
    }

    func nginxConfigDirectory() -> String {
        if !config.nginxConfigDirectory.isEmpty {
            return config.nginxConfigDirectory
        }
        // Default: look for nginx config inside deployment directory
        return ensureDeploymentDirectory() + "/nginx"
    }

    // MARK: - Generate Deployment Files

    /// Generates deployment files. **Always persists dirty config first** so disk and generate stay aligned.
    func generateDeployment() async -> DeploymentReport {
        // Fundamental gate: never generate from unsaved memory only.
        if !saveIfNeeded() {
            let report = DeploymentReport(
                generatedAt: Date(),
                targetDirectory: ensureDeploymentDirectory(),
                filesWritten: [],
                errors: [lastPersistenceError ?? "配置保存失败，已中止生成。"],
                warnings: []
            )
            await MainActor.run { self.lastReport = report }
            return report
        }

        let deployDir = ensureDeploymentDirectory()
        let nginxDir = nginxConfigDirectory()
        let nginxConfDir = nginxDir + "/conf.d"
        let nginxConfigDir = nginxConfDir + "/config"
        let nginxIncludesDir = nginxConfDir + "/includes"

        // Ensure nginx config directories exist
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: nginxDir), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: nginxConfDir), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: nginxConfigDir), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: nginxIncludesDir), withIntermediateDirectories: true)

        let config = self.config
        var variables: [String: String] = [:]
        var errors: [String] = []
        var warnings: [String] = []
        var writtenFiles: [String] = []

        // Build variables
        // Server specific variables
        switch config.mediaServerType {
        case .plex:
            variables["PLEX_SERVER_URL"] = jsonString(config.plex.serverURL)
            variables["PROXY_PORT"] = String(config.plex.proxyPort)
            variables["PROXY_HTTPS_PORT"] = String(config.plex.proxyHttpsPort)
            variables["CONTAINER_NAME"] = config.mediaServerType.containerName
        case .emby:
            variables["EMBY_SERVER_URL"] = jsonString(config.emby.serverURL)
            variables["EMBY_API_KEY"] = jsonString(config.emby.apiKey)
            variables["PROXY_PORT"] = String(config.emby.proxyPort)
            variables["PROXY_HTTPS_PORT"] = String(config.emby.proxyHttpsPort)
            variables["CONTAINER_NAME"] = config.mediaServerType.containerName
        case .jellyfin:
            variables["EMBY_SERVER_URL"] = jsonString(config.jellyfin.serverURL)
            variables["EMBY_API_KEY"] = jsonString(config.jellyfin.apiKey)
            variables["PROXY_PORT"] = String(config.jellyfin.proxyPort)
            variables["PROXY_HTTPS_PORT"] = String(config.jellyfin.proxyHttpsPort)
            variables["CONTAINER_NAME"] = config.mediaServerType.containerName
        }

        // OpenList
        let olURL = config.openList.serverURL
        variables["OPENLIST_URL"] = jsonString(olURL)
        variables["OPENLIST_TOKEN"] = jsonString(config.openList.token)
        variables["OPENLIST_PUBLIC_URL"] = jsonString(
            config.openList.publicURL.isEmpty ? olURL : config.openList.publicURL
        )
        // Sign
        variables["SIGN_ENABLED"] = config.openList.signEnabled ? "true" : "false"
        variables["SIGN_EXPIRE_HOURS"] = String(config.openList.signExpireHours)
        // Fallback
        variables["FALLBACK_USE_ORIGINAL"] = config.redirect.fallbackUseOriginal ? "true" : "false"
        // Redirect
        variables["REDIRECT_ENABLED"] = config.redirect.enabled ? "true" : "false"
        variables["ENABLE_PART_STREAM"] = config.redirect.enablePartStreamPlayOrDownload ? "true" : "false"
        variables["ENABLE_VIDEO_TRANSCODE"] = config.redirect.enableVideoTranscodePlay ? "true" : "false"
        variables["EMBY_VIDEO_STREAM_PLAY"] = config.redirect.enableVideoStreamPlay ? "true" : "false"
        variables["EMBY_VIDEO_LIVE_PLAY"] = config.redirect.enableVideoLivePlay ? "true" : "false"
        variables["EMBY_AUDIO_STREAM_PLAY"] = config.redirect.enableAudioStreamPlay ? "true" : "false"
        variables["EMBY_ITEMS_DOWNLOAD"] = config.redirect.enableItemsDownload ? "true" : "false"
        variables["EMBY_SYNC_DOWNLOAD"] = config.redirect.enableSyncDownload ? "true" : "false"
        variables["WEB_COOKIE_115"] = jsonString(config.redirect.webCookie115)
        variables["DIRECT_HLS_ENABLE"] = config.redirect.directHlsEnable ? "true" : "false"
        variables["DIRECT_HLS_DEFAULT_PLAY_MAX"] = config.redirect.directHlsDefaultPlayMax ? "true" : "false"
        // Transcode
        variables["TRANSCODE_ENABLED"] = config.redirect.transcodeEnabled ? "true" : "false"
        // Route cache
        variables["ROUTE_CACHE_ENABLED"] = config.redirect.routeCacheEnabled ? "true" : "false"
        // Mount paths
        variables["MEDIA_MOUNT_PATHS"] = jsonArray(config.mount.mediaMountPaths)
        // Path mappings
        let enabledMappings = config.pathMappings.filter(\.enabled)
        variables["MEDIA_PATH_MAPPING"] = mediaPathMappingJS(enabledMappings)
        // Docker compose
        variables["DEPLOY_DIR"] = yamlEscape(deployDir)
        variables["NGINX_CONF"] = yamlEscape(nginxDir)

        // Render and write each template.
        // typeSpecific: look under Templates/plex or Templates/emby first.
        // common: docker-compose.yml lives at Templates/docker-compose.yml.
        let composeURL = URL(fileURLWithPath: deployDir).appendingPathComponent("docker-compose.yml")
        var templates: [(name: String, templateName: String, dest: URL, typeSpecific: Bool)] = [
            ("constant.js", "constant.js", URL(fileURLWithPath: nginxConfDir).appendingPathComponent("constant.js"), true),
            ("constant-mount.js", "constant-mount.js", URL(fileURLWithPath: nginxConfigDir).appendingPathComponent("constant-mount.js"), true),
            ("constant-pro.js", "constant-pro.js", URL(fileURLWithPath: nginxConfigDir).appendingPathComponent("constant-pro.js"), true),
            ("constant-transcode.js", "constant-transcode.js", URL(fileURLWithPath: nginxConfigDir).appendingPathComponent("constant-transcode.js"), true),
            ("http.conf", "http.conf", URL(fileURLWithPath: nginxIncludesDir).appendingPathComponent("http.conf"), false),
            ("https.conf", "https.conf", URL(fileURLWithPath: nginxIncludesDir).appendingPathComponent("https.conf"), false),
        ]

        if FileManager.default.fileExists(atPath: composeURL.path) {
            warnings.append("docker-compose.yml 已存在，本次保留未覆盖。如需重新生成，请先删除该文件。")
        } else {
            templates.append(("docker-compose.yml", "docker-compose.yml", composeURL, false))
        }

        if config.mediaServerType != .plex {
            templates.append(("constant-ext.js", "constant-ext.js", URL(fileURLWithPath: nginxConfigDir).appendingPathComponent("constant-ext.js"), true))
        }

        let renderer = TemplateRenderer.shared
        let backupDir = backupDirURL.path
        let templateSubfolder = config.mediaServerType.templateSubfolder

        for (name, templateName, destURL, typeSpecific) in templates {
            let bundle = ConfigService.templatesBundle
            let templatePath: URL?
            if typeSpecific {
                templatePath = bundle.url(forResource: "\(templateSubfolder)/\(templateName)", withExtension: nil)
                    ?? bundle.url(forResource: "Templates/\(templateName)", withExtension: nil)
            } else {
                templatePath = bundle.url(forResource: "Templates/\(templateName)", withExtension: nil)
                    ?? bundle.url(forResource: templateName, withExtension: nil)
            }
            guard let templatePath,
                  let templateContent = try? String(contentsOf: templatePath, encoding: .utf8) else {
                errors.append("Template \(templateName) not found")
                continue
            }

            let (rendered, unresolved) = renderer.render(template: templateContent, variables: variables)
            if !unresolved.isEmpty {
                errors.append("Unresolved variables in \(templateName): \(unresolved.joined(separator: ", "))")
                continue
            }

            do {
                _ = try renderer.writeRendered(content: rendered, to: destURL, backupDir: backupDir)
                writtenFiles.append(destURL.path)
            } catch {
                errors.append("Failed to write \(name): \(error.localizedDescription)")
            }
        }

        // Dynamically enable/disable HTTPS in active conf depending on SSL certificates, and disable conflicting config files
        let activeConfName = config.mediaServerType.nginxConfName
        let inactiveConfName = config.mediaServerType == .plex ? "emby.conf" : "plex.conf"

        let activeConfURL = URL(fileURLWithPath: nginxConfDir).appendingPathComponent(activeConfName)
        let activeDisabledURL = URL(fileURLWithPath: nginxConfDir).appendingPathComponent("\(activeConfName).disabled")
        if !FileManager.default.fileExists(atPath: activeConfURL.path),
           FileManager.default.fileExists(atPath: activeDisabledURL.path) {
            try? FileManager.default.moveItem(at: activeDisabledURL, to: activeConfURL)
        }

        let inactiveConfURL = URL(fileURLWithPath: nginxConfDir).appendingPathComponent(inactiveConfName)
        if FileManager.default.fileExists(atPath: inactiveConfURL.path) {
            // Rename the inactive configuration file to .disabled so Nginx doesn't load it, preserving it safely
            let disabledURL = URL(fileURLWithPath: nginxConfDir).appendingPathComponent("\(inactiveConfName).disabled")
            try? FileManager.default.removeItem(at: disabledURL)
            try? FileManager.default.moveItem(at: inactiveConfURL, to: disabledURL)
        }

        let certDir = URL(fileURLWithPath: nginxDir).appendingPathComponent("conf.d/cert")
        let fullchainFile = certDir.appendingPathComponent("fullchain.pem")
        let keyFile = certDir.appendingPathComponent("privkey.key")
        let hasCerts = FileManager.default.fileExists(atPath: fullchainFile.path) && FileManager.default.fileExists(atPath: keyFile.path)

        if FileManager.default.fileExists(atPath: activeConfURL.path),
           let content = try? String(contentsOf: activeConfURL, encoding: .utf8) {
            var newContent = content
            if hasCerts {
                newContent = newContent.replacingOccurrences(
                    of: "# include /etc/nginx/conf.d/includes/https.conf;",
                    with: "include /etc/nginx/conf.d/includes/https.conf;"
                )
            } else {
                newContent = newContent.replacingOccurrences(
                    of: "include /etc/nginx/conf.d/includes/https.conf;",
                    with: "# include /etc/nginx/conf.d/includes/https.conf;"
                )
                newContent = newContent.replacingOccurrences(
                    of: "# # include /etc/nginx/conf.d/includes/https.conf;",
                    with: "# include /etc/nginx/conf.d/includes/https.conf;"
                )
            }

            if newContent != content {
                do {
                    try newContent.write(to: activeConfURL, atomically: true, encoding: .utf8)
                    writtenFiles.append(activeConfURL.path)
                } catch {
                    errors.append("Failed to update \(activeConfName) SSL configuration: \(error.localizedDescription)")
                }
            }
        }

        // Skeleton checks: parameter generate does not replace full upstream nginx tree.
        let fm = FileManager.default
        let nginxConfPath = nginxDir + "/nginx.conf"
        if !fm.fileExists(atPath: nginxConfPath) {
            warnings.append("缺少 \(nginxConfPath)。请先在「上游同步」复制 nginx 骨架，再生成参数。")
        }
        if !fm.fileExists(atPath: activeConfURL.path) {
            warnings.append("缺少 \(activeConfName)。请先上游同步，或确认 nginx 配置目录正确。")
        }
        var helperFiles = [
            "constant-common.js",
            "constant-symlink.js",
            "constant-strm.js"
        ]
        if config.mediaServerType != .plex {
            helperFiles.append("constant-nginx.js")
        }
        for helper in helperFiles {
            let path = nginxConfigDir + "/" + helper
            if !fm.fileExists(atPath: path) {
                warnings.append("缺少 \(helper)（constant.js 会 import）。请先上游同步。")
            }
        }
        if !fm.fileExists(atPath: deployDir + "/docker-compose.yml") {
            warnings.append("docker-compose.yml 未写入部署目录，容器启动将失败。")
        }

        let report = DeploymentReport(
            generatedAt: Date(),
            targetDirectory: deployDir,
            filesWritten: writtenFiles,
            errors: errors,
            warnings: warnings
        )

        await MainActor.run {
            self.lastReport = report
        }

        return report
    }

    // MARK: - Helpers

    private func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return str.replacingOccurrences(of: "\\/", with: "/")
    }

    private func jsonArray(_ values: [String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return str.replacingOccurrences(of: "\\/", with: "/")
    }

    private func yamlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func mediaPathMappingJS(_ mappings: [PathMapping]) -> String {
        let rows: [[Any]] = mappings.map { [0, 0, $0.localPrefix, $0.remotePrefix] }
        guard JSONSerialization.isValidJSONObject(rows),
              let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str.replacingOccurrences(of: "\\/", with: "/")
    }

    private static var templatesBundle: Bundle {
        let mainBundle = Bundle.main
        if let resourceURL = mainBundle.resourceURL {
            let bundleURL = resourceURL.appendingPathComponent("embyExternalUrl-Manager_EmbyExternalUrlManager.bundle")
            if let b = Bundle(url: bundleURL) {
                return b
            }
            let oldBundleURL = resourceURL.appendingPathComponent("Plex2AlistManager_Plex2AlistManager.bundle")
            if let b = Bundle(url: oldBundleURL) {
                return b
            }
        }
        let bundleURL = mainBundle.bundleURL.appendingPathComponent("embyExternalUrl-Manager_EmbyExternalUrlManager.bundle")
        if let b = Bundle(url: bundleURL) {
            return b
        }
        let oldBundleURL = mainBundle.bundleURL.appendingPathComponent("Plex2AlistManager_Plex2AlistManager.bundle")
        if let b = Bundle(url: oldBundleURL) {
            return b
        }
        return mainBundle
    }
}
