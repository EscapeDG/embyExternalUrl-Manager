import Foundation
import AppKit
import Darwin

// MARK: - Process runner

/// 所有外部命令（docker / openssl / acme.sh / git / Rust core …）统一从这里执行：
/// 并发排空 stdout / stderr 防止管道写满死锁，并带超时保护。
enum ProcessRunner {

    /// 常见 CLI 工具目录（Homebrew、OrbStack、Docker Desktop、acme.sh）。
    static func toolPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.orbstack/bin",
            "\(home)/.docker/bin",
            "\(home)/.acme.sh"
        ]
    }

    /// 继承当前环境，PATH 前面补上常见工具目录；`extra` 覆盖同名变量。
    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (toolPaths() + [existing]).joined(separator: ":")
        for (key, value) in extra { env[key] = value }
        return env
    }

    /// 同步执行。超时返回 exitCode -9。
    /// `displayArguments` 用于在 `CommandResult.command` 中展示（例如隐藏敏感参数）。
    static func run(
        _ command: String,
        args: [String],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil,
        displayArguments: [String]? = nil
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.environment = environment ?? Self.environment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outBuffer = LockedBuffer()
        let errBuffer = LockedBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { outBuffer.append(chunk) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { errBuffer.append(chunk) }
        }

        // 退出通知代替轮询：terminationHandler 在 run() 之前设置，避免错过很快结束的进程
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        let commandLine = Shell.displayLine([command] + (displayArguments ?? args))
        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(command: commandLine, exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut { terminate(process, exited: exited) }
        process.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        // 进程退出后管道里可能还有 handler 来不及派发的残余数据
        outBuffer.append(outPipe.fileHandleForReading.readDataToEndOfFile())
        errBuffer.append(errPipe.fileHandleForReading.readDataToEndOfFile())

        return CommandResult(
            command: commandLine,
            exitCode: timedOut ? -9 : process.terminationStatus,
            stdout: String(data: outBuffer.data, encoding: .utf8) ?? "",
            stderr: timedOut
                ? "Command timed out after \(Int(timeout))s"
                : (String(data: errBuffer.data, encoding: .utf8) ?? "")
        )
    }

    /// 在全局并发队列上执行，不阻塞调用方。
    static func runAsync(
        _ command: String,
        args: [String],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run(command, args: args, timeout: timeout, environment: environment))
            }
        }
    }

    // MARK: private

    private final class LockedBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        func append(_ chunk: Data) {
            lock.lock(); storage.append(chunk); lock.unlock()
        }
        var data: Data {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
    }

    /// 先 SIGTERM，2 秒内没退出再 SIGKILL。
    private static func terminate(_ process: Process, exited: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if exited.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

// MARK: - Shell helpers

enum Shell {
    /// 单引号转义，供拼接 shell 命令使用。
    static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// 仅在需要时加引号（含空白、引号或反斜杠），用于展示命令行。
    static func displayToken(_ token: String) -> String {
        token.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" || $0 == "\\" })
            ? quote(token)
            : token
    }

    static func displayLine(_ tokens: [String]) -> String {
        tokens.map(displayToken).joined(separator: " ")
    }

    /// 在「终端」App 中执行命令（需要交互 / 可见输出的安装类操作）。
    static func openInTerminal(_ command: String) -> CommandResult {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        return ProcessRunner.run("/usr/bin/osascript", args: ["-e", script], timeout: 15)
    }
}

// MARK: - Folder picker

enum FolderPicker {
    /// 弹出目录选择面板，返回所选路径；取消返回 nil。
    @MainActor
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    @MainActor
    static func choose(_ completion: (String) -> Void) {
        if let path = choose() { completion(path) }
    }
}
