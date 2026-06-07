import SwiftUI

struct ContentView: View {
    @EnvironmentObject var configService: ConfigService
    @StateObject private var dockerService = DockerService.shared
    @State private var selectedItem: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
        } detail: {
            detailView
                .toolbar {
                    // Refresh
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                await dockerService.detect()
                                _ = await dockerService.ps()
                            }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .help("刷新状态")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            Task {
                await dockerService.detect()
                _ = await dockerService.ps(mediaServerType: configService.config.mediaServerType)
            }
        }
        .onChange(of: configService.config.mediaServerType) { _, _ in
            Task {
                await dockerService.detect()
                _ = await dockerService.ps(mediaServerType: configService.config.mediaServerType)
            }
        }
    }

    // MARK: - Detail View Router

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


