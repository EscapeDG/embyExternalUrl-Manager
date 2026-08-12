import SwiftUI
import AppKit

/// Media server connection configuration (Plex / Emby / Jellyfin) + OpenList + paths.
struct ConnectionView: View {
    @EnvironmentObject var configService: ConfigService
    @State private var showResetConfirm = false
    @State private var scanMessage: String?
    @State private var scanSuccess = false

    var body: some View {
        PageScaffold(title: "媒体服务器") {
            VStack(alignment: .leading, spacing: 24) {
                if let err = configService.lastPersistenceError, !configService.isDirty {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("媒体服务器类型", selection: $configService.config.mediaServerType) {
                            ForEach(MediaServerType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        MediaServerEditor()
                    }
                } label: {
                    Label("媒体服务器", systemImage: "cable.connector")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        FormField(label: "服务器地址") {
                            TextField("http://127.0.0.1:5244", text: $configService.config.openList.serverURL)
                        }
                        FormField(label: "Token") {
                            SecureField("输入 OpenList Token", text: $configService.config.openList.token)
                        }
                        FormField(label: "公网地址") {
                            VStack(alignment: .leading) {
                                TextField("留空则使用服务器地址", text: $configService.config.openList.publicURL)
                                Text("用于客户端自请求直链的场景，如 115 网盘需要公网可访问的地址")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    Label("OpenList 直链后端", systemImage: "link")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        FormField(label: "部署目录") {
                            VStack(alignment: .leading) {
                                HStack {
                                    TextField("默认: App Support 下自动创建", text: $configService.config.deploymentDirectory)
                                        .font(.system(.body, design: .monospaced))
                                    Button("选择") { selectFolder { configService.config.deploymentDirectory = $0 } }
                                        .buttonStyle(.bordered)
                                }
                                Text("存放 docker-compose.yml 和运行时日志的目录")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        FormField(label: "nginx 配置目录") {
                            VStack(alignment: .leading) {
                                HStack {
                                    TextField("默认: 部署目录下的 nginx/", text: $configService.config.nginxConfigDirectory)
                                        .font(.system(.body, design: .monospaced))
                                    Button("选择") { selectFolder { configService.config.nginxConfigDirectory = $0 } }
                                        .buttonStyle(.bordered)
                                    Button("扫描已有配置") { scanExistingConfig() }
                                        .buttonStyle(.borderedProminent)
                                }
                                Text("包含 nginx.conf 和 conf.d/ 的目录，配置生成时会覆盖 constant*.js")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let msg = scanMessage {
                            HStack(spacing: 6) {
                                Image(systemName: scanSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(scanSuccess ? .green : .orange)
                                    .font(.caption)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundColor(scanSuccess ? .green : .orange)
                            }
                            .padding(.leading, 4)
                        }
                    }
                } label: {
                    Label("路径设置", systemImage: "folder")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())
            }
        } footer: {
            ConfigSaveBar(showsReset: true) {
                showResetConfirm = true
            }
        }
        .confirmationDialog("恢复默认配置？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                _ = configService.resetToDefaults()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清空当前所有媒体服务器、OpenList、路径与证书相关设置，并立即写入磁盘。")
        }
    }

    // MARK: - Helpers

    private func selectFolder(_ completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }

    private func scanExistingConfig() {
        let nginxDir = configService.nginxConfigDirectory()
        let scanner = ExistingConfigScanner.shared
        let scanned = scanner.scan(nginxConfDir: nginxDir, preferredType: configService.config.mediaServerType)

        var filled: [String] = []

        if let type = scanned.mediaServerType {
            configService.config.mediaServerType = type
            filled.append("服务类型")

            let serverURL = scanned.serverURL ?? scanned.plexURL
            switch type {
            case .emby:
                if let v = serverURL { configService.config.emby.serverURL = v; filled.append("Emby 地址") }
                if let v = scanned.embyApiKey { configService.config.emby.apiKey = v; filled.append("API Key") }
                if let v = scanned.proxyPort { configService.config.emby.proxyPort = v; filled.append("HTTP 端口") }
                if let v = scanned.proxyHttpsPort { configService.config.emby.proxyHttpsPort = v; filled.append("HTTPS 端口") }
            case .jellyfin:
                if let v = serverURL { configService.config.jellyfin.serverURL = v; filled.append("Jellyfin 地址") }
                if let v = scanned.embyApiKey { configService.config.jellyfin.apiKey = v; filled.append("API Key") }
                if let v = scanned.proxyPort { configService.config.jellyfin.proxyPort = v; filled.append("HTTP 端口") }
                if let v = scanned.proxyHttpsPort { configService.config.jellyfin.proxyHttpsPort = v; filled.append("HTTPS 端口") }
            case .plex:
                if let v = serverURL { configService.config.plex.serverURL = v; filled.append("Plex 地址") }
                if let v = scanned.proxyPort { configService.config.plex.proxyPort = v; filled.append("HTTP 端口") }
                if let v = scanned.proxyHttpsPort { configService.config.plex.proxyHttpsPort = v; filled.append("HTTPS 端口") }
            }
        } else {
            if let v = scanned.serverURL ?? scanned.plexURL {
                switch configService.config.mediaServerType {
                case .emby:
                    configService.config.emby.serverURL = v
                    filled.append("Emby 地址")
                case .jellyfin:
                    configService.config.jellyfin.serverURL = v
                    filled.append("Jellyfin 地址")
                case .plex:
                    configService.config.plex.serverURL = v
                    filled.append("Plex 地址")
                }
            }
            if let v = scanned.proxyPort {
                switch configService.config.mediaServerType {
                case .emby: configService.config.emby.proxyPort = v
                case .jellyfin: configService.config.jellyfin.proxyPort = v
                case .plex: configService.config.plex.proxyPort = v
                }
                filled.append("HTTP 端口")
            }
            if let v = scanned.proxyHttpsPort {
                switch configService.config.mediaServerType {
                case .emby: configService.config.emby.proxyHttpsPort = v
                case .jellyfin: configService.config.jellyfin.proxyHttpsPort = v
                case .plex: configService.config.plex.proxyHttpsPort = v
                }
                filled.append("HTTPS 端口")
            }
        }

        if let v = scanned.openListURL { configService.config.openList.serverURL = v; filled.append("OpenList 地址") }
        if let v = scanned.openListToken { configService.config.openList.token = v; filled.append("OpenList Token") }
        if let v = scanned.openListPublicURL { configService.config.openList.publicURL = v; filled.append("公网地址") }
        if let v = scanned.signEnabled { configService.config.openList.signEnabled = v; filled.append("签名开关") }
        if let v = scanned.signExpireHours { configService.config.openList.signExpireHours = v; filled.append("签名有效期") }
        if let v = scanned.redirectEnabled { configService.config.redirect.enabled = v; filled.append("302 开关") }
        if let v = scanned.transcodeEnabled { configService.config.redirect.transcodeEnabled = v; filled.append("转码开关") }
        if let v = scanned.routeCacheEnabled { configService.config.redirect.routeCacheEnabled = v; filled.append("缓存开关") }
        if let v = scanned.fallbackUseOriginal { configService.config.redirect.fallbackUseOriginal = v; filled.append("回源策略") }

        if !scanned.mediaMountPaths.isEmpty {
            configService.config.mount.mediaMountPaths = scanned.mediaMountPaths
            filled.append("挂载路径")
        }

        if !scanned.pathMappings.isEmpty {
            configService.config.pathMappings = scanned.pathMappings.map {
                PathMapping(localPrefix: $0.local, remotePrefix: $0.remote, enabled: true)
            }
            filled.append("路径映射")
        }

        if filled.isEmpty {
            scanMessage = "在 \(nginxDir) 下未识别到有效配置"
            scanSuccess = false
        } else {
            if configService.save() {
                scanMessage = "已读取 \(filled.count) 项配置：\(filled.joined(separator: "、"))"
                scanSuccess = true
            } else {
                scanMessage = "已识别配置但保存失败：\(configService.lastPersistenceError ?? "无法写入配置文件。")"
                scanSuccess = false
            }
        }
    }
}
