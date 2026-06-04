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
./Scripts/build_app.sh
./Scripts/package_dmg.sh
```

构建完成后，应用包会输出到 `dist/embyExternalUrl-Manager.app`，DMG 会输出到 `dist/embyExternalUrl-Manager-版本号.dmg`。

## 项目关系

本项目是围绕上游 302 直链能力制作的 macOS 管理器，重点是降低配置、同步、生成和本地运行验证成本。核心 Nginx/njs 规则和 302 直链思路来自上游项目。

## 致谢

感谢源作者 [bpking1](https://github.com/bpking1) 开源并维护 [bpking1/embyExternalUrl](https://github.com/bpking1/embyExternalUrl)。没有上游项目提供的核心脚本和思路，这个图形化管理器也就没有落地基础。

使用本项目时，请同时关注并尊重上游项目的说明、更新和许可要求。
