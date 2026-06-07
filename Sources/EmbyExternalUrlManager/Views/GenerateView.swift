import SwiftUI

struct GenerateView: View {
    @EnvironmentObject var configService: ConfigService
    @StateObject private var dockerService = DockerService.shared

    @State private var isGenerating = false
    @State private var lastReport: DeploymentReport?
    @State private var composeResult: CommandResult?
    @State private var nginxTestResult: CommandResult?
    @State private var containerLogs: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Docker Environment
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            StatusDot(color: dockerService.isAvailable ? .green : .red,
                                      isActive: dockerService.isAvailable)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Docker 守护进程")
                                    .fontWeight(.medium)
                                Text(dockerService.isAvailable
                                     ? "Docker 已安装且守护进程运行中"
                                     : "Docker 未安装或守护进程未启动")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 10) {
                            StatusDot(color: dockerService.containerRunning ? .green : .orange,
                                      isActive: dockerService.isAvailable)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(configService.config.mediaServerType.rawValue) 容器")
                                    .fontWeight(.medium)
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Button("刷新") {
                                Task { await dockerService.detect()
                                    _ = await dockerService.ps(mediaServerType: configService.config.mediaServerType) }
                            }
                            .buttonStyle(.bordered)
                            .help("重新检测 Docker Daemon 和容器状态")
                        }
                    }
                } label: {
                    Label("Docker 环境", systemImage: "shippingbox")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                // MARK: Generate Deployment
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("将当前配置渲染为 njs 配置文件（constant*.js）和 docker-compose.yml，写入部署目录。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button(action: generate) {
                                Label("生成配置", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating)

                            if isGenerating {
                                ProgressView().scaleEffect(0.7)
                            }
                        }

                        if let report = configService.lastReport ?? lastReport {
                            reportSummary(report)
                        }
                    }
                } label: {
                    Label("生成部署文件", systemImage: "gearshape.2")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                // MARK: Container Management
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button("验证 Compose") {
                                Task { await validateCompose() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!dockerService.isAvailable)

                            Button("启动") {
                                Task { await dockerService.up(directory: configService.ensureDeploymentDirectory()) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!dockerService.isAvailable || dockerService.containerRunning)

                            Button("重启") {
                                Task { await dockerService.restart(directory: configService.ensureDeploymentDirectory()) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!dockerService.isAvailable || !dockerService.containerRunning)

                            Button("停止") {
                                Task { await dockerService.down(directory: configService.ensureDeploymentDirectory()) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!dockerService.isAvailable || !dockerService.containerRunning)
                        }

                        if let result = composeResult {
                            CommandOutputView(title: "docker compose config", result: result)
                        }
                    }
                } label: {
                    Label("容器管理", systemImage: "play.rectangle")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                // MARK: Nginx Test
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("执行 nginx -t") {
                            Task { await runNginxTest() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!dockerService.containerRunning)

                        if let result = nginxTestResult {
                            CommandOutputView(title: "nginx -t", result: result)
                        }
                    }
                } label: {
                    Label("Nginx 验证", systemImage: "checkmark.seal")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                // MARK: Container Logs
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("查看日志") {
                            Task { containerLogs = await dockerService.logs(tail: 50, mediaServerType: configService.config.mediaServerType) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!dockerService.containerRunning)

                        if !containerLogs.isEmpty {
                            ScrollView([.vertical]) {
                                Text(containerLogs)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 300)
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(6)
                        }
                    }
                } label: {
                    Label("容器日志", systemImage: "text.alignleft")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("生成与部署")
        .onAppear {
            Task { await dockerService.detect()
                _ = await dockerService.ps(mediaServerType: configService.config.mediaServerType) }
        }
        .onChange(of: configService.config.mediaServerType) { _, newType in
            composeResult = nil
            nginxTestResult = nil
            containerLogs = ""
            Task { await dockerService.detect()
                _ = await dockerService.ps(mediaServerType: newType) }
        }
    }

    private var statusText: String {
        if !dockerService.isAvailable { return "无法检测 — Docker 未运行" }
        if dockerService.containerRunning { return dockerService.containerStatus }
        if dockerService.containerStatus.isEmpty || dockerService.containerStatus == "未找到容器" {
            return "未找到 \(configService.config.mediaServerType.containerName) 容器"
        }
        return dockerService.containerStatus
    }

    // MARK: - Actions

    private func generate() {
        isGenerating = true
        Task {
            let report = await configService.generateDeployment()
            await MainActor.run { lastReport = report; isGenerating = false }
        }
    }

    private func validateCompose() async {
        let result = await dockerService.composeConfig(directory: configService.ensureDeploymentDirectory())
        await MainActor.run { composeResult = result }
    }

    private func runNginxTest() async {
        let result = await dockerService.nginxTest(mediaServerType: configService.config.mediaServerType)
        await MainActor.run { nginxTestResult = result }
    }

    // MARK: - View Builders

    private func reportSummary(_ report: DeploymentReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.errors.isEmpty {
                Label("配置生成成功", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Label("生成失败", systemImage: "xmark.circle.fill").foregroundColor(.red)
            }
            Text("目录: \(report.targetDirectory)").font(.caption).foregroundColor(.secondary)
            ForEach(report.filesWritten, id: \.self) { file in
                Text("✓ \(URL(fileURLWithPath: file).lastPathComponent)").font(.caption).foregroundColor(.secondary)
            }
            ForEach(report.errors, id: \.self) { error in
                Text("✗ \(error)").font(.caption).foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
    }
}
