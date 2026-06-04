# embyExternalUrl-Manager Agent Rules

本仓库是 `embyExternalUrl-Manager` 的独立 GitHub 仓库，远端为：

```text
https://github.com/EscapeDG/embyExternalUrl-Manager.git
```

## 工作范围

- 默认只在当前仓库根目录内工作。
- 不把发布分支、发布 worktree、临时目录或打包缓存创建到桌面同级目录。
- 需要创建发布分支的本地 worktree 时，必须放在项目目录下：

```text
.release-worktrees/<branch-name>
```

示例：

```bash
git worktree add .release-worktrees/release-v1.0.1 -b release/v1.0.1 main
```

## GitHub 同步规则

- 默认远端只使用 `origin`，指向 `EscapeDG/embyExternalUrl-Manager`。
- `main` 是默认开发和发布基线分支。
- 发布分支命名使用 `release/vX.Y.Z`。
- 发布标签命名使用 `vX.Y.Z`。
- 发布前必须推送对应提交和标签到 GitHub。
- GitHub Release 必须挂载对应版本的 DMG 产物，并在 release notes 中写明 SHA256。
- 如果创建了发布分支，必须同步推送到 GitHub：

```bash
git push -u origin release/vX.Y.Z
```

## 发布流程

1. 确认工作区干净。
2. 更新版本号、build number 和相关脚本。
3. 运行最小验证：

```bash
swift build
cargo test --manifest-path RustCore/Cargo.toml
./Scripts/build_app.sh
./Scripts/package_dmg.sh
```

4. 确认 `dist/embyExternalUrl-Manager-X.Y.Z.dmg` 通过 `hdiutil verify`。
5. 计算并记录 SHA256。
6. 提交版本变更并推送到 GitHub。
7. 创建并推送 `vX.Y.Z` 标签。
8. 创建 GitHub Release 并上传 DMG。

## 不应上传的内容

- `.build/`
- `.swiftpm/xcode/`
- `RustCore/target/`
- `dist/`
- `.release-worktrees/`
- `.DS_Store`
- 本机绝对路径、个人姓名、账号隐私信息或临时调试文件

## 上游关系

本项目是独立非 Fork 仓库。上游核心脚本来源和致谢对象为：

```text
https://github.com/bpking1/embyExternalUrl
```

不得把 `origin` 改回上游仓库，也不得把本项目作为 fork 发布。
