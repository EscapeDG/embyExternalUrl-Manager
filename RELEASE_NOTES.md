# embyExternalUrl-Manager Release Notes

## 1.0.1 (101)

- 修复了在“生成配置”时，由于 JSONSerialization 对顶级非字典/非数组类型（String）序列化选项缺失 `.fragmentsAllowed` 导致的 App 崩溃闪退 Bug。
- 生成配置时排除了 `docker-compose.yml`，点击生成配置按钮时将不再触碰或覆盖该部署文件，以防用户自定义配置丢失。
- 修复了主窗口点击红叉关闭后，从状态栏菜单点击“显示主窗口”或点击 Dock 图标无法重新唤醒主界面的 Bug（通过拦截窗口关闭动作为隐藏以保持实例生存）。
- 优化了配置生成的 JSON 斜杠转义处理：生成 Nginx 配置文件时去除了路径正斜杠前多余的转义反斜杠，并在“扫描配置”时自动过滤旧有反斜杠污染，彻底解决了前端输入框内显示转义斜杠的体验缺陷。
- 软件官方名称及标识正式更名为 `embyExternalUrl-Manager` (Bundle ID: `com.embyexternalurl.manager`, 可执行文件名称: `EmbyExternalUrlManager`)，并同步适配了自动构建 `build_app.sh` 与打包 `package_dmg.sh` 脚本。
- 内置的 `plex2alist-core` 运行时和相关环境扫描工具保持正常工作。

## 1.0.0 (100)

- `embyExternalUrl-Manager` 独立版首个版本发布。
- 原生 SwiftUI + Rust core 架构，常驻系统菜单栏支持快捷启动/停止/重启/重载。
- 一键同步上游 `bpking1/embyExternalUrl` 核心脚本，提供部署目录同步覆盖保护。
- 证书配置、ACME 自动申请及到期时间显示集成。
- 集成 Docker 和 Nginx 状态检测。
