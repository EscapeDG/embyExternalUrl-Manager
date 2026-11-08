import Foundation

// MARK: - Template Renderer

final class TemplateRenderer {
    static let shared = TemplateRenderer()

    /// Replace `{{VARIABLE}}` placeholders in template text with values from `variables`.
    /// Returns (renderedText, unresolvedKeys).
    func render(template: String, variables: [String: String]) -> (String, [String]) {
        var result = template
        var unresolved: [String] = []

        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        // Check for any remaining placeholders
        let pattern = #"\{\{(\w+)\}\}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)
            for match in matches {
                if let r = Range(match.range(at: 1), in: result) {
                    unresolved.append(String(result[r]))
                }
            }
        }

        return (result, unresolved)
    }

    /// 每个目标文件最多保留的备份数量。
    static let maxBackupsPerFile = 5

    /// 原子写入。内容没变就不写、不备份；有变化时先备份旧文件，并只保留最近几份。
    @discardableResult
    func writeRendered(content: String, to url: URL, backupDir: String? = nil) throws -> String? {
        let fm = FileManager.default

        var backupPath: String?
        if fm.fileExists(atPath: url.path) {
            if let existing = try? String(contentsOf: url, encoding: .utf8), existing == content {
                return nil
            }
            if let backupDir = backupDir {
                try fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let tag = Self.stableTag(for: url.path)
                let prefix = "\(url.lastPathComponent)."
                let suffix = ".\(tag).bak"
                let backupURL = URL(fileURLWithPath: backupDir)
                    .appendingPathComponent("\(prefix)\(formatter.string(from: Date()))\(suffix)")
                try fm.copyItem(at: url, to: backupURL)
                backupPath = backupURL.path
                prune(directory: backupDir, prefix: prefix, suffix: suffix)
            }
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        return backupPath
    }

    /// 同名文件位于不同目录时区分备份；FNV-1a 跨启动稳定（`hashValue` 每次启动都会变）。
    private static func stableTag(for path: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16).prefix(8).description
    }

    private func prune(directory: String, prefix: String, suffix: String) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return }
        let mine = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.sorted()
        guard mine.count > Self.maxBackupsPerFile else { return }
        for name in mine.prefix(mine.count - Self.maxBackupsPerFile) {
            try? fm.removeItem(atPath: directory + "/" + name)
        }
    }
}
