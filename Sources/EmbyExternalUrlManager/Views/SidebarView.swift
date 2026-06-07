import SwiftUI

// MARK: - Navigation Items

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case mediaServer
    case redirectRules
    case pathMapping
    case certificate
    case upstreamSync
    case docker
    case generate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "仪表盘"
        case .mediaServer:  return "媒体服务器"
        case .redirectRules: return "302 规则"
        case .pathMapping:  return "路径映射"
        case .certificate:  return "证书"
        case .upstreamSync: return "上游同步"
        case .docker:       return "Docker 环境"
        case .generate:     return "生成与部署"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:    return "gauge.medium"
        case .mediaServer:  return "cable.connector"
        case .redirectRules: return "arrow.triangle.swap"
        case .pathMapping:  return "arrow.left.arrow.right"
        case .certificate:  return "lock.shield"
        case .upstreamSync: return "arrow.triangle.2.circlepath"
        case .docker:       return "shippingbox"
        case .generate:     return "gearshape.2"
        }
    }

    var group: SidebarGroup {
        switch self {
        case .dashboard:    return .overview
        case .mediaServer, .redirectRules, .pathMapping: return .configuration
        case .certificate:  return .security
        case .upstreamSync, .docker, .generate: return .deployment
        }
    }
}

enum SidebarGroup: String, CaseIterable {
    case overview
    case configuration
    case security
    case deployment

    var label: String {
        switch self {
        case .overview:      return ""
        case .configuration: return "配置"
        case .security:      return "安全"
        case .deployment:    return "部署"
        }
    }

    var items: [SidebarItem] {
        SidebarItem.allCases.filter { $0.group == self }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var configService: ConfigService
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            // Dashboard — standalone
            Section {
                Label(SidebarItem.dashboard.label, systemImage: SidebarItem.dashboard.icon)
                    .tag(SidebarItem.dashboard)
            }

            // Configuration group
            Section(header: Text("配置").font(.caption).foregroundColor(.secondary)) {
                ForEach(SidebarGroup.configuration.items) { item in
                    sidebarRow(item)
                }
            }

            // Security group
            Section(header: Text("安全").font(.caption).foregroundColor(.secondary)) {
                ForEach(SidebarGroup.security.items) { item in
                    sidebarRow(item)
                }
            }

            // Deployment group
            Section(header: Text("部署").font(.caption).foregroundColor(.secondary)) {
                ForEach(SidebarGroup.deployment.items) { item in
                    sidebarRow(item)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)

        // Bottom server type badge
        .safeAreaInset(edge: .bottom) {
            serverBadge
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.label, systemImage: item.icon)
            .tag(item)
            .font(.subheadline)
    }

    private var serverBadge: some View {
        let mediaType = configService.config.mediaServerType
        let isPlex = mediaType == .plex
        return HStack(spacing: 6) {
            Image(systemName: isPlex ? "play.tv.fill" : "play.tv")
                .font(.system(size: 10, weight: .bold))
            Text(mediaType.rawValue)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundColor(.white)
        .background(isPlex ? Color.orange : Color.green)
        .cornerRadius(4)
        .padding(.bottom, 8)
    }
}
