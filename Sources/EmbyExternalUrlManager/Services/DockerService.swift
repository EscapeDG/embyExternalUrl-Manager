import Foundation
import Darwin

// MARK: - Docker Service

final class DockerService: ObservableObject {
    static let shared = DockerService()

    @Published var isAvailable: Bool = false
    @Published var containerRunning: Bool = false
    @Published var containerStatus: String = ""
    @Published var lastCommandResult: CommandResult?
    @Published var isBusy: Bool = false

    private let processQueue = DispatchQueue(label: "docker.service")

    func detect() async {
        let result = await runCommand("/usr/bin/env", args: ["docker", "info", "--format", "{{.ServerVersion}}"], timeout: 8)
        await MainActor.run {
            isAvailable = result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func ps(mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> String {
        let candidates = mediaServerType.containerCandidates
        let filters = candidates.flatMap { ["--filter", "name=\($0)"] }
        let result = await runCommand("/usr/bin/env", args: ["docker", "ps", "-a"] + filters + ["--format", "{{.Names}}\t{{.Status}}"], timeout: 8)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // 解析容器名和状态
        let lines = output.split(separator: "\n").map(String.init)
        let containers = lines.map { line -> (name: String, status: String) in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
        }
        if let currentContainer = containers.first(where: { candidates.contains($0.name) }) {
            await MainActor.run {
                containerRunning = currentContainer.status.contains("Up")
                containerStatus = "\(currentContainer.name) — \(currentContainer.status)"
            }
            return currentContainer.status
        } else {
            await MainActor.run {
                containerRunning = false
                containerStatus = "未找到 \(mediaServerType.containerName) 容器"
            }
            return ""
        }
    }

    func up(directory: String) async -> CommandResult {
        guard await tryBeginBusy() else {
            return CommandResult(command: "docker compose up", exitCode: -1, stdout: "", stderr: "已有容器操作进行中")
        }
        defer { Task { await clearBusy() } }
        let result = await runCommand("/usr/bin/env", args: ["docker", "compose", "-f", "\(directory)/docker-compose.yml", "up", "-d"], timeout: 90)
        await MainActor.run { self.lastCommandResult = result }
        _ = await ps()
        return result
    }

    func down(directory: String) async -> CommandResult {
        guard await tryBeginBusy() else {
            return CommandResult(command: "docker compose down", exitCode: -1, stdout: "", stderr: "已有容器操作进行中")
        }
        defer { Task { await clearBusy() } }
        let result = await runCommand("/usr/bin/env", args: ["docker", "compose", "-f", "\(directory)/docker-compose.yml", "down"], timeout: 30)
        await MainActor.run { self.lastCommandResult = result }
        _ = await ps()
        return result
    }

    func restart(directory: String) async -> CommandResult {
        guard await tryBeginBusy() else {
            return CommandResult(command: "docker compose restart", exitCode: -1, stdout: "", stderr: "已有容器操作进行中")
        }
        defer { Task { await clearBusy() } }
        let result = await runCommand("/usr/bin/env", args: ["docker", "compose", "-f", "\(directory)/docker-compose.yml", "restart"], timeout: 30)
        await MainActor.run { self.lastCommandResult = result }
        _ = await ps()
        return result
    }

    private func tryBeginBusy() async -> Bool {
        await MainActor.run {
            if isBusy { return false }
            isBusy = true
            return true
        }
    }

    private func clearBusy() async {
        await MainActor.run { isBusy = false }
    }

    func logs(tail: Int = 100, mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> String {
        let container = findContainerName(mediaServerType: mediaServerType)
        guard !container.isEmpty else { return "未找到容器" }
        let result = await runCommand("/usr/bin/env", args: ["docker", "logs", "--tail", "\(tail)", container], timeout: 15)
        return result.stdout
    }

    func nginxTest(mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> CommandResult {
        let container = findContainerName(mediaServerType: mediaServerType)
        if container.isEmpty {
            return CommandResult(command: "nginx -t", exitCode: -1, stdout: "", stderr: "未找到 nginx 容器")
        }
        let result = await runCommand("/usr/bin/env", args: ["docker", "exec", container, "nginx", "-t"], timeout: 15)
        await MainActor.run { self.lastCommandResult = result }
        return result
    }

    func reloadNginx(mediaServerType: MediaServerType = ConfigService.shared.config.mediaServerType) async -> CommandResult {
        let container = findContainerName(mediaServerType: mediaServerType)
        if container.isEmpty {
            return CommandResult(command: "nginx -s reload", exitCode: -1, stdout: "", stderr: "未找到正在运行的 nginx 容器")
        }
        let result = await runCommand("/usr/bin/env", args: ["docker", "exec", container, "nginx", "-s", "reload"], timeout: 15)
        await MainActor.run { self.lastCommandResult = result }
        return result
    }

    func composeConfig(directory: String) async -> CommandResult {
        let result = await runCommand("/usr/bin/env", args: ["docker", "compose", "-f", "\(directory)/docker-compose.yml", "config"], timeout: 30)
        await MainActor.run { self.lastCommandResult = result }
        return result
    }

    // MARK: - Helper

    /// 查找当前媒体类型对应的正在运行的 nginx 容器。
    private func findContainerName(mediaServerType: MediaServerType) -> String {
        for name in mediaServerType.containerCandidates {
            let result = runCommandSync("/usr/bin/env", args: ["docker", "ps", "--filter", "name=\(name)", "--filter", "status=running", "--format", "{{.Names}}"], timeout: 8)
            let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let matched = out.split(separator: "\n").map(String.init).first(where: { $0 == name }) {
                return matched
            }
        }
        return ""
    }

    private func runCommandSync(_ command: String, args: [String], timeout: TimeInterval = 10) -> CommandResult {
        Self.execute(command: command, args: args, timeout: timeout)
    }

    private static func dockerEnvironment() -> [String: String] {
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dockerPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "\(home)/.orbstack/bin",
            "\(home)/.docker/bin"
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (dockerPaths + [existingPath]).joined(separator: ":")
        return env
    }

    /// 启动进程并并发排空 stdout/stderr，避免子进程因管道缓冲写满而阻塞。
    /// 返回 (exitCode, stdout, stderr, timedOut)；启动失败时 exitCode 为 nil。
    private static func execute(command: String, args: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.environment = dockerEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outData = NSMutableData()
        let errData = NSMutableData()
        let dataLock = NSLock()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            dataLock.lock()
            outData.append(chunk)
            dataLock.unlock()
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            dataLock.lock()
            errData.append(chunk)
            dataLock.unlock()
        }

        let commandLine = ([command] + args).joined(separator: " ")
        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(command: commandLine, exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let timedOut = Self.wait(for: process, timeout: timeout)
        if timedOut {
            Self.terminate(process)
        }
        process.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        // 进程退出后管道中可能仍有 handler 尚未派发的残余数据
        let outRemainder = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errRemainder = errPipe.fileHandleForReading.readDataToEndOfFile()
        dataLock.lock()
        outData.append(outRemainder)
        errData.append(errRemainder)
        let finalOut = outData as Data
        let finalErr = errData as Data
        dataLock.unlock()

        return CommandResult(
            command: commandLine,
            exitCode: timedOut ? -9 : process.terminationStatus,
            stdout: String(data: finalOut, encoding: .utf8) ?? "",
            stderr: timedOut ? "Command timed out after \(Int(timeout))s" : (String(data: finalErr, encoding: .utf8) ?? "")
        )
    }

    // MARK: - Process Runner

    private func runCommand(_ command: String, args: [String], timeout: TimeInterval = 30) async -> CommandResult {
        return await withCheckedContinuation { continuation in
            processQueue.async {
                continuation.resume(returning: Self.execute(command: command, args: args, timeout: timeout))
            }
        }
    }

    private static func wait(for process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return process.isRunning
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
