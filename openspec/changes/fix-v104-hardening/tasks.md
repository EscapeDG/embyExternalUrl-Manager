# Tasks: fix-v104-hardening

## 1. ConfigService

- [x] 1.1 `load()` decode 失败：备份失败时保留原文件与内存配置，不静默回退默认；备份成功文案与事实一致
- [x] 1.2 生成流程跳过已存在的 `docker-compose.yml` 并给出 warning
- [x] 1.3 compose 路径变量加引号并转义 `"` / `\`
- [x] 1.4 Plex 骨架警告只检查 Plex 模板实际 import 的 helper

## 2. DockerService

- [x] 2.1 `runCommand` 与 `runCommandSync` 改为并发读取 stdout/stderr，超时路径终止并排空
- [x] 2.2 up/down/restart 用 defer 保证 `isBusy` 复位
- [x] 2.3 `ps()` 移除 `containers.first` 回退，仅精确匹配候选名

## 3. TemplateRenderer

- [x] 3.1 备份文件名加入毫秒与短 hash，避免同秒/同名碰撞

## 4. UI 保存反馈

- [x] 4.1 PathMappingView 保存失败显示错误而非「已保存」
- [x] 4.2 RedirectSettingsView 保存失败显示错误而非「已保存」
- [x] 4.3 ConnectionView 恢复默认失败时提示；UpstreamSyncView / CertificateView 的 save() 检查返回值

## 5. 版本与构建

- [x] 5.1 版本提升 `1.0.4 (104)`（build_app.sh / package_dmg.sh / RustCore Cargo.toml / main.rs）
- [x] 5.2 提交对齐后的 `RustCore/Cargo.lock`；build_app.sh Rust 构建加 `--locked`
- [x] 5.3 更新 `RELEASE_NOTES.md` 增加 1.0.4 条目
- [x] 5.4 修正 README「Plex 全链路 smoke 已通过」为待验证口径

## 6. 上一 change 修复

- [x] 6.1 为 `fix-generate-compose-and-ui-guards` 的 ui-guards spec 补 Scenario

## 7. 验证

- [x] 7.1 `openspec validate fix-v104-hardening --strict` 通过
- [x] 7.2 `openspec validate fix-generate-compose-and-ui-guards --strict` 通过
- [x] 7.3 `swift build` 通过
- [x] 7.4 `cargo test --locked --manifest-path RustCore/Cargo.toml` 通过
- [x] 7.5 更新 LMV status / next_tasks / logs
