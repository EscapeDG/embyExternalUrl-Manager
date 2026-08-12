import Foundation

// MARK: - Pipeline step

struct PipelineStep: Identifiable, Equatable {
    enum Status: Equatable {
        case ok
        case warning
        case fail
        case pending
    }

    let id: String
    let title: String
    let status: Status
    let message: String
    let navigateTo: SidebarItem?
}

// MARK: - Deployment pipeline evaluator

/// Pure evaluation of the main deploy chain (config → upstream → generate → container → nginx).
enum DeploymentPipeline {
    @MainActor
    static func evaluate(
        configService: ConfigService,
        status: SystemStatusStore
    ) -> [PipelineStep] {
        let config = configService.config
        let fm = FileManager.default
        let deployDir = configService.ensureDeploymentDirectory()
        let nginxDir = configService.nginxConfigDirectory()
        let confDir = nginxDir + "/conf.d"
        let activeConf = confDir + "/" + config.mediaServerType.nginxConfName
        let composePath = deployDir + "/docker-compose.yml"
        let constantJS = confDir + "/constant.js"

        var steps: [PipelineStep] = []

        // 1. Config saved
        if configService.isDirty {
            steps.append(PipelineStep(
                id: "config",
                title: "配置已保存",
                status: .warning,
                message: "有未保存的更改；生成时会自动保存。",
                navigateTo: .mediaServer
            ))
        } else if let err = configService.lastPersistenceError, !err.isEmpty {
            steps.append(PipelineStep(
                id: "config",
                title: "配置已保存",
                status: .fail,
                message: err,
                navigateTo: .mediaServer
            ))
        } else {
            steps.append(PipelineStep(
                id: "config",
                title: "配置已保存",
                status: .ok,
                message: "config.json 与内存一致",
                navigateTo: nil
            ))
        }

        // 2. Paths / server address
        let serverURL: String = {
            switch config.mediaServerType {
            case .plex: return config.plex.serverURL
            case .emby: return config.emby.serverURL
            case .jellyfin: return config.jellyfin.serverURL
            }
        }()
        let openListOK = !config.openList.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let serverOK = !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if serverOK && openListOK {
            steps.append(PipelineStep(
                id: "endpoints",
                title: "媒体与 OpenList 地址",
                status: .ok,
                message: "\(config.mediaServerType.rawValue) 与 OpenList 已填写",
                navigateTo: .mediaServer
            ))
        } else {
            steps.append(PipelineStep(
                id: "endpoints",
                title: "媒体与 OpenList 地址",
                status: .fail,
                message: "请补全媒体服务器地址与 OpenList 地址",
                navigateTo: .mediaServer
            ))
        }

        // 3. Upstream skeleton
        let hasNginxConf = fm.fileExists(atPath: nginxDir + "/nginx.conf")
        let hasActiveConf = fm.fileExists(atPath: activeConf) || fm.fileExists(atPath: activeConf + ".disabled")
        if hasNginxConf && hasActiveConf {
            steps.append(PipelineStep(
                id: "upstream",
                title: "上游 nginx 骨架",
                status: .ok,
                message: "已检测到 nginx.conf 与 \(config.mediaServerType.nginxConfName)",
                navigateTo: .upstreamSync
            ))
        } else {
            steps.append(PipelineStep(
                id: "upstream",
                title: "上游 nginx 骨架",
                status: .fail,
                message: "缺少 nginx 骨架，请先「上游同步」",
                navigateTo: .upstreamSync
            ))
        }

        // 4. Generated parameters
        if fm.fileExists(atPath: constantJS) {
            steps.append(PipelineStep(
                id: "generated",
                title: "参数已生成",
                status: .ok,
                message: "constant.js 已存在",
                navigateTo: .generate
            ))
        } else {
            steps.append(PipelineStep(
                id: "generated",
                title: "参数已生成",
                status: .pending,
                message: "尚未生成 constant*.js",
                navigateTo: .generate
            ))
        }

        // 5. Compose
        if fm.fileExists(atPath: composePath) {
            steps.append(PipelineStep(
                id: "compose",
                title: "docker-compose.yml",
                status: .ok,
                message: "部署目录已有 Compose",
                navigateTo: .generate
            ))
        } else {
            steps.append(PipelineStep(
                id: "compose",
                title: "docker-compose.yml",
                status: .fail,
                message: "缺少 compose，无法启动容器",
                navigateTo: .generate
            ))
        }

        // 6. Docker engine
        if status.dockerAvailable {
            steps.append(PipelineStep(
                id: "docker",
                title: "Docker 引擎",
                status: .ok,
                message: "Docker 守护进程可用",
                navigateTo: nil
            ))
        } else {
            steps.append(PipelineStep(
                id: "docker",
                title: "Docker 引擎",
                status: .fail,
                message: "Docker 未运行，可前往 Docker 环境安装/启动",
                navigateTo: .docker
            ))
        }

        // 7. Container
        if status.containerRunning {
            steps.append(PipelineStep(
                id: "container",
                title: "反代容器",
                status: .ok,
                message: status.containerStatus.isEmpty ? "运行中" : status.containerStatus,
                navigateTo: .generate
            ))
        } else if status.dockerAvailable {
            steps.append(PipelineStep(
                id: "container",
                title: "反代容器",
                status: .warning,
                message: status.containerStatus.isEmpty ? "未运行" : status.containerStatus,
                navigateTo: .generate
            ))
        } else {
            steps.append(PipelineStep(
                id: "container",
                title: "反代容器",
                status: .pending,
                message: "等待 Docker 可用",
                navigateTo: .docker
            ))
        }

        return steps
    }

    static func summaryLine(steps: [PipelineStep]) -> String {
        let ok = steps.filter { $0.status == .ok }.count
        let fail = steps.filter { $0.status == .fail }.count
        let warn = steps.filter { $0.status == .warning }.count
        if fail > 0 {
            return "\(ok)/\(steps.count) 通过 · \(fail) 项需处理"
        }
        if warn > 0 {
            return "\(ok)/\(steps.count) 通过 · \(warn) 项注意"
        }
        return "\(ok)/\(steps.count) 主链路检查通过"
    }
}
