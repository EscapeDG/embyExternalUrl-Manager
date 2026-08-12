import SwiftUI

// MARK: - Dashboard View

/// Landing page: lightweight cards + compact pipeline with deep links.
struct DashboardView: View {
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var systemStatus: SystemStatusStore
    @Environment(\.navigate) private var navigate
    @State private var lastDiagnostics: [DiagnosticResult] = []
    @State private var isDiagnosing = false
    @State private var pipelineSteps: [PipelineStep] = []

    var body: some View {
        PageScaffold(title: "仪表盘") {
            VStack(alignment: .leading, spacing: 20) {
                Text("仪表盘")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    mediaServerCard
                    containerCard
                    certificateCard
                }

                PipelineChecklistView(steps: pipelineSteps, compact: true)

                actionBar

                Divider()

                recentDiagnosticsSection
            }
        }
        .onAppear { reevaluate() }
        .onChange(of: configService.config) { _, _ in reevaluate() }
        .onChange(of: configService.isDirty) { _, _ in reevaluate() }
        .onChange(of: systemStatus.containerStatus) { _, _ in reevaluate() }
        .onChange(of: systemStatus.dockerAvailable) { _, _ in reevaluate() }
        .onChange(of: systemStatus.certificateSummary) { _, _ in reevaluate() }
    }

    private func reevaluate() {
        pipelineSteps = DeploymentPipeline.evaluate(configService: configService, status: systemStatus)
    }

    // MARK: - Cards

    private var mediaServerCard: some View {
        cardContent {
            HStack(spacing: 8) {
                StatusDot(color: .green, isActive: true)
                Text(configService.config.mediaServerType.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                MetricBadge("\(httpPort):\(httpsPort)")
            }

            Divider()

            InfoRow(label: "地址", value: serverAddress)
            InfoRow(label: "HTTP", value: "\(httpPort)")
            InfoRow(label: "HTTPS", value: "\(httpsPort)")

            Button("编辑连接") {
                navigate.wrappedValue = .mediaServer
            }
            .buttonStyle(.borderless)
            .font(.caption)
        } label: {
            Label("媒体服务器", systemImage: "cable.connector")
        }
    }

    private var containerCard: some View {
        cardContent {
            HStack(spacing: 8) {
                StatusDot(color: systemStatus.dockerAvailable ? .green : .red,
                          isActive: systemStatus.dockerAvailable)
                Text("Docker 容器")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if systemStatus.dockerAvailable {
                    MetricBadge(systemStatus.containerRunning ? "运行中" : "已停止")
                }
            }

            Divider()

            InfoRow(label: "引擎", value: systemStatus.dockerAvailable ? "🟢 可用" : "🔴 不可用")
            InfoRow(label: "容器", value: configService.config.mediaServerType.containerName)
            InfoRow(label: "状态", value: containerStatusDisplay)

            Button(systemStatus.dockerAvailable ? "生成与部署" : "Docker 环境") {
                navigate.wrappedValue = systemStatus.dockerAvailable ? .generate : .docker
            }
            .buttonStyle(.borderless)
            .font(.caption)
        } label: {
            Label("容器状态", systemImage: "shippingbox")
        }
    }

    private var certificateCard: some View {
        let summary = systemStatus.certificateSummary
        let levelColor: Color = {
            switch summary?.level {
            case .ok: return .green
            case .warning: return .orange
            case .error: return .red
            default: return .secondary
            }
        }()

        return cardContent {
            HStack(spacing: 8) {
                StatusDot(color: levelColor, isActive: summary != nil)
                Text("证书")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                MetricBadge(summary?.statusTitle ?? "未检查")
            }

            Divider()

            InfoRow(label: "目录", value: summary?.directory.isEmpty == false ? summary!.directory : certificateDir)
            InfoRow(label: "主题", value: {
                let s = summary?.subject ?? ""
                return s.isEmpty ? "—" : s
            }())
            InfoRow(label: "到期", value: {
                if let days = summary?.daysRemaining {
                    return summary?.isExpired == true ? "已过期" : "剩余 \(days) 天"
                }
                return summary?.statusTitle ?? "前往证书页查看"
            }())

            Button("打开证书页") {
                navigate.wrappedValue = .certificate
            }
            .buttonStyle(.borderless)
            .font(.caption)
        } label: {
            Label("证书", systemImage: "lock.shield")
        }
    }

    private func cardContent<C: View, L: View>(
        @ViewBuilder content: @escaping () -> C,
        @ViewBuilder label: @escaping () -> L
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } label: {
            label()
        }
        .groupBoxStyle(FormGroupBoxStyle())
    }

    // MARK: - Actions

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
                Task {
                    await systemStatus.refreshAll(configService: configService, force: true)
                    reevaluate()
                }
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
            if let suggestion = result.suggestion, suggestion.contains("生成") {
                Button("前往") { navigate.wrappedValue = .generate }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if let suggestion = result.suggestion, suggestion.contains("Docker") {
                Button("前往") { navigate.wrappedValue = .docker }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
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

    private var containerStatusDisplay: String {
        if !systemStatus.dockerAvailable {
            return "Docker 未运行"
        }
        if systemStatus.containerRunning {
            return "🟢 运行中"
        }
        return systemStatus.containerStatus.isEmpty ? "🔴 已停止" : "🔴 \(systemStatus.containerStatus)"
    }

    private func runDiagnostics() async {
        isDiagnosing = true
        lastDiagnostics = []

        await systemStatus.refreshAll(configService: configService, force: true)
        reevaluate()

        var results: [DiagnosticResult] = []

        results.append(DiagnosticResult(
            title: "Docker 引擎",
            message: systemStatus.dockerAvailable ? "Docker 已安装且守护进程运行中" : "Docker 未安装或守护进程未启动",
            level: systemStatus.dockerAvailable ? .info : .error,
            suggestion: systemStatus.dockerAvailable ? nil : "请安装 Docker 或 OrbStack"
        ))

        if systemStatus.dockerAvailable {
            results.append(DiagnosticResult(
                title: "\(configService.config.mediaServerType.rawValue) 容器",
                message: systemStatus.containerRunning ? "容器运行中 (\(systemStatus.containerStatus))" : "容器未运行",
                level: systemStatus.containerRunning ? .info : .warning,
                suggestion: systemStatus.containerRunning ? nil : "请在「生成与部署」页启动容器"
            ))
        }

        if systemStatus.dockerAvailable && systemStatus.containerRunning {
            let nginxResult = await DockerService.shared.nginxTest(mediaServerType: configService.config.mediaServerType)
            results.append(DiagnosticResult(
                title: "Nginx 配置",
                message: nginxResult.exitCode == 0 ? "nginx -t 通过" : "nginx -t 失败",
                level: nginxResult.exitCode == 0 ? .info : .error,
                suggestion: nginxResult.exitCode == 0 ? nil : nginxResult.stderr
            ))
        }

        let deployDir = configService.ensureDeploymentDirectory()
        let hasCompose = FileManager.default.fileExists(atPath: deployDir + "/docker-compose.yml")
        results.append(DiagnosticResult(
            title: "部署目录",
            message: hasCompose ? "docker-compose.yml 已存在" : "尚未生成部署配置",
            level: hasCompose ? .info : .warning,
            suggestion: hasCompose ? nil : "请在「生成与部署」页生成配置"
        ))

        if configService.isDirty {
            results.append(DiagnosticResult(
                title: "配置持久化",
                message: "存在未保存更改；生成时将自动保存",
                level: .warning,
                suggestion: nil
            ))
        }

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
