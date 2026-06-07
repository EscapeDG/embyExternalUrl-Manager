# embyExternalUrl-Manager

`embyExternalUrl-Manager` 是一个 macOS 原生图形化管理器，用于配置和管理基于 `nginx + njs` 的媒体库 302 直链方案。

它面向 Emby、Jellyfin 和 Plex 用户，帮助把媒体服务、OpenList 直链后端、Docker 容器、Nginx 配置和上游脚本同步流程集中到一个桌面应用中处理。

## 目标链路

```text
Emby / Jellyfin / Plex
    -> nginx + njs
    -> embyExternalUrl 上游脚本
    -> OpenList 直链
    -> 302 重定向播放
```

## 主要功能

- 配置 Emby、Jellyfin、Plex 源服务地址和代理端口。
- 配置 OpenList 地址、Token、公开访问地址和签名参数。
- 生成 Docker Compose、Nginx 和 njs 参数模板。
- 管理 302 重定向开关、转码直链、路由缓存、回源策略和路径映射。
- 同步上游 `embyExternalUrl` 仓库的 Nginx/njs 脚本，并保护本地参数文件。
- 提供 Docker、Nginx 状态检测和菜单栏快捷启动、停止、重启、重载操作。
- 支持证书导入、PFX 刷新和 acme.sh 自动签发辅助流程。

## 环境要求

- macOS 14 或更新版本。
- Swift 5.9 或更新版本。
- Rust toolchain，用于构建本地辅助 core。
- Docker Desktop 或 OrbStack。
- 已部署或可访问的 OpenList 服务。

## 本地构建

```bash
swift build
cargo test --manifest-path RustCore/Cargo.toml
cargo build --release --manifest-path RustCore/Cargo.toml
./Scripts/build_app.sh
./Scripts/package_dmg.sh
```

构建完成后，应用包会输出到 `dist/embyExternalUrl-Manager.app`，DMG 会输出到 `dist/embyExternalUrl-Manager-版本号.dmg`。

## 测试现状与已知限制

- **测试现状**：目前主要在 macOS 宿主机 **Plex** 配合 Docker Nginx/njs 及 OpenList 后端下完成了全链路 302 拦截播放的 smoke test。
- **Emby/Jellyfin 状态**：虽然界面和核心代码已同步继承了上游的 302 配置文件生成与管理能力，但由于个人缺乏真实的 Emby/Jellyfin 测试环境，**尚未经过完整的生产联调验证**，非常欢迎有环境的用户测试并提 Issue 反馈。
- **凭据安全**：当前版本尚未把 OpenList Token 迁移到 macOS Keychain，目前以明文形式保存在用户的 Application Support 配置目录中。请不要在公开 issue 中暴露该敏感信息。
- **系统拦截**：未使用 Developer ID 签名和 Apple 公证的 DMG 可能会被 Gatekeeper 拦截。

更多安全说明与报告漏洞方式见 `SECURITY.md`。

## 许可证

本项目以 MIT License 开源，详见 `LICENSE`。

上游 `bpking1/embyExternalUrl` 同样采用 MIT License。上游版权和许可说明见 `NOTICE`，使用或分发本项目时也请遵守上游项目的许可要求。

## 项目关系

本项目是围绕上游 302 直链能力制作的 macOS 管理器，重点是降低配置、同步、生成和本地运行验证成本。核心 Nginx/njs 规则和 302 直链思路来自上游项目。

## 致谢

感谢源作者 [bpking1](https://github.com/bpking1) 开源并维护 [bpking1/embyExternalUrl](https://github.com/bpking1/embyExternalUrl)。没有上游项目提供的核心脚本和思路，这个图形化管理器也就没有落地基础。

使用本项目时，请同时关注并尊重上游项目的说明、更新和许可要求。
