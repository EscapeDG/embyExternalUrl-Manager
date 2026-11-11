import Foundation

// MARK: - Mounted nginx log reader

/// 上游 nginx.conf 把日志写到 `/var/log/nginx/error.log` / `access.log`。
/// compose 把该目录挂到宿主机后，镜像里指向 stdout/stderr 的软链接被覆盖，`docker logs` 读不到内容，
/// 这时改为直接读宿主机上的日志文件。
enum MountedLogReader {
    static let containerLogDirectory = "/var/log/nginx"

    /// 单个文件最多从末尾读取的字节数，避免一次读入很大的 access.log。
    static let maxTailBytes = 512 * 1024

    private struct Mount: Decodable {
        let Source: String?
        let Destination: String?
    }

    /// 从 `docker inspect -f '{{json .Mounts}}'` 的输出中找出 `/var/log/nginx` 对应的宿主机目录。
    static func hostLogDirectory(mountsJSON: String) -> String? {
        guard let data = mountsJSON.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let mounts = try? JSONDecoder().decode([Mount].self, from: data) else { return nil }
        let target = containerLogDirectory
        guard let source = mounts.first(where: { normalize($0.Destination) == target })?.Source,
              !source.isEmpty else { return nil }
        // Docker Desktop 有时以 /host_mnt 前缀报告宿主机路径
        let prefix = "/host_mnt/"
        if source.hasPrefix(prefix), !FileManager.default.fileExists(atPath: source) {
            return "/" + source.dropFirst(prefix.count)
        }
        return source
    }

    /// 目录下的 `*.log` 文件：error.log、access.log 优先，其余按名称排序（轮转后的 .log.1 / .gz 不读）。
    static func logFiles(in directory: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        let rank = ["error.log": 0, "access.log": 1]
        return names
            .filter { $0.hasSuffix(".log") }
            .sorted { (rank[$0] ?? 2, $0) < (rank[$1] ?? 2, $1) }
    }

    /// 读取文件末尾 `lines` 行；文件很大时只读最后 `maxBytes` 字节，丢弃开头可能不完整的一行。
    static func tail(path: String, lines: Int, maxBytes: Int = maxTailBytes) -> String? {
        guard lines > 0, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() ?? Data() else { return nil }

        var all = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
        if offset > 0, !all.isEmpty { all.removeFirst() }
        if all.last == "" { all.removeLast() }
        return all.suffix(lines).joined(separator: "\n")
    }

    /// 拼出各日志文件末尾内容；目录里没有日志文件时返回 nil。
    static func render(directory: String, lines: Int) -> String? {
        let sections = logFiles(in: directory).compactMap { name -> String? in
            guard let text = tail(path: directory + "/" + name, lines: lines) else { return nil }
            return "== \(name)（末 \(lines) 行）==\n" + (text.isEmpty ? "（空）" : text)
        }
        guard !sections.isEmpty else { return nil }
        return "docker logs 无输出，以下读取挂载目录 \(directory)\n\n" + sections.joined(separator: "\n\n")
    }

    private static func normalize(_ path: String?) -> String? {
        guard var path, !path.isEmpty else { return nil }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
