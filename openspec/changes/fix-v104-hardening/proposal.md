# Proposal: fix-v104-hardening

## Why

v1.0.3 复盘发现多个正确性缺陷：损坏配置在备份失败时被丢弃、Docker 子进程大输出可能管道死锁、部分页面保存失败仍提示「已保存」、生成流程无条件覆盖用户自定义 `docker-compose.yml` 且路径未做 Compose/YAML 转义。这些问题直接影响配置数据安全与部署可靠性，必须在真实链路 smoke 前修复。

## What Changes

1. **配置持久化**：`load()` 解码失败时优先尝试备份；备份失败则保留磁盘原文件并保留内存中的现有配置（首次启动无现有配置时才回退默认），并把失败信息暴露给 UI。
2. **进程执行**：重构 `DockerService` 的 `runCommand` / `runCommandSync`，在进程运行期间并发读取 stdout/stderr，避免超过管道容量后子进程阻塞；超时路径终止进程并排空管道。
3. **保存反馈**：所有 `save()` 调用点（PathMapping、RedirectSettings、Connection 重置、UpstreamSync、Certificate）检查返回值，失败时展示错误而非「已保存」。
4. **Compose 生成**：部署目录已存在 `docker-compose.yml` 时跳过覆盖并给出「保留现有文件」提示（不再静默覆盖）；compose 模板中的路径值加双引号并转义，避免 `#`、`:`、空格、换行破坏 YAML。
5. **容器匹配**：`ps()` 仅在候选名精确匹配成功时判定容器，移除回退到任意首个结果的行为。
6. **备份命名**：`TemplateRenderer.writeRendered` 备份文件加入毫秒级时间戳与源文件 hash 前缀，避免一秒内或跨部署同名碰撞。
7. **版本一致性**：提交 `RustCore/Cargo.lock` 与 `Cargo.toml` 的 `1.0.3` 对齐；构建脚本 Rust 构建改用 `--locked`，在 lockfile 过期时直接失败。
8. **OpenSpec 修复**：为上一个 change 的 `ui-guards` spec 补充缺失 Scenario，使 `openspec validate --strict` 通过。
9. **GenerateView 容器操作反馈**：启动/停止/重启失败时展示命令输出，不再静默丢弃。
10. **版本与发布说明**：版本提升至 `1.0.4 (104)`，更新 `RELEASE_NOTES.md`；修正 README 中「Plex 全链路 smoke 已通过」与项目文档不一致的表述（标注为待验证）。

## Capabilities

### New Capabilities

- `config-persistence`: 配置加载失败时的备份/保留语义与保存结果反馈
- `process-execution`: 外部进程并发读取、超时终止与管道安全
- `deployment-generate`: Compose 文件保留策略与模板转义
- `docker-service`: 容器精确匹配与 busy 保护

### Modified Capabilities

（无；`openspec/specs/` 主目录当前为空，上一 change 未归档。）

## Impact

- `Sources/EmbyExternalUrlManager/Services/ConfigService.swift`：load/save 错误路径、生成流程 compose 策略
- `Sources/EmbyExternalUrlManager/Services/DockerService.swift`：进程读取与容器匹配
- `Sources/EmbyExternalUrlManager/Services/TemplateRenderer.swift`：备份命名
- `Sources/EmbyExternalUrlManager/Views/{PathMappingView,RedirectSettingsView,ConnectionView,UpstreamSyncView,CertificateView}.swift`：保存失败反馈
- `Sources/EmbyExternalUrlManager/Resources/Templates/docker-compose.yml`：路径引号
- `Scripts/build_app.sh`、`RustCore/Cargo.lock`、`RELEASE_NOTES.md`、`README.md`
- `openspec/changes/fix-generate-compose-and-ui-guards/specs/ui-guards/spec.md`：补 Scenario
