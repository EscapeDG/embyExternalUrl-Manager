import SwiftUI

// MARK: - Dashboard View

/// Landing page showing overall system health at a glance.
struct DashboardView: View {
    @EnvironmentObject var configService: ConfigService
    @StateObject private var dockerService = DockerService.shared
    @State private var lastDiagnostics: [DiagnosticResult] = []
    @State private var isDiagnosing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Page title
                Text("仪表盘")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                // 3 status cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    mediaServerCard
                    containerCard
                    certificateCard
                }

                // Quick action toolbar
                actionBar

                Divider()

                // Recent diagnostics
                recentDiagnosticsSection
            }
            .padding(24)
        }
        .onAppear {
            Task {
                await dockerService.detect()
                _ = await dockerService.ps(mediaServerType: configService.config.mediaServerType)
            }
        }
    }

    // MARK: - Media Server Card

    private var mediaServerCard: some View {
        cardContent {
            HStack(spacing: 8) {
                StatusDot(color: .green, isActive: true)
                Text(configService.config.mediaServerType.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                MetricBadge(configService.config.mediaServerType == .plex
                            ? "\(configService.config.plex.proxyPort):\(configService.config.plex.proxyHttpsPort)"
                            : "\(configService.config.emby.proxyPort):\(configService.config.emby.proxyHttpsPort)")
            }

            Divider()

            InfoRow(label: "地址", value: serverAddress)
            InfoRow(label: "HTTP", value: "\(httpPort)")
            InfoRow(label: "HTTPS", value: "\(httpsPort)")

            Spacer()

            Text("运行诊断检查连通性")
                .font(.caption2)
                .foregroundColor(.secondary)
        } label: {
            Label("媒体服务器", systemImage: "cable.connector")
        }
    }

    // MARK: - Container Card

    private var containerCard: some View {
        cardContent {
            HStack(spacing: 8) {
                StatusDot(color: dockerService.isAvailable ? .green : .red,
                          isActive: dockerService.isAvailable)
                Text("Docker 容器")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if dockerService.isAvailable {
                    MetricBadge(dockerService.containerRunning ? "运行中" : "已停止")
                }
            }

            Divider()

            InfoRow(label: "引擎", value: dockerService.isAvailable ? "🟢 可用" : "🔴 不可用")
            InfoRow(label: "容器", value: configService.config.mediaServerType.containerName)
            InfoRow(label: "状态", value: containerStatusDisplay)

            Spacer()

            Text(containerActionHint)
                .font(.caption2)
                .foregroundColor(.secondary)
        } label: {
            Label("容器状态", systemImage: "shippingbox")
        }
    }

    // MARK: - Certificate Card

    private var certificateCard: some View {
        cardContent {
            HStack(spacing: 8) {
                StatusDot(color: .orange, isActive: true)
                Text("证书")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                MetricBadge("待检查")
            }

            Divider()

            InfoRow(label: "目录", value: certificateDir)
            InfoRow(label: "域名", value: configService.config.certificateDomains.isEmpty ? "未配置" : configService.config.certificateDomains)
            InfoRow(label: "到期", value: "前往证书页查看")

            Spacer()

            Text("前往「证书」页配置")
                .font(.caption2)
                .foregroundColor(.secondary)
        } label: {
            Label("证书", systemImage: "lock.shield")
        }
    }

    // MARK: - Card Container (equal height)

    private func cardContent<C: View, L: View>(@ViewBuilder content: @escaping () -> C,
                                                @ViewBuilder label: @escaping () -> L) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } label: {
            label()
        }
        .groupBoxStyle(FormGroupBoxStyle())
        .frame(maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await runDiagnostics() }
            } label: {
                Label("运行诊断", systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDiagnosing)

            Button {
                Task { await dockerService.detect(); _ = await dockerService.ps() }
            } label: {
                Label("刷新状态", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isDiagnosing)

            Spacer()

            if isDiagnosing {
                ProgressView()
                    .scaleEffect(0.7)
                Text("诊断中…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Recent Diagnostics

    private var recentDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("诊断结果")
                .font(.title3)
                .fontWeight(.semibold)

            if lastDiagnostics.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("尚未运行诊断。点击「运行诊断」检查系统状态。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(lastDiagnostics) { result in
                        diagnosticRow(result)
                    }
                }
            }
        }
    }

    private func diagnosticRow(_ result: DiagnosticResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: result.level))
                .foregroundColor(color(for: result.level))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(result.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    private var serverAddress: String {
        switch configService.config.mediaServerType {
        case .plex: return configService.config.plex.serverURL
        case .emby: return configService.config.emby.serverURL
        case .jellyfin: return configService.config.jellyfin.serverURL
        }
    }

    private var httpPort: Int {
        switch configService.config.mediaServerType {
        case .plex: return configService.config.plex.proxyPort
        case .emby: return configService.config.emby.proxyPort
        case .jellyfin: return configService.config.jellyfin.proxyPort
        }
    }

    private var httpsPort: Int {
        switch configService.config.mediaServerType {
        case .plex: return configService.config.plex.proxyHttpsPort
        case .emby: return configService.config.emby.proxyHttpsPort
        case .jellyfin: return configService.config.jellyfin.proxyHttpsPort
        }
    }

    private var certificateDir: String {
        let nginxDir = configService.nginxConfigDirectory()
        return nginxDir.isEmpty ? "未配置" : nginxDir + "/conf.d/cert"
    }

    private var containerActionHint: String {
        if !dockerService.isAvailable { return "请安装 Docker 或 OrbStack" }
        if !dockerService.containerRunning { return "在「生成与部署」页启动容器" }
        return "容器运行正常"
    }

    private var containerStatusDisplay: String {
        if !dockerService.isAvailable {
            return "Docker 未运行"
        }
        if dockerService.containerRunning {
            return "🟢 运行中"
        }
        return dockerService.containerStatus.isEmpty ? "🔴 已停止" : "🔴 \(dockerService.containerStatus)"
    }

    private func runDiagnostics() async {
        isDiagnosing = true
        lastDiagnostics = []

        var results: [DiagnosticResult] = []

        // Test Docker
        await dockerService.detect()
        let containerStatus = await dockerService.ps(mediaServerType: configService.config.mediaServerType)
        results.append(DiagnosticResult(
            title: "Docker 引擎",
            message: dockerService.isAvailable ? "Docker 已安装且守护进程运行中" : "Docker 未安装或守护进程未启动",
            level: dockerService.isAvailable ? .info : .error,
            suggestion: dockerService.isAvailable ? nil : "请安装 Docker 或 OrbStack"
        ))

        // Test container
        if dockerService.isAvailable {
            results.append(DiagnosticResult(
                title: "\(configService.config.mediaServerType.rawValue) 容器",
                message: dockerService.containerRunning ? "容器运行中 (\(containerStatus))" : "容器未运行",
                level: dockerService.containerRunning ? .info : .warning,
                suggestion: dockerService.containerRunning ? nil : "请在「生成与部署」页启动容器"
            ))
        }

        // Test nginx config
        if dockerService.isAvailable && dockerService.containerRunning {
            let nginxResult = await dockerService.nginxTest(mediaServerType: configService.config.mediaServerType)
            results.append(DiagnosticResult(
                title: "Nginx 配置",
                message: nginxResult.exitCode == 0 ? "nginx -t 通过" : "nginx -t 失败",
                level: nginxResult.exitCode == 0 ? .info : .error,
                suggestion: nginxResult.exitCode == 0 ? nil : nginxResult.stderr
            ))
        }

        // Test deployment directory
        let deployDir = configService.ensureDeploymentDirectory()
        let hasCompose = FileManager.default.fileExists(atPath: deployDir + "/docker-compose.yml")
        results.append(DiagnosticResult(
            title: "部署目录",
            message: hasCompose ? "docker-compose.yml 已存在" : "尚未生成部署配置",
            level: hasCompose ? .info : .warning,
            suggestion: hasCompose ? nil : "请在「生成与部署」页生成配置"
        ))

        await MainActor.run {
            lastDiagnostics = results
            isDiagnosing = false
        }
    }

    private func icon(for level: DiagnosticResult.DiagnosticLevel) -> String {
        switch level {
        case .info: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for level: DiagnosticResult.DiagnosticLevel) -> Color {
        switch level {
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}


