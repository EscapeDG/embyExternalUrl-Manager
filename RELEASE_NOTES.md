# embyExternalUrl-Manager Release Notes

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
