import SwiftUI

struct ContentView: View {
    @EnvironmentObject var configService: ConfigService
    @StateObject private var systemStatus = SystemStatusStore.shared
    @State private var selectedItem: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
        } detail: {
            detailView
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                await systemStatus.refreshAll(configService: configService, force: true)
                            }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .help("刷新 Docker / 容器 / 证书状态")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .environment(\.navigate, $selectedItem)
        .environmentObject(systemStatus)
        .onAppear {
            Task {
                await systemStatus.refreshAll(configService: configService, force: true)
            }
        }
        .onChange(of: configService.config.mediaServerType) { _, _ in
            Task {
                await systemStatus.refreshDocker(
                    mediaServerType: configService.config.mediaServerType,
                    force: true
                )
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .dashboard:
            DashboardView()
        case .mediaServer:
            ConnectionView()
        case .redirectRules:
            RedirectSettingsView()
        case .pathMapping:
            PathMappingView()
        case .certificate:
            CertificateView()
        case .upstreamSync:
            UpstreamSyncView()
        case .docker:
            DockerInstallView()
        case .generate:
            GenerateView()
        case nil:
            DashboardView()
        }
    }
}
