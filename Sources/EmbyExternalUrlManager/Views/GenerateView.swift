import SwiftUI

struct GenerateView: View {
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var systemStatus: SystemStatusStore
    @StateObject private var dockerService = DockerService.shared

    @State private var isGenerating = false
    @State private var lastReport: DeploymentReport?
    @State private var composeResult: CommandResult?
    @State private var nginxTestResult: CommandResult?
    @State private var containerLogs: String = ""
    @State private var lifecycleResult: CommandResult?
    @State private var pipelineSteps: [PipelineStep] = []

    var body: some View {
        PageScaffold(title: "生成与部署") {
            VStack(alignment: .leading, spacing: 20) {
                // Full pipeline checklist
                PipelineChecklistView(steps: pipelineSteps, compact: false)

                if configService.isDirty {
                    Label("存在未保存更改：点击「生成配置」将自动保存后写入部署文件。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                // MARK: Generate Deployment
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("将当前配置渲染为 njs 配置文件（constant*.js）和 docker-compose.yml（若尚不存在），写入部署目录。")
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
                        HStack(spacing: 10) {
                            StatusDot(
                                color: systemStatus.dockerAvailable ? .green : .red,
                                isActive: systemStatus.dockerAvailable
                            )
                            Text(systemStatus.dockerAvailable
                                 ? (systemStatus.containerRunning
                                    ? "容器运行中 · \(systemStatus.containerStatus)"
                                    : "引擎可用 · 容器未运行")
                                 : "Docker 不可用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("刷新") {
                                Task {
                                    await systemStatus.refreshDocker(
                                        mediaServerType: configService.config.mediaServerType,
                                        force: true
                                    )
                                    reevaluate()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack(spacing: 12) {
                            Button("验证 Compose") {
                                Task { await validateCompose() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!systemStatus.dockerAvailable)

                            Button("启动") {
                                Task {
                                    lifecycleResult = await dockerService.up(
                                        directory: configService.ensureDeploymentDirectory()
                                    )
                                    await systemStatus.refreshDocker(
                                        mediaServerType: configService.config.mediaServerType,
                                        force: true
                                    )
                                    reevaluate()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!systemStatus.dockerAvailable || systemStatus.containerRunning || dockerService.isBusy)

                            Button("重启") {
                                Task {
                                    lifecycleResult = await dockerService.restart(
                                        directory: configService.ensureDeploymentDirectory()
                                    )
                                    await systemStatus.refreshDocker(
                                        mediaServerType: configService.config.mediaServerType,
                                        force: true
                                    )
                                    reevaluate()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!systemStatus.dockerAvailable || !systemStatus.containerRunning || dockerService.isBusy)

                            Button("停止") {
                                Task {
                                    lifecycleResult = await dockerService.down(
                                        directory: configService.ensureDeploymentDirectory()
                                    )
                                    await systemStatus.refreshDocker(
                                        mediaServerType: configService.config.mediaServerType,
                                        force: true
                                    )
                                    reevaluate()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!systemStatus.dockerAvailable || !systemStatus.containerRunning || dockerService.isBusy)

                            if dockerService.isBusy {
                                ProgressView().scaleEffect(0.7)
                                Text("容器操作进行中…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let lifecycleResult, lifecycleResult.exitCode != 0 {
                            CommandOutputView(title: "容器操作失败", result: lifecycleResult)
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
                        .disabled(!systemStatus.containerRunning)

                        if let result = nginxTestResult {
                            CommandOutputView(title: "nginx -t", result: result)
                        }
                    }
                } label: {
                    Label("Nginx 验证", systemImage: "checkmark.seal")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                // MARK: Container Logs (single scroll page — DisclosureGroup, no nested ScrollView)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("查看日志") {
                            Task {
                                containerLogs = await dockerService.logs(
                                    tail: 50,
                                    mediaServerType: configService.config.mediaServerType
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!systemStatus.containerRunning)

                        if !containerLogs.isEmpty {
                            DisclosureGroup("日志输出") {
                                Text(containerLogs)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.04))
                                    .cornerRadius(6)
                            }
                        }
                    }
                } label: {
                    Label("容器日志", systemImage: "text.alignleft")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())
            }
        }
        .onAppear { reevaluate() }
        .onChange(of: configService.isDirty) { _, _ in reevaluate() }
        .onChange(of: systemStatus.containerStatus) { _, _ in reevaluate() }
        .onChange(of: configService.config.mediaServerType) { _, newType in
            composeResult = nil
            nginxTestResult = nil
            containerLogs = ""
            Task {
                await systemStatus.refreshDocker(mediaServerType: newType, force: true)
                reevaluate()
            }
        }
    }

    private func reevaluate() {
        pipelineSteps = DeploymentPipeline.evaluate(configService: configService, status: systemStatus)
    }

    // MARK: - Actions

    private func generate() {
        isGenerating = true
        Task {
            let report = await configService.generateDeployment()
            await MainActor.run {
                lastReport = report
                isGenerating = false
                reevaluate()
            }
            await systemStatus.refreshAll(configService: configService, force: true)
            await MainActor.run { reevaluate() }
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

    private func reportSummary(_ report: DeploymentReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.errors.isEmpty {
                Label(report.warnings.isEmpty ? "配置生成成功" : "配置已生成（有警告）",
                      systemImage: report.warnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(report.warnings.isEmpty ? .green : .orange)
            } else {
                Label("生成失败", systemImage: "xmark.circle.fill").foregroundColor(.red)
            }
            Text("目录: \(report.targetDirectory)").font(.caption).foregroundColor(.secondary)
            ForEach(report.filesWritten, id: \.self) { file in
                Text("✓ \(URL(fileURLWithPath: file).lastPathComponent)").font(.caption).foregroundColor(.secondary)
            }
            ForEach(report.warnings, id: \.self) { warning in
                Text("⚠ \(warning)").font(.caption).foregroundColor(.orange)
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
