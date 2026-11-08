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

    /// `appSupportDirectory` 仅供测试注入隔离目录；应用本身只使用 `shared`。
    init(appSupportDirectory: URL? = nil) {
        if let appSupportDirectory {
            appSupportDir = appSupportDirectory
        } else {
            let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            appSupportDir = paths.appendingPathComponent("embyExternalUrl-Manager", isDirectory: true)
        }
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

    /// 只把指定字段写入磁盘，不连带保存其它页面尚未保存的修改。
    /// 内存中的 `config` 同步应用同样的修改，`isDirty` 仍反映其余未保存内容。
    @discardableResult
    func persistPartial(_ mutate: (inout AppConfig) -> Void) -> Bool {
        lastPersistenceError = nil
        var onDisk = lastSavedConfig
        mutate(&onDisk)
        do {
            try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            try JSONEncoder().encode(onDisk).write(to: configFileURL, options: .atomic)
        } catch {
            lastPersistenceError = "保存失败：\(error.localizedDescription)"
            return false
        }
        lastSavedConfig = onDisk
        lastSavedAt = Date()
        var inMemory = config
        mutate(&inMemory)
        config = inMemory
        isDirty = (config != lastSavedConfig)
        return true
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

    /// 部署目录路径（纯计算，不创建目录；界面渲染 / 状态检查使用）。
    func deploymentDirectoryPath() -> String {
        let custom = config.deploymentDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return appSupportDir.appendingPathComponent(config.mediaServerType.deploymentSubfolder).path
    }

    /// 部署目录路径，并确保 logs / cache / acme-webroot 子目录存在（执行动作前使用）。
    func ensureDeploymentDirectory() -> String {
        let dir = deploymentDirectoryPath()
        for sub in ["", "/logs", "/cache", "/acme-webroot"] {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir + sub), withIntermediateDirectories: true)
        }
        return dir
    }

    /// nginx 配置目录路径（纯计算，不创建目录）。
    func nginxConfigDirectory() -> String {
        let custom = config.nginxConfigDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return deploymentDirectoryPath() + "/nginx"
    }

    // MARK: - Certificate Directory

    /// nginx 容器只读取 `<nginx 目录>/conf.d/cert`（https.conf 固定引用 /etc/nginx/conf.d/cert）。
    func nginxCertificateDirectory() -> String {
        nginxConfigDirectory() + "/conf.d/cert"
    }

    /// 证书页管理的目录；未单独设置时就是 nginx 读取的目录。
    func effectiveCertificateDirectory() -> String {
        let custom = config.certificateDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? nginxCertificateDirectory() : custom
    }

    /// 与 nginx 目录相同则不单独记录，避免 nginx 目录变化后残留旧的绝对路径。
    func normalizedCertificateDirectory(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let a = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        let b = URL(fileURLWithPath: nginxCertificateDirectory()).standardizedFileURL.path
        return a == b ? nil : trimmed
    }

    /// 自定义证书目录不在 nginx 挂载范围内，容器读不到；把证书与私钥同步到 nginx 目录。
    private func syncCertificatesToNginx(written: inout [String], warnings: inout [String]) {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: effectiveCertificateDirectory(), isDirectory: true)
        let target = URL(fileURLWithPath: nginxCertificateDirectory(), isDirectory: true)
        guard source.standardizedFileURL.path != target.standardizedFileURL.path else { return }

        func first(_ names: [String]) -> URL? {
            names.map { source.appendingPathComponent($0) }.first { fm.fileExists(atPath: $0.path) }
        }
        guard let cert = first(["fullchain.pem", "cert.pem"]),
              let key = first(["privkey.key", "key.pem"]) else {
            warnings.append("证书目录 \(source.path) 中未找到 fullchain.pem / privkey.key，未同步到 nginx 目录。")
            return
        }
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for (src, name, mode) in [(cert, "fullchain.pem", 0o644), (key, "privkey.key", 0o600)] {
                let dest = target.appendingPathComponent(name)
                if fm.fileExists(atPath: dest.path), fm.contentsEqual(atPath: src.path, andPath: dest.path) { continue }
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: src, to: dest)
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: dest.path)
                written.append(dest.path)
            }
        } catch {
            warnings.append("同步证书到 nginx 目录失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Generate Deployment Files

    /// Generates deployment files. **Always persists dirty config first** so disk and generate stay aligned.
    @MainActor
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
            self.lastReport = report
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
        // Path mappings — keep hand-written entries Manager does not model (only when same server family)
        let family = Self.skeletonFamily(for: config.mediaServerType)
        let existingFamily = Self.existingFamily(nginxDir: nginxDir)
        let canPreserve = existingFamily == nil || existingFamily == family
        let existingPro = (try? String(contentsOfFile: nginxConfigDir + "/constant-pro.js", encoding: .utf8)) ?? ""
        let foreignMappings = canPreserve ? ConfigPreserver.foreignPathMappingElements(in: existingPro) : []
        let enabledMappings = config.pathMappings.filter { $0.enabled && !$0.localPrefix.isEmpty && !$0.remotePrefix.isEmpty }
        variables["MEDIA_PATH_MAPPING"] = mediaPathMappingJS(enabledMappings, extras: foreignMappings)
        var notes: [String] = []
        if !foreignMappings.isEmpty {
            notes.append("mediaPathMapping：保留了 \(foreignMappings.count) 条手写映射")
        }
        if !canPreserve {
            warnings.append("检测到骨架由 \(existingFamily ?? "") 切换为 \(family)：旧类型的自定义规则（routeRule 等）未沿用，旧文件已备份。")
        }
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

        // ACME webroot 验证：nginx 把 /.well-known/acme-challenge/ 指向挂载进容器的 acme-webroot
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: nginxConfDir + "/custome/location"), withIntermediateDirectories: true
        )
        templates.append((
            "acme-challenge.conf", "acme-challenge.conf",
            URL(fileURLWithPath: nginxConfDir + "/custome/location/acme-challenge.conf"), false
        ))

        if let existingCompose = try? String(contentsOf: composeURL, encoding: .utf8) {
            if Self.composeMatches(
                existingCompose,
                container: config.mediaServerType.containerName,
                nginxDir: nginxDir,
                deployDir: deployDir
            ) {
                // 容器名与挂载路径一致：保留用户对 compose 的其它自定义
                if !existingCompose.contains("/usr/share/nginx/acme-webroot") {
                    warnings.append("docker-compose.yml 没有 acme-webroot 挂载；要使用 Webroot 方式签发证书，请删除该文件后重新生成（旧文件会先备份）。")
                }
            } else {
                templates.append(("docker-compose.yml", "docker-compose.yml", composeURL, false))
                warnings.append("docker-compose.yml 的容器名或挂载路径与当前设置不一致，已备份旧文件并重新生成；运行中的容器需在「容器管理」重新启动才会应用。")
            }
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

            var finalContent = rendered
            if canPreserve,
               let existing = try? String(contentsOf: destURL, encoding: .utf8) {
                let merged = ConfigPreserver.merge(rendered: rendered, existing: existing, templateName: templateName)
                finalContent = merged.content
                if !merged.preserved.isEmpty {
                    notes.append("\(name)：保留了 \(merged.preserved.joined(separator: "、"))")
                }
            }

            do {
                _ = try renderer.writeRendered(content: finalContent, to: destURL, backupDir: backupDir)
                writtenFiles.append(destURL.path)
            } catch {
                errors.append("Failed to write \(name): \(error.localizedDescription)")
            }
        }

        // 自定义证书目录 → 同步到 nginx 实际读取的目录，再按证书是否存在启停 HTTPS
        syncCertificatesToNginx(written: &writtenFiles, warnings: &warnings)
        let reconcile = NginxConfReconciler.reconcile(
            nginxDir: nginxDir,
            type: config.mediaServerType,
            hasCerts: NginxConfReconciler.hasCertificates(nginxDir: nginxDir)
        )
        writtenFiles.append(contentsOf: reconcile.changed)
        errors.append(contentsOf: reconcile.errors)
        let activeConfName = config.mediaServerType.nginxConfName
        let activeConfURL = URL(fileURLWithPath: nginxConfDir).appendingPathComponent(activeConfName)

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
            warnings: warnings,
            notes: notes
        )

        self.lastReport = report
        return report
    }

    // MARK: - Helpers

    private func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return str.replacingOccurrences(of: "\\/", with: "/")
    }

    private func jsonArray(_ values: [String]) -> String {
        let values = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return str.replacingOccurrences(of: "\\/", with: "/")
    }

    private func yamlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Manager 管理的条目用 `[0, 0, "本地", "远端"]` 单行格式（上游格式，也便于「扫描已有配置」读回）；
    /// `extras` 是用户手写的其它格式条目，原样追加。
    private func mediaPathMappingJS(_ mappings: [PathMapping], extras: [String] = []) -> String {
        let rows = mappings.map { "[0, 0, \(jsonString($0.localPrefix)), \(jsonString($0.remotePrefix))]" } + extras
        guard !rows.isEmpty else { return "[]" }
        return "[\n  " + rows.joined(separator: ",\n  ") + "\n]"
    }

    /// plex 与 emby/jellyfin 使用两套不同的上游骨架。
    static func skeletonFamily(for type: MediaServerType) -> String {
        type == .plex ? "plex" : "emby"
    }

    /// 已生成的 constant.js 属于哪种骨架；读不出时回退到同步写入的类型标记。
    static func existingFamily(nginxDir: String) -> String? {
        if let text = try? String(contentsOfFile: nginxDir + "/conf.d/constant.js", encoding: .utf8) {
            if text.contains("plexHost") { return "plex" }
            if text.contains("embyHost") { return "emby" }
        }
        if let marker = try? String(contentsOfFile: nginxDir + "/.manager-skeleton-type", encoding: .utf8) {
            let kind = marker.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == "plex" || kind == "emby" { return kind }
        }
        return nil
    }

    /// compose 中的容器名与四个挂载源是否仍与当前设置一致（忽略引号差异）。
    static func composeMatches(_ text: String, container: String, nginxDir: String, deployDir: String) -> Bool {
        let flat = text.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        return [
            "container_name: \(container)",
            "\(nginxDir)/nginx.conf:/etc/nginx/nginx.conf",
            "\(nginxDir)/conf.d:/etc/nginx/conf.d",
            "\(deployDir)/logs:/var/log/nginx",
            "\(deployDir)/cache:/var/cache/nginx"
        ].allSatisfy { flat.contains($0) }
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

// MARK: - Nginx conf reconciler

/// 让 nginx 只加载当前媒体类型的 conf，并按证书是否存在启停 HTTPS include。
/// 「生成」与「上游同步」共用，避免同步后 plex.conf / emby.conf 同时生效。
enum NginxConfReconciler {

    static func hasCertificates(nginxDir: String) -> Bool {
        let fm = FileManager.default
        let dir = nginxDir + "/conf.d/cert"
        return fm.fileExists(atPath: dir + "/fullchain.pem") && fm.fileExists(atPath: dir + "/privkey.key")
    }

    static func reconcile(
        nginxDir: String,
        type: MediaServerType,
        hasCerts: Bool
    ) -> (changed: [String], errors: [String]) {
        let fm = FileManager.default
        let confDir = URL(fileURLWithPath: nginxDir).appendingPathComponent("conf.d")
        var changed: [String] = []
        var errors: [String] = []

        let activeName = type.nginxConfName
        let inactiveName = type == .plex ? "emby.conf" : "plex.conf"
        let active = confDir.appendingPathComponent(activeName)
        let activeDisabled = confDir.appendingPathComponent("\(activeName).disabled")
        let inactive = confDir.appendingPathComponent(inactiveName)

        if !fm.fileExists(atPath: active.path), fm.fileExists(atPath: activeDisabled.path) {
            try? fm.moveItem(at: activeDisabled, to: active)
        }
        if fm.fileExists(atPath: inactive.path) {
            let disabled = confDir.appendingPathComponent("\(inactiveName).disabled")
            try? fm.removeItem(at: disabled)
            try? fm.moveItem(at: inactive, to: disabled)
        }

        let include = "include /etc/nginx/conf.d/includes/https.conf;"
        if let content = try? String(contentsOf: active, encoding: .utf8) {
            var updated = content
            if hasCerts {
                updated = updated.replacingOccurrences(of: "# " + include, with: include)
            } else {
                updated = updated.replacingOccurrences(of: include, with: "# " + include)
                updated = updated.replacingOccurrences(of: "# # " + include, with: "# " + include)
            }
            if updated != content {
                do {
                    try updated.write(to: active, atomically: true, encoding: .utf8)
                    changed.append(active.path)
                } catch {
                    errors.append("Failed to update \(activeName) SSL configuration: \(error.localizedDescription)")
                }
            }
        }
        return (changed, errors)
    }
}
