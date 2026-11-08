# embyExternalUrl-Manager Release Notes

## 1.1.2 (112)

### 修复（1.1.1 的回归，请升级）

- **不再覆盖已有的 `docker-compose.yml`**：1.1.1 会把容器名（如 `nginx-plex`）或相对路径挂载不符合其预期的手写 compose 当成"不一致"并重写。现在已有 compose 一律不改动；容器名接受 `plex2Alist-nginx` / `nginx-plex`（Emby、Jellyfin 同理），挂载源支持相对路径，日志与缓存目录不检查。
- 只有 `nginx.conf` / `conf.d` 的挂载源确实指向别处时才提示，并把按当前设置生成的版本写到 `docker-compose.generated.yml`，由用户自行对比。
- **开关被改写时提示**：生成时若 Manager 里的开关值会改变现有文件中的 `enable`（如转码 `false → true`），生成页会列出变化。
- compose 没有 `acme-webroot` 挂载时，不再写入无用的 `acme-challenge.conf`。

### 限制

- 仍为 ad-hoc 签名，未公证。
- 「容器日志」读取 `docker logs`；nginx 日志写入挂载文件的部署里，该视图可能为空（后续版本改进）。

## 1.1.1 (111)

### 修复（架构核查后）

- **OpenList 检测**：按响应体 `code` 判断（OpenList 错误 Token 也返回 HTTP 200），增加目录读取检测；仪表盘诊断与「媒体服务器」页接入 OpenList / 媒体服务器连通与 API Key 检测。
- **Plex ⇄ Emby/Jellyfin 切换**：上游同步识别骨架类型（`.manager-skeleton-type`），切换时替换上游自带文件并只保留当前类型的 nginx conf，不再两套骨架混杂。
- **保留用户参数**：生成时保留手写的 `routeRule`、`alistRawUrlMapping`、`clientSelfAlistRule`、ext 各项及非 Manager 格式的路径映射；`enable` 类字段只更新开关。
- **证书目录统一**：自定义证书目录在生成 / 续期时同步到 nginx 实际读取的 `conf.d/cert`。
- **Compose 随配置更新**：容器名或挂载源变化时备份并重新生成 `docker-compose.yml`；一致时保留用户自定义。
- **外部命令**：统一 `ProcessRunner`（超时、管道排空）；PFX / 私钥密码改走环境变量，不再出现在命令行。
- **容器管理**：Docker 状态单源；启动 / 停止 / 重启统一接口，"停止"改为 `compose stop`；生成后提示"验证并重载"，先 `nginx -t` 再 reload。
- **ACME webroot** 接入 nginx（`acme-challenge.conf` + compose 挂载）；Plex 默认 HTTPS 端口改为 8099，Jellyfin 为 8092/8097。
- 其它：主窗口不再多开；上游同步页保存只写本页字段；备份保留最近若干份；模板内容未变不重写。

### 限制

- 仍为 ad-hoc 签名，未公证。
- 未在真实 Docker / OpenList / Plex 环境做 302 smoke 测试，菜单栏与生成页界面点击未做界面验证。

## 1.1.0 (110)

### 架构治理（从补丁到契约）

- **配置单一写路径**：`ConfigService` 跟踪 `isDirty` / `lastSavedAt`；编辑只改内存，`save()` 是唯一落盘入口。
- **生成前自动保存**：`generateDeployment()` 若有未保存更改先 `saveIfNeeded()`，失败则中止生成并回报错误，消除「内存有、磁盘无」断链。
- **SystemStatusStore**：Docker / 容器 / 证书摘要单源刷新（带 debounce），仪表盘、生成页、菜单栏共用，去掉多处重复 `detect+ps`。
- **DeploymentPipeline**：主链路检查单（配置 → 端点 → 上游骨架 → 参数 → compose → Docker → 容器）；**仪表盘简版 + 生成页完整版**，缺步可一键跳转。
- **PageScaffold + ConfigSaveBar**：统一页面壳与底栏保存反馈（脏指示 / 错误 inline），去掉各配置页复制的 Alert 状态机。
- **MediaServerEditor**：Plex / Emby / Jellyfin 表单合并，避免三段漂移。
- **证书卡真数据**：仪表盘证书卡读取 `CertificateService` 检验摘要，不再固定「待检查」。
- **布局**：窗口最小尺寸统一 900×600；路径映射窄窗 `ViewThatFits` 纵向回退；生成页日志改 `DisclosureGroup`，去掉嵌套 ScrollView。
- **窗口唤起**：菜单「显示主窗口」优先 `openWindow`，去掉 className 启发式扫描。

### 限制

- 仍为 ad-hoc 签名，未公证。
- 真实 302 / OpenList smoke 需在部署环境手测；Pipeline 做到配置与容器/nginx 前置检查。

## 1.0.5 (105)

- **配置损坏保护**：`config.json` 解析失败且备份失败时，不再静默丢弃，而是保留原文件与当前内存配置并提示用户手动处理。
- **Docker 命令死锁修复**：外部进程执行改为并发读取 stdout/stderr，`docker compose`、镜像拉取等大输出命令不再因管道缓冲写满而阻塞至超时。
- **保存反馈全覆盖**：路径映射、302 规则、连接页重置、上游同步、证书页与扫描回填在保存失败时显示具体错误，不再误报「已保存」。
- **Compose 保留策略**：部署目录已存在 `docker-compose.yml` 时生成流程跳过覆盖并提示；恢复 v1.0.1 起「不覆盖用户自定义 Compose」的行为。Compose 模板路径值改为带引号的 YAML 标量，支持含空格、`#`、`:` 的路径。
- **容器精确匹配**：容器状态只认与当前媒体类型完全同名的容器，不再把子串相似容器误判为受管容器。
- **Plex 骨架警告修正**：Plex 生成不再对未使用的 `constant-nginx.js` 发出缺失警告。
- **容器操作结果展示**：生成页启动/停止/重启失败时展示命令输出，不再静默无反馈。
- **备份文件名唯一化**：生成备份加入毫秒时间戳与目录 hash，避免同秒或跨部署同名碰撞导致写入失败。
- **构建一致性**：Rust core 构建启用 `--locked`，lockfile 过期时构建直接失败；`Cargo.lock` 与发布版本对齐。
- 附带 OpenSpec 变更记录：`openspec/changes/fix-v104-hardening/`。

## 1.0.4 (104)

- 中间版本标签（与 1.0.5 同源 hardening 提交窗口）；请以 **1.0.5** 为当前稳定发布。

## 1.0.3 (103)

- **生成部署文件恢复写入 `docker-compose.yml`**：修复「生成配置成功但无法启动容器」的问题；模板变量包含容器名、部署目录与 nginx 配置路径。
- **生成结果增加 nginx 骨架警告**：若缺少 `nginx.conf`、活动 conf 或 constant 依赖文件，提示先「上游同步」再生成参数。
- **配置持久化硬化**：`save()` 返回成功/失败；损坏 `config.json` 会备份到 Backups 后再回退默认；OpenList / Mount / PathMapping 字段缺失时可弹性解码。
- **仪表盘 Jellyfin 端口徽章修正**：非 Plex 时按当前类型显示正确 HTTP/HTTPS 代理端口。
- **容器操作 busy 锁**：启动/停止/重启互斥；生成页与菜单栏在操作中禁用或提示，失败时弹出错误信息。
- **恢复默认需确认**：连接页「恢复默认」增加 confirmationDialog，避免一键清空。
- 附带 OpenSpec 变更记录：`openspec/changes/fix-generate-compose-and-ui-guards/`。

## 1.0.2 (102)

- UI 架构升级：由原先传统的 TabView 标签页页面转换到了高颜值的双栏侧边栏 (`SidebarView`) 与仪表盘 (`DashboardView`) 架构，提升应用视觉质感并精简了导航流。
- 修复了路径映射页面的数据持久化 Bug：新增底部“保存配置”按钮底栏与弹框 Alert 反馈逻辑，确保所有对路径挂载与路径映射的前端配置变动都可被安全且原子地持久化写入磁盘。
- 统一了配置保存反馈交互：将 ConnectionView（连接）、RedirectSettingsView（302 控制）与 PathMappingView（路径映射）三处页面的保存统一为了“保存配置”文案并配置了统一的“已保存”弹框，解决了之前保存反馈有无、按钮文本各异的不一致缺陷。
- 清理废弃 Diagnostics 视图：彻底物理删除旧有冗余的 `DiagnosticsView.swift` 文件，将诊断系统完全归入 Dashboard 仪表盘页的“运行诊断”列表中。
- 优化长耗时任务在等待期间的用户反馈：在 UpstreamSyncView 处的上游 Git 同步期间，以及 CertificateView 处的 PFX 证书更新、acme.sh 自动化更新任务中增加了详细的在运行说明文本，杜绝了由于网络开销或外部脚本启动时只显示静态 ProgressView 菊花所引起的假死体验。
- 增加 Docker 页面的 Homebrew 补全指引：在 Docker 状态检测页面中，若本地未检测到 brew 环境，在“未找到”旁新增了可直接跳转到官网的 `安装指引` 链接。
- 修复「生成与部署」页模块居中缩水问题：更新全局 `FormGroupBoxStyle` 样式并对 `GenerateView` 的内部 `VStack` 的最大宽度设定为 `.frame(maxWidth: .infinity, alignment: .leading)`，使得整页在内容较窄时依然可以美观地左对齐拉伸撑满屏幕，恢复界面统一观感。

## 1.0.1 (101)

- 修复了在“生成配置”时，由于 JSONSerialization 对顶级非字典/非数组类型（String）序列化选项缺失 `.fragmentsAllowed` 导致的 App 崩溃闪退 Bug。
- 生成配置时排除了 `docker-compose.yml`，点击生成配置按钮时将不再触碰或覆盖该部署文件，以防用户自定义配置丢失。
- 修复了主窗口点击红叉关闭后，从状态栏菜单点击“显示主窗口”或点击 Dock 图标重新唤醒主界面的逻辑（重构为 SwiftUI 原生推荐的 `@Environment(\.openWindow)` 闭包桥接唤醒机制，弃用脆弱的 AppKit Delegate 代理拦截，彻底解决主窗口销毁后再次打开偶发性无响应、白屏或 Dock 点击失效的 Bug）。
- 进一步优化状态栏「显示主窗口」的查找和唤醒机制：针对 `NSApp.windows` 包含辅助窗口且排序不固定导致唤醒失效的 Bug，通过 `.canBecomeKey` 及 `.titled` 风格掩码精确过滤以准确定位并唤醒主界面，同时支持自动还原最小化窗口；引入 App Teardown 状态识别，完美解决了之前 Delegate 拦截导致 Cmd+Q 或系统注销时 App 无法正常退出的兼容性隐患。
- 优化了配置生成的 JSON 斜杠转义处理：生成 Nginx 配置文件时去除了路径正斜杠前多余的转义反斜杠，并在“扫描配置”时自动过滤旧有反斜杠污染，彻底解决了前端输入框内显示转义斜杠的体验缺陷。
- 软件官方名称及标识正式更名为 `embyExternalUrl-Manager` (Bundle ID: `com.embyexternalurl.manager`, 可执行文件名称: `EmbyExternalUrlManager`)，并同步适配了自动构建 `build_app.sh` 与打包 `package_dmg.sh` 脚本。
- 内置的 `plex2alist-core` 运行时和相关环境扫描工具保持正常工作。

## 1.0.0 (100)

- `embyExternalUrl-Manager` 独立版首个版本发布。
- 原生 SwiftUI + Rust core 架构，常驻系统菜单栏支持快捷启动/停止/重启/重载。
- 一键同步上游 `bpking1/embyExternalUrl` 核心脚本，提供部署目录同步覆盖保护。
- 证书配置、ACME 自动申请及到期时间显示集成。
- 集成 Docker 和 Nginx 状态检测。
