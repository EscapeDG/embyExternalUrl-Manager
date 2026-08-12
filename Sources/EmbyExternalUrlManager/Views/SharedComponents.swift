import SwiftUI
import AppKit

// MARK: - Navigation environment (deep-link from dashboard / pipeline)

private struct NavigateKey: EnvironmentKey {
    static let defaultValue: Binding<SidebarItem?> = .constant(.dashboard)
}

extension EnvironmentValues {
    var navigate: Binding<SidebarItem?> {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
}

// MARK: - Page scaffold

/// Unified page chrome: optional scroll content + optional sticky footer (save bar).
struct PageScaffold<Content: View, Footer: View>: View {
    let title: String
    var useScroll: Bool = true
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(
        title: String,
        useScroll: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.useScroll = useScroll
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            if useScroll {
                ScrollView {
                    content()
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            footer()
        }
        .navigationTitle(title)
    }
}

extension PageScaffold where Footer == EmptyView {
    init(title: String, useScroll: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, useScroll: useScroll, content: content, footer: { EmptyView() })
    }
}

// MARK: - Config save bar (single save UX)

struct ConfigSaveBar: View {
    @EnvironmentObject var configService: ConfigService
    var showsReset: Bool = false
    var onReset: (() -> Void)?

    @State private var flashMessage: String?
    @State private var flashIsError = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                dirtyLabel
                if let flashMessage {
                    Text(flashMessage)
                        .font(.caption)
                        .foregroundColor(flashIsError ? .red : .secondary)
                        .lineLimit(2)
                }
                Spacer()
                if showsReset, let onReset {
                    Button("恢复默认", role: .destructive, action: onReset)
                        .buttonStyle(.bordered)
                }
                Button("保存配置") {
                    let ok = configService.save()
                    flashIsError = !ok
                    flashMessage = ok
                        ? "已写入磁盘"
                        : (configService.lastPersistenceError ?? "无法写入配置文件。")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var dirtyLabel: some View {
        if configService.isDirty {
            Label("未保存的更改", systemImage: "pencil.circle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        } else if configService.lastSavedAt != nil {
            Label("已与磁盘同步", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Pipeline checklist UI

struct PipelineChecklistView: View {
    let steps: [PipelineStep]
    var compact: Bool = false
    @Environment(\.navigate) private var navigate

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Text(compact ? "主链路" : "部署检查单")
                    .font(compact ? .headline : .title3)
                    .fontWeight(.semibold)
                Spacer()
                Text(DeploymentPipeline.summaryLine(steps: steps))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: step.status))
                        .foregroundColor(color(for: step.status))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(step.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let target = step.navigateTo, step.status != .ok {
                        Button("前往") {
                            navigate.wrappedValue = target
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(compact ? 8 : 10)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(6)
            }
        }
    }

    private func icon(for status: PipelineStep.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .pending: return "circle.dashed"
        }
    }

    private func color(for status: PipelineStep.Status) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .fail: return .red
        case .pending: return .secondary
        }
    }
}

// MARK: - Media server form (Plex / Emby / Jellyfin)

struct MediaServerEditor: View {
    @EnvironmentObject var configService: ConfigService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormField(label: "服务器地址") {
                VStack(alignment: .leading) {
                    TextField(addressPlaceholder, text: serverURLBinding)
                    Text(addressHelp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            if configService.config.mediaServerType != .plex {
                FormField(label: "API Key / Token") {
                    SecureField("输入 API Key", text: apiKeyBinding)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 24) {
                    FormField(label: "HTTP 反代端口") {
                        TextField("8091", value: httpPortBinding, format: .number)
                            .frame(width: 120)
                    }
                    FormField(label: "HTTPS 反代端口") {
                        TextField("8095", value: httpsPortBinding, format: .number)
                            .frame(width: 120)
                    }
                }
                Text("配置 nginx 容器的监听端口。HTTP 用于常规反向代理访问，HTTPS 用于证书加载后的 SSL 安全连接。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var addressPlaceholder: String {
        switch configService.config.mediaServerType {
        case .plex: return "http://127.0.0.1:32400"
        case .emby, .jellyfin: return "http://127.0.0.1:8096"
        }
    }

    private var addressHelp: String {
        switch configService.config.mediaServerType {
        case .plex:
            return "上游 plex2Alist 只需要 Plex 源服务地址；播放请求中的 X-Plex-Token 会由 Plex 客户端带入并透传。"
        case .emby:
            return "输入 Emby 源服务地址。"
        case .jellyfin:
            return "输入 Jellyfin 源服务地址。"
        }
    }

    private var serverURLBinding: Binding<String> {
        switch configService.config.mediaServerType {
        case .plex: return $configService.config.plex.serverURL
        case .emby: return $configService.config.emby.serverURL
        case .jellyfin: return $configService.config.jellyfin.serverURL
        }
    }

    private var apiKeyBinding: Binding<String> {
        switch configService.config.mediaServerType {
        case .plex: return .constant("")
        case .emby: return $configService.config.emby.apiKey
        case .jellyfin: return $configService.config.jellyfin.apiKey
        }
    }

    private var httpPortBinding: Binding<Int> {
        switch configService.config.mediaServerType {
        case .plex: return $configService.config.plex.proxyPort
        case .emby: return $configService.config.emby.proxyPort
        case .jellyfin: return $configService.config.jellyfin.proxyPort
        }
    }

    private var httpsPortBinding: Binding<Int> {
        switch configService.config.mediaServerType {
        case .plex: return $configService.config.plex.proxyHttpsPort
        case .emby: return $configService.config.emby.proxyHttpsPort
        case .jellyfin: return $configService.config.jellyfin.proxyHttpsPort
        }
    }
}

// MARK: - Form Field Component

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            content
        }
    }
}

// MARK: - Form GroupBox Style

struct FormGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .font(.headline)
                .padding(.bottom, 12)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status Dot

struct StatusDot: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isActive ? 1.0 : 0.4)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Metric Badge

struct MetricBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(4)
    }
}

// MARK: - Command Output View

struct CommandOutputView: View {
    let title: String
    let result: CommandResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                Text(result.exitCode == 0 ? "成功" : "失败 \(result.exitCode)")
                    .font(.caption)
                    .foregroundColor(result.exitCode == 0 ? .green : .red)
            }
            Text(result.command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            if !result.stdout.isEmpty {
                Text(result.stdout)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if !result.stderr.isEmpty {
                Text(result.stderr)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
}
