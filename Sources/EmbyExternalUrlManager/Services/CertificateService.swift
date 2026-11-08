import Foundation

// MARK: - Certificate Service

final class CertificateService: @unchecked Sendable {
    static let shared = CertificateService()

    struct CertificateUpdateReport: Codable, Equatable {
        let certDirectory: String
        let filesWritten: [String]
        let backups: [String]
        let certificateInfo: String
        let commandResult: CommandResult

        var succeeded: Bool {
            commandResult.exitCode == 0
        }
    }

    struct CertificateInspection: Equatable {
        let certificatePath: String
        let subject: String
        let issuer: String
        let notBefore: Date?
        let notAfter: Date?
        let rawOutput: String
        let commandResult: CommandResult

        var daysRemaining: Int? {
            guard let notAfter else { return nil }
            return Calendar.current.dateComponents([.day], from: Date(), to: notAfter).day
        }

        var isExpired: Bool {
            guard let notAfter else { return false }
            return notAfter < Date()
        }
    }

    /// 证书剩余天数低于该值时提示“即将到期”（仪表盘与证书页共用）。
    static let warningDays = 30

    private let queue = DispatchQueue(label: "certificate.service")

    func updateCertificate(
        certificatePath: String,
        privateKeyPath: String,
        certDirectory: String,
        pfxPassword: String,
        privateKeyPassword: String
    ) async -> CertificateUpdateReport {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.updateCertificateSync(
                    certificatePath: certificatePath,
                    privateKeyPath: privateKeyPath,
                    certDirectory: certDirectory,
                    pfxPassword: pfxPassword,
                    privateKeyPassword: privateKeyPassword
                ))
            }
        }
    }

    func inspectCertificate(certDirectory: String) async -> CertificateInspection {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.inspectCertificateSync(certDirectory: certDirectory))
            }
        }
    }

    private func updateCertificateSync(
        certificatePath: String,
        privateKeyPath: String,
        certDirectory: String,
        pfxPassword: String,
        privateKeyPassword: String
    ) -> CertificateUpdateReport {
        let result = RustCoreService.shared.decode(
            CertificateUpdateReport.self,
            arguments: [
                "cert-update",
                "--cert", certificatePath,
                "--key", privateKeyPath,
                "--dir", certDirectory
            ],
            // 密码走环境变量，不出现在命令行参数 / 进程列表里
            environment: [
                "P2A_PFX_PASSWORD": pfxPassword,
                "P2A_KEY_PASSWORD": privateKeyPassword
            ]
        )

        switch result {
        case .success(let report):
            return report
        case .failure(let commandResult):
            return CertificateUpdateReport(
                certDirectory: certDirectory,
                filesWritten: [],
                backups: [],
                certificateInfo: "",
                commandResult: commandResult
            )
        }
    }

    private func inspectCertificateSync(certDirectory: String) -> CertificateInspection {
        let dir = URL(fileURLWithPath: certDirectory, isDirectory: true)
        let candidates = [
            dir.appendingPathComponent("fullchain.pem"),
            dir.appendingPathComponent("cert.pem")
        ]
        guard let certURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            let result = CommandResult(
                command: "openssl x509",
                exitCode: -1,
                stdout: "",
                stderr: "未找到 fullchain.pem 或 cert.pem"
            )
            return CertificateInspection(
                certificatePath: "",
                subject: "",
                issuer: "",
                notBefore: nil,
                notAfter: nil,
                rawOutput: "",
                commandResult: result
            )
        }

        let result = runCommand("/usr/bin/openssl", args: [
            "x509",
            "-in", certURL.path,
            "-noout",
            "-subject",
            "-issuer",
            "-dates"
        ])
        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        return CertificateInspection(
            certificatePath: certURL.path,
            subject: value(named: "subject", in: output),
            issuer: value(named: "issuer", in: output),
            notBefore: parseOpenSSLDate(value(named: "notBefore", in: output)),
            notAfter: parseOpenSSLDate(value(named: "notAfter", in: output)),
            rawOutput: output,
            commandResult: result
        )
    }

    private func runCommand(_ command: String, args: [String]) -> CommandResult {
        ProcessRunner.run(command, args: args, timeout: 15)
    }

    private func value(named name: String, in output: String) -> String {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
            ?? ""
    }

    private func parseOpenSSLDate(_ value: String) -> Date? {
        let normalized = value
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        return formatter.date(from: normalized)
    }
}
