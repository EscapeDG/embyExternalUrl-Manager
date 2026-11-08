import Foundation

// MARK: - Docker Service

/// Docker CLI 的无状态封装。容器 / 引擎状态由 `SystemStatusStore` 唯一持有，这里只返回结果。
final class DockerService: ObservableObject {
    static let shared = DockerService()

    struct ContainerState: Equatable {
        var running: Bool
        var status: String
    }

    enum Lifecycle {
        case start, stop, restart

        var title: String {
            switch self {
            case .start: return "启动"
            case .stop: return "停止"
            case .restart: return "重启"
            }
        }
    }

    @Published var lastCommandResult: CommandResult?
    @Published var isBusy: Bool = false

    /// docker 命令串行执行，避免 compose 操作与状态查询交叉。
    private let processQueue = DispatchQueue(label: "docker.service")

    // MARK: - Status

    /// Docker 引擎是否可用。
    func detect() async -> Bool {
        let result = await runCommand(["info", "--format", "{{.ServerVersion}}"], timeout: 8)
        return result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 当前媒体类型对应的 nginx 容器状态；找不到容器时 `running == false`。
    func containerState(mediaServerType: MediaServerType) async -> ContainerState {
        let candidates = mediaServerType.containerCandidates
        let filters = candidates.flatMap { ["--filter", "name=\($0)"] }
        let result = await runCommand(["ps", "-a"] + filters + ["--format", "{{.Names}}\t{{.Status}}"], timeout: 8)
        let containers = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map { line -> (name: String, status: String) in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
            }
        guard let current = containers.first(where: { candidates.contains($0.name) }) else {
            return ContainerState(running: false, status: "未找到 \(mediaServerType.containerName) 容器")
        }
        return ContainerState(running: current.status.hasPrefix("Up"), status: "\(current.name) — \(current.status)")
    }

    // MARK: - Lifecycle

    /// 启动 / 停止 / 重启 compose 服务。带忙碌保护，并先检查 compose 文件是否存在。
    /// 「停止」使用 `compose stop`（保留容器，随时可再启动），而不是 `down`。
    func lifecycle(_ operation: Lifecycle, directory: String) async -> CommandResult {
        let compose = "\(directory)/docker-compose.yml"
        guard FileManager.default.fileExists(atPath: compose) else {
            return CommandResult(command: "docker compose", exitCode: -1, stdout: "",
                                 stderr: "缺少 docker-compose.yml，请先在「生成与部署」页生成部署配置。")
        }
        guard await tryBeginBusy() else {
            return CommandResult(command: "docker compose", exitCode: -1, stdout: "", stderr: "已有容器操作进行中")
        }
        let result: CommandResult
        switch operation {
        case .start: result = await runCommand(["compose", "-f", compose, "up", "-d"], timeout: 90)
        case .stop: result = await runCommand(["compose", "-f", compose, "stop"], timeout: 30)
        case .restart: result = await runCommand(["compose", "-f", compose, "restart"], timeout: 30)
        }
        await MainActor.run {
            self.lastCommandResult = result
            self.isBusy = false
        }
        return result
    }

    private func tryBeginBusy() async -> Bool {
        await MainActor.run {
            if isBusy { return false }
            isBusy = true
            return true
        }
    }

    // MARK: - Inspect / nginx

    func logs(tail: Int = 100, mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> String {
        guard let container = await runningContainerName(mediaServerType: mediaServerType) else { return "未找到容器" }
        let result = await runCommand(["logs", "--tail", "\(tail)", container], timeout: 15)
        // nginx 把访问日志写 stdout、错误日志写 stderr，docker logs 分开返回
        return [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func nginxTest(mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> CommandResult {
        guard let container = await runningContainerName(mediaServerType: mediaServerType) else {
            return CommandResult(command: "nginx -t", exitCode: -1, stdout: "", stderr: "未找到正在运行的 nginx 容器")
        }
        let result = await runCommand(["exec", container, "nginx", "-t"], timeout: 15)
        await MainActor.run { self.lastCommandResult = result }
        return result
    }

    func reloadNginx(mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> CommandResult {
        guard let container = await runningContainerName(mediaServerType: mediaServerType) else {
            return CommandResult(command: "nginx -s reload", exitCode: -1, stdout: "", stderr: "未找到正在运行的 nginx 容器")
        }
        let result = await runCommand(["exec", container, "nginx", "-s", "reload"], timeout: 15)
        await MainActor.run { self.lastCommandResult = result }
        return result
    }

    /// 先 `nginx -t`，通过后再重载；配置有误时不重载，避免把正在运行的 nginx 搞挂。
    func testAndReloadNginx(mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> CommandResult {
        let test = await nginxTest(mediaServerType: mediaServerType)
        guard test.exitCode == 0 else { return test }
        return await reloadNginx(mediaServerType: mediaServerType)
    }

    func composeConfig(directory: String) async -> CommandResult {
        let result = await runCommand(["compose", "-f", "\(directory)/docker-compose.yml", "config"], timeout: 30)
        await MainActor.run { self.lastCommandResult = result }
        return result
    }

    // MARK: - Helpers

    /// 当前媒体类型对应的、正在运行的 nginx 容器名。
    private func runningContainerName(mediaServerType: MediaServerType) async -> String? {
        for name in mediaServerType.containerCandidates {
            let result = await runCommand(
                ["ps", "--filter", "name=\(name)", "--filter", "status=running", "--format", "{{.Names}}"],
                timeout: 8
            )
            let names = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").map(String.init)
            if let matched = names.first(where: { $0 == name }) { return matched }
        }
        return nil
    }

    private func runCommand(_ dockerArgs: [String], timeout: TimeInterval) async -> CommandResult {
        await withCheckedContinuation { continuation in
            processQueue.async {
                continuation.resume(returning: ProcessRunner.run(
                    "/usr/bin/env",
                    args: ["docker"] + dockerArgs,
                    timeout: timeout
                ))
            }
        }
    }
}
