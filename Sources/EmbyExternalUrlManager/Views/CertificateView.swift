import SwiftUI

enum CertMode: String, CaseIterable {
    case manual = "手动上传"
    case acme = "自动申请"
}

struct CertificateView: View {
    @EnvironmentObject var configService: ConfigService
    @StateObject private var dockerService = DockerService.shared

    @State private var certMode: CertMode = .manual

    // Status
    @State private var certificateInspection: CertificateService.CertificateInspection?
    @State private var isInspecting = false

    // Manual
    @State private var certificatePath = ""
    @State private var privateKeyPath = ""
    @State private var certDirectory = ""
    @State private var pfxPassword = ""
    @State private var privateKeyPassword = ""
    @State private var reloadAfterUpdate = true
    @State private var isUpdating = false
    @State private var report: CertificateService.CertificateUpdateReport?
    @State private var reloadResult: CommandResult?

    // ACME
    @State private var acmeStatus: CertificateAutomationService.Status = .empty
    @State private var acmeDomains = ""
    @State private var acmeEmail = ""
    @State private var acmeMode: CertificateAutomationService.IssueMode = .standalone
    @State private var acmeWebrootPath = ""
    @State private var acmeCustomArguments = ""
    @State private var acmePreflightShell = ""
    @State private var reloadAfterRenew = true
    @State private var isAcmeWorking = false
    @State private var acmeCommandResult: CommandResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status card
                GroupBox {
                    certificateStatusContent
                } label: {
                    Label("证书状态", systemImage: "lock.shield")
                        .font(.headline)
                }
                .groupBoxStyle(FormGroupBoxStyle())

                // Mode picker
                Picker("模式", selection: $certMode) {
                    ForEach(CertMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Manual upload
                if certMode == .manual {
                    GroupBox {
                        manualUploadContent
                    } label: {
                        Label("手动上传证书", systemImage: "doc.badge.plus")
                            .font(.headline)
                    }
                    .groupBoxStyle(FormGroupBoxStyle())

                    // Manual results
                    if let report {
                        GroupBox {
                            reportContent(report)
                        } label: {
                            Label("更新结果", systemImage: "checkmark.circle")
                                .font(.headline)
                        }
                        .groupBoxStyle(FormGroupBoxStyle())
                    }

                    if let reloadResult {
                        CommandOutputView(title: "nginx reload", result: reloadResult)
                    }
                }

                // ACME
                if certMode == .acme {
                    GroupBox {
                        acmeContent
                    } label: {
                        Label("ACME 自动申请", systemImage: "sparkles")
                            .font(.headline)
                    }
                    .groupBoxStyle(FormGroupBoxStyle())

                    if let acmeCommandResult {
                        CommandOutputView(title: "ACME 命令", result: acmeCommandResult)
                    }
                }

                if let reloadResult, certMode == .acme {
                    CommandOutputView(title: "nginx reload", result: reloadResult)
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("证书")
        .onAppear {
            if certDirectory.isEmpty {
                certDirectory = configService.config.certificateDirectory ?? defaultCertDirectory
            }
            loadAcmeConfig()
            Task {
                await refreshCertificateStatus()
                await refreshAcmeStatus()
            }
        }
    }

    // MARK: - Status Content

    private var certificateStatusContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(statusTitle, systemImage: statusIcon)
                    .foregroundColor(statusColor)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    Task { await refreshCertificateStatus() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isInspecting)
            }

            InfoRow(label: "证书目录", value: effectiveCertDirectory)

            if let inspection = certificateInspection, inspection.commandResult.exitCode == 0 {
                InfoRow(label: "证书文件", value: inspection.certificatePath)
                if !inspection.subject.isEmpty {
                    InfoRow(label: "Subject", value: inspection.subject)
                }
                if !inspection.issuer.isEmpty {
                    InfoRow(label: "Issuer", value: inspection.issuer)
                }
                if let notBefore = inspection.notBefore {
                    InfoRow(label: "生效时间", value: dateText(notBefore))
                }
                if let notAfter = inspection.notAfter {
                    InfoRow(label: "到期时间", value: dateText(notAfter))
                }
                if let days = inspection.daysRemaining {
                    InfoRow(label: "剩余天数", value: "\(days) 天")
                }
            } else if let inspection = certificateInspection {
                Text(inspection.commandResult.stderr.isEmpty ? "当前目录未发现证书" : inspection.commandResult.stderr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Manual Upload

    private var manualUploadContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormField(label: "证书 PEM") {
                filePickerRow(placeholder: "cert.pem 或 fullchain.pem", text: $certificatePath, buttonTitle: "选择证书")
            }
            FormField(label: "私钥 PEM") {
                filePickerRow(placeholder: "key.pem 或 privkey.key", text: $privateKeyPath, buttonTitle: "选择私钥")
            }
            FormField(label: "证书目录") {
                HStack {
                    TextField(defaultCertDirectory, text: $certDirectory)
                        .font(.system(.body, design: .monospaced))
                    Button("选择目录") { selectFolder { certDirectory = $0 } }
                        .buttonStyle(.bordered)
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: effectiveCertDirectory)) } label: {
                        Image(systemName: "folder")
                    }.buttonStyle(.bordered).help("打开证书目录")
                }
            }
            FormField(label: "PFX 密码") {
                SecureField("用于 certificate.pfx；留空则生成空密码 PFX", text: $pfxPassword)
            }
            FormField(label: "私钥密码") {
                SecureField("如果 key.pem 已加密，在这里填写；未加密则留空", text: $privateKeyPassword)
            }
            Toggle("更新后自动重载 nginx 容器", isOn: $reloadAfterUpdate)
                .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Button {
                    Task { await updateCertificate() }
                } label: {
                    Label("一键更新证书", systemImage: "lock.rotation")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating || certificatePath.isEmpty || privateKeyPath.isEmpty)
                if isUpdating {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("正在更新证书并生成 PFX...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - ACME

    private var acmeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(acmeStatus.acmePath.isEmpty ? "acme.sh 未安装" : "acme.sh 已安装",
                      systemImage: acmeStatus.acmePath.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(acmeStatus.acmePath.isEmpty ? .orange : .green)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    Task { await refreshAcmeStatus() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            if !acmeStatus.acmePath.isEmpty {
                InfoRow(label: "acme.sh", value: acmeStatus.acmePath)
            }

            FormField(label: "域名") {
                TextField("example.com 或 example.com,www.example.com", text: $acmeDomains)
                    .font(.system(.body, design: .monospaced))
            }
            FormField(label: "邮箱") {
                TextField("用于注册 ACME 账号，可留空", text: $acmeEmail)
                    .font(.system(.body, design: .monospaced))
            }
            FormField(label: "验证方式") {
                Picker("验证方式", selection: $acmeMode) {
                    ForEach(CertificateAutomationService.IssueMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if acmeMode == .webroot {
                FormField(label: "Webroot") {
                    directoryRow(
                        placeholder: CertificateAutomationService.shared.defaultWebrootDirectory(
                            deploymentDirectory: configService.ensureDeploymentDirectory()),
                        text: $acmeWebrootPath, buttonTitle: "选择目录")
                }
            }

            if acmeMode == .customDNS {
                FormField(label: "DNS 参数") {
                    TextField("--dns dns_cf", text: $acmeCustomArguments)
                        .font(.system(.body, design: .monospaced))
                }
                FormField(label: "环境变量") {
                    TextField("export CF_Token='xxx'; export CF_Account_ID='xxx'", text: $acmePreflightShell)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Toggle("申请和续期成功后重载 nginx 容器", isOn: $reloadAfterRenew)
                .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Button {
                    Task { await installAcme() }
                } label: {
                    Label("安装 acme.sh", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .disabled(isAcmeWorking)

                Button {
                    Task { await issueCertificate() }
                } label: {
                    Label("申请并配置自动续期", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAcmeWorking || acmeDomains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isAcmeWorking {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("正在通过 acme.sh 执行操作，请耐心等待（可在下方查看结果）...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers (unchanged from original)

    private var defaultCertDirectory: String { configService.nginxConfigDirectory() + "/conf.d/cert" }
    private var effectiveCertDirectory: String { certDirectory.isEmpty ? defaultCertDirectory : certDirectory }

    private var statusTitle: String {
        guard let inspection = certificateInspection else { return "正在读取证书" }
        guard inspection.commandResult.exitCode == 0 else { return "未找到当前证书" }
        if inspection.isExpired { return "证书已过期" }
        if let days = inspection.daysRemaining {
            if days <= 7 { return "证书即将过期" }
            if days <= 30 { return "证书临近到期" }
            return "证书有效"
        }
        return "证书状态未知"
    }

    private var statusIcon: String {
        guard let inspection = certificateInspection, inspection.commandResult.exitCode == 0 else {
            return "exclamationmark.triangle.fill"
        }
        if inspection.isExpired { return "xmark.octagon.fill" }
        if let days = inspection.daysRemaining, days <= 30 { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        guard let inspection = certificateInspection, inspection.commandResult.exitCode == 0 else { return .orange }
        if inspection.isExpired { return .red }
        if let days = inspection.daysRemaining, days <= 30 { return .orange }
        return .green
    }

    private func updateCertificate() async {
        isUpdating = true; reloadResult = nil
        let targetDirectory = effectiveCertDirectory
        await MainActor.run { configService.config.certificateDirectory = targetDirectory; configService.save() }
        let updateReport = await CertificateService.shared.updateCertificate(
            certificatePath: certificatePath, privateKeyPath: privateKeyPath,
            certDirectory: targetDirectory, pfxPassword: pfxPassword, privateKeyPassword: privateKeyPassword)
        var reload: CommandResult?
        if updateReport.succeeded, reloadAfterUpdate {
            reload = await dockerService.reloadNginx(mediaServerType: configService.config.mediaServerType)
        }
        await MainActor.run { report = updateReport; reloadResult = reload; isUpdating = false }
        await refreshCertificateStatus()
    }

    private func installAcme() async {
        isAcmeWorking = true; saveAcmeConfig()
        let result = await CertificateAutomationService.shared.openInstallAcme(email: acmeEmail)
        await MainActor.run { acmeCommandResult = result; isAcmeWorking = false }
    }

    private func issueCertificate() async {
        isAcmeWorking = true; saveAcmeConfig()
        let request = CertificateAutomationService.Request(
            domains: acmeDomains, email: acmeEmail, mode: acmeMode,
            webrootPath: effectiveWebrootPath, customIssueArguments: acmeCustomArguments,
            preflightShell: acmePreflightShell, certDirectory: effectiveCertDirectory,
            pfxPassword: pfxPassword, reloadAfterRenew: reloadAfterRenew)
        let result = await CertificateAutomationService.shared.openIssueAndInstall(request)
        await MainActor.run { acmeCommandResult = result; isAcmeWorking = false }
    }

    private func refreshCertificateStatus() async {
        isInspecting = true
        let inspection = await CertificateService.shared.inspectCertificate(certDirectory: effectiveCertDirectory)
        await MainActor.run { certificateInspection = inspection; isInspecting = false }
    }

    private func refreshAcmeStatus() async {
        let status = await CertificateAutomationService.shared.refreshStatus()
        await MainActor.run { acmeStatus = status }
    }

    private var effectiveWebrootPath: String {
        acmeWebrootPath.isEmpty
            ? CertificateAutomationService.shared.defaultWebrootDirectory(deploymentDirectory: configService.ensureDeploymentDirectory())
            : acmeWebrootPath
    }

    private func loadAcmeConfig() {
        acmeDomains = configService.config.certificateDomains
        acmeEmail = configService.config.certificateEmail
        acmeMode = CertificateAutomationService.IssueMode(rawValue: configService.config.certificateIssueMode) ?? .standalone
        acmeWebrootPath = configService.config.certificateWebrootPath
        acmeCustomArguments = configService.config.certificateCustomIssueArguments
        acmePreflightShell = configService.config.certificatePreflightShell
        reloadAfterRenew = configService.config.certificateReloadAfterRenew
    }

    private func saveAcmeConfig() {
        configService.config.certificateDirectory = effectiveCertDirectory
        configService.config.certificateDomains = acmeDomains
        configService.config.certificateEmail = acmeEmail
        configService.config.certificateIssueMode = acmeMode.rawValue
        configService.config.certificateWebrootPath = acmeWebrootPath
        configService.config.certificateCustomIssueArguments = acmeCustomArguments
        configService.config.certificatePreflightShell = acmePreflightShell
        configService.config.certificateReloadAfterRenew = reloadAfterRenew
        configService.save()
    }

    private func reportContent(_ report: CertificateService.CertificateUpdateReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(report.succeeded ? "证书更新成功" : "证书更新失败",
                  systemImage: report.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(report.succeeded ? .green : .red).fontWeight(.medium)
            InfoRow(label: "证书目录", value: report.certDirectory)

            if !report.filesWritten.isEmpty {
                Text("写入文件").font(.caption).foregroundColor(.secondary)
                ForEach(report.filesWritten, id: \.self) { path in
                    Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            if !report.backups.isEmpty {
                Text("已备份旧文件").font(.caption).foregroundColor(.secondary)
                ForEach(report.backups, id: \.self) { path in
                    Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            if !report.certificateInfo.isEmpty {
                Text(report.certificateInfo).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06)).cornerRadius(6)
            }
            CommandOutputView(title: "openssl pkcs12", result: report.commandResult)
        }
    }

    private func filePickerRow(placeholder: String, text: Binding<String>, buttonTitle: String) -> some View {
        HStack {
            TextField(placeholder, text: text).font(.system(.body, design: .monospaced))
            Button(buttonTitle) { selectFile { text.wrappedValue = $0 } }.buttonStyle(.bordered)
        }
    }

    private func directoryRow(placeholder: String, text: Binding<String>, buttonTitle: String) -> some View {
        HStack {
            TextField(placeholder, text: text).font(.system(.body, design: .monospaced))
            Button(buttonTitle) { selectFolder { text.wrappedValue = $0 } }.buttonStyle(.bordered)
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)) } label: {
                Image(systemName: "folder")
            }.buttonStyle(.bordered).help("打开目录")
        }
    }

    private func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium; f.timeStyle = .medium
        return f.string(from: date)
    }

    private func selectFile(_ completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { completion(url.path) }
    }

    private func selectFolder(_ completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { completion(url.path) }
    }
}
