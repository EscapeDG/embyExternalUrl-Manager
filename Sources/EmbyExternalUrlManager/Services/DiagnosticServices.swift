import Foundation

// MARK: - OpenList Service

final class OpenListService: ObservableObject {
    static let shared = OpenListService()

    /// OpenList / AList 的业务错误放在响应体的 `code` 字段里（HTTP 状态仍是 200）。
    private struct APIEnvelope {
        let code: Int?
        let message: String
        let data: [String: Any]?

        init(_ data: Data) {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            code = object?["code"] as? Int
            message = object?["message"] as? String ?? ""
            self.data = object?["data"] as? [String: Any]
        }
    }

    /// 连通性 → Token 认证 → 目录列表读取。任一步失败即停止并给出原因。
    func runAllTests(config: AppConfig) async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        let baseURL = config.openList.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = config.openList.token.trimmingCharacters(in: .whitespacesAndNewlines)

        let pingResult = await testPing(baseURL: baseURL)
        results.append(pingResult)
        guard pingResult.level == .info else { return results }

        let authResult = await testAuth(baseURL: baseURL, token: token)
        results.append(authResult)
        guard authResult.level == .info else { return results }

        results.append(await testFileList(baseURL: baseURL, token: token))
        return results
    }

    func testPing(baseURL: String) async -> DiagnosticResult {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else {
            return DiagnosticResult(title: "OpenList 地址无效", message: "无法解析 URL: \(baseURL)", level: .error, suggestion: "请检查 OpenList 地址格式，例如 http://127.0.0.1:5244")
        }

        var lastStatus: Int?
        for path in ["ping", "api/public/settings"] {
            var request = URLRequest(url: url.appendingPathComponent(path))
            request.timeoutInterval = 10
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if (200..<300).contains(http.statusCode) {
                        return DiagnosticResult(title: "OpenList 连通", message: "/\(path) → \(http.statusCode)", level: .info, suggestion: nil)
                    }
                    lastStatus = http.statusCode
                }
            } catch {
                return DiagnosticResult(title: "OpenList 不可达", message: error.localizedDescription, level: .error, suggestion: "检查网络连接和 OpenList 服务状态")
            }
        }
        return DiagnosticResult(title: "OpenList 无响应", message: "ping 与 api/public/settings 均未返回 2xx\(lastStatus.map { "（最后 HTTP \($0)）" } ?? "")", level: .warning, suggestion: "确认 OpenList 服务已启动且地址正确")
    }

    func testAuth(baseURL: String, token: String) async -> DiagnosticResult {
        guard !token.isEmpty else {
            return DiagnosticResult(title: "OpenList Token 未配置", message: "Token 为空", level: .warning, suggestion: "请在「媒体服务器」页配置 OpenList Token")
        }
        guard let url = URL(string: baseURL)?.appendingPathComponent("api/me") else {
            return DiagnosticResult(title: "OpenList 地址无效", message: "无法解析 URL", level: .error, suggestion: nil)
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return DiagnosticResult(title: "OpenList 认证测试失败", message: "无 HTTP 响应", level: .error, suggestion: nil)
            }
            guard http.statusCode == 200 else {
                return DiagnosticResult(title: "OpenList 认证失败", message: "/api/me → HTTP \(http.statusCode)", level: .error, suggestion: "检查 Token 是否正确")
            }
            let envelope = APIEnvelope(data)
            guard envelope.code == 200 else {
                return DiagnosticResult(title: "OpenList Token 无效", message: "/api/me → code \(envelope.code.map(String.init) ?? "?") \(envelope.message)", level: .error, suggestion: "在 OpenList 后台「设置 → 其他」或个人资料中重新获取 Token")
            }
            let username = envelope.data?["username"] as? String ?? ""
            if username == "guest" {
                return DiagnosticResult(title: "OpenList Token 被识别为访客", message: "/api/me 返回用户 guest", level: .warning, suggestion: "Token 可能已失效，请重新获取")
            }
            return DiagnosticResult(title: "OpenList 认证通过", message: "用户 \(username.isEmpty ? "-" : username)", level: .info, suggestion: nil)
        } catch {
            return DiagnosticResult(title: "OpenList 认证测试异常", message: error.localizedDescription, level: .error, suggestion: "检查网络连接")
        }
    }

    /// 用 Token 列出根目录，确认账号能读取存储（302 直链依赖 fs/get，同样需要读权限）。
    func testFileList(baseURL: String, token: String) async -> DiagnosticResult {
        guard let url = URL(string: baseURL)?.appendingPathComponent("api/fs/list") else {
            return DiagnosticResult(title: "OpenList 地址无效", message: "无法解析 URL", level: .error, suggestion: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["path": "/", "password": "", "page": 1, "per_page": 1, "refresh": false])
        request.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let envelope = APIEnvelope(data)
            guard envelope.code == 200 else {
                return DiagnosticResult(title: "OpenList 目录读取失败", message: "/api/fs/list → code \(envelope.code.map(String.init) ?? "?") \(envelope.message)", level: .error, suggestion: "确认该账号对根目录有读取权限，且已添加存储")
            }
            let total = envelope.data?["total"] as? Int ?? 0
            if total == 0 {
                return DiagnosticResult(title: "OpenList 根目录为空", message: "/api/fs/list → 0 项", level: .warning, suggestion: "确认已在 OpenList 添加存储，且账号可见")
            }
            return DiagnosticResult(title: "OpenList 目录可读", message: "根目录共 \(total) 项", level: .info, suggestion: nil)
        } catch {
            return DiagnosticResult(title: "OpenList 目录读取异常", message: error.localizedDescription, level: .error, suggestion: "检查网络连接")
        }
    }
}

// MARK: - Plex Service

final class PlexService: ObservableObject {
    static let shared = PlexService()

    /// 测试 Plex 源服务器连通性。上游 plex2Alist 不要求预配置 Plex Token。
    func ping(serverURL: String) async -> DiagnosticResult {
        guard let url = URL(string: serverURL)?.appendingPathComponent("identity") else {
            return DiagnosticResult(title: "Plex 地址无效", message: "无法解析 URL: \(serverURL)", level: .error, suggestion: "检查 Plex 地址格式 (如 http://127.0.0.1:32400)")
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let name = parsePlexIdentity(data)
                    return DiagnosticResult(title: "Plex 服务器可达", message: "\(serverURL) → 200\(name.isEmpty ? "" : " (\(name))")", level: .info, suggestion: nil)
                } else {
                    return DiagnosticResult(title: "Plex 返回异常", message: "/identity → \(httpResponse.statusCode)", level: .error, suggestion: "确认 Plex 服务正在运行")
                }
            }
            return DiagnosticResult(title: "Plex 无响应", message: "无 HTTP 响应", level: .error, suggestion: "确认 Plex 服务正在运行")
        } catch {
            return DiagnosticResult(title: "Plex 不可达", message: error.localizedDescription, level: .error, suggestion: "确认 Plex 服务运行中且地址正确")
        }
    }

    private func parsePlexIdentity(_ data: Data) -> String {
        guard let xml = String(data: data, encoding: .utf8) else { return "" }
        if let range = xml.range(of: "friendlyName=\"") {
            let start = range.upperBound
            if let end = xml[start...].firstIndex(of: "\"") {
                return String(xml[start..<end])
            }
        }
        return ""
    }
}

// MARK: - Emby / Jellyfin Service

final class EmbyJellyfinService: ObservableObject {
    static let shared = EmbyJellyfinService()

    func ping(serverURL: String, serverType: MediaServerType) async -> DiagnosticResult {
        let serverName = serverType.rawValue
        guard let url = URL(string: serverURL)?.appendingPathComponent("System/Info/Public") else {
            return DiagnosticResult(title: "\(serverName) 地址无效", message: "无法解析 URL: \(serverURL)", level: .error, suggestion: "检查 \(serverName) 地址格式")
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if (200..<300).contains(httpResponse.statusCode) {
                    return DiagnosticResult(title: "\(serverName) 服务器可达", message: "\(serverURL) → \(httpResponse.statusCode)", level: .info, suggestion: nil)
                }
                return DiagnosticResult(title: "\(serverName) 返回异常", message: "/System/Info/Public → \(httpResponse.statusCode)", level: .error, suggestion: "确认 \(serverName) 服务正在运行")
            }
            return DiagnosticResult(title: "\(serverName) 无响应", message: "无 HTTP 响应", level: .error, suggestion: "确认 \(serverName) 服务正在运行")
        } catch {
            return DiagnosticResult(title: "\(serverName) 不可达", message: error.localizedDescription, level: .error, suggestion: "确认 \(serverName) 服务运行中且地址正确")
        }
    }

    func testAPIKey(serverURL: String, apiKey: String, serverType: MediaServerType) async -> DiagnosticResult {
        let serverName = serverType.rawValue
        guard !apiKey.isEmpty else {
            return DiagnosticResult(title: "\(serverName) API Key 未配置", message: "API Key 为空", level: .warning, suggestion: "请在连接设置中配置 \(serverName) API Key")
        }
        guard let url = URL(string: serverURL)?.appendingPathComponent("System/Info") else {
            return DiagnosticResult(title: "\(serverName) 地址无效", message: "无法解析 URL", level: .error, suggestion: nil)
        }

        do {
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-Emby-Token")
            request.setValue(apiKey, forHTTPHeaderField: "X-MediaBrowser-Token")
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if (200..<300).contains(httpResponse.statusCode) {
                    return DiagnosticResult(title: "\(serverName) API Key 可用", message: "/System/Info → \(httpResponse.statusCode)", level: .info, suggestion: nil)
                }
                return DiagnosticResult(title: "\(serverName) API Key 异常", message: "/System/Info → \(httpResponse.statusCode)", level: .error, suggestion: "检查 API Key 是否正确")
            }
            return DiagnosticResult(title: "\(serverName) API Key 测试失败", message: "无 HTTP 响应", level: .error, suggestion: nil)
        } catch {
            return DiagnosticResult(title: "\(serverName) API Key 测试异常", message: error.localizedDescription, level: .error, suggestion: "检查网络连接")
        }
    }
}
