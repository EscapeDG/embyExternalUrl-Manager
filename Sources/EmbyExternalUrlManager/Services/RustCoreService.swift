import Foundation

// MARK: - Rust Core Service

final class RustCoreService: @unchecked Sendable {
    static let shared = RustCoreService()

    enum DecodeResult<T> {
        case success(T)
        case failure(CommandResult)
    }

    /// 执行 Rust core。`environment` 用于传递敏感值（密码等），避免出现在命令行参数里。
    /// 默认关闭 git 的交互式凭据提示，并带超时，避免 clone / pull 卡死界面。
    func run(arguments: [String], timeout: TimeInterval = 60, environment: [String: String] = [:]) -> CommandResult {
        guard let executableURL = executableURL() else {
            return CommandResult(
                command: maskedCommand(arguments: arguments),
                exitCode: -1,
                stdout: "",
                stderr: "未找到 Rust core 可执行文件 plex2alist-core。请重新构建或重新安装应用。"
            )
        }
        var extra = ["GIT_TERMINAL_PROMPT": "0"]
        for (key, value) in environment { extra[key] = value }
        return ProcessRunner.run(
            executableURL.path,
            args: arguments,
            timeout: timeout,
            environment: ProcessRunner.environment(extra: extra),
            displayArguments: masked(arguments: arguments)
        )
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        arguments: [String],
        timeout: TimeInterval = 60,
        environment: [String: String] = [:]
    ) -> DecodeResult<T> {
        let result = run(arguments: arguments, timeout: timeout, environment: environment)
        guard let data = result.stdout.data(using: .utf8), !data.isEmpty else {
            return .failure(result)
        }

        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failure(CommandResult(
                command: result.command,
                exitCode: result.exitCode == 0 ? -1 : result.exitCode,
                stdout: result.stdout,
                stderr: [result.stderr, "Rust core 输出解析失败：\(error.localizedDescription)"]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            ))
        }
    }

    private func executableURL() -> URL? {
        let fm = FileManager.default
        let candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/plex2alist-core"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("plex2alist-core"),
            URL(fileURLWithPath: fm.currentDirectoryPath)
                .appendingPathComponent("RustCore/target/release/plex2alist-core"),
            URL(fileURLWithPath: fm.currentDirectoryPath)
                .appendingPathComponent("RustCore/target/debug/plex2alist-core")
        ].compactMap { $0 }

        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    private func maskedCommand(executablePath: String = "plex2alist-core", arguments: [String]) -> String {
        ([executablePath] + masked(arguments: arguments))
            .map(displayToken)
            .joined(separator: " ")
    }

    private func masked(arguments: [String]) -> [String] {
        var output = arguments
        for index in output.indices {
            if index > 0 {
                let previous = output[output.index(before: index)]
                if previous == "--pfx-password" || previous == "--key-password" {
                    output[index] = "******"
                }
            }
        }
        return output
    }

    private func displayToken(_ token: String) -> String {
        if token.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            || token.contains("'")
            || token.contains("\"")
            || token.contains("\\") {
            return "'\(token.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return token
    }
}
