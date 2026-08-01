# Design: fix-v104-hardening

## Context

v1.0.3 发布后复盘发现配置持久化、进程执行、Compose 生成与 UI 反馈四类正确性缺陷。当前真实 Docker 环境缺失，本轮只修代码与构建链路，不做真实 302 联调。OpenSpec 等级为 required，上一 change 的 `ui-guards` spec 缺少 Scenario 导致 `validate --strict` 失败。

## Goals / Non-Goals

**Goals:**
- 配置损坏时不再可能静默丢失用户配置。
- Docker 子进程任意输出量下不阻塞、可超时终止。
- 所有保存路径的失败对用户可见。
- 已存在的自定义 `docker-compose.yml` 不被生成流程覆盖。
- `openspec validate --strict` 对两个 change 均通过；`swift build` 通过。

**Non-Goals:**
- 不做真实 Docker/OpenList/Plex 302 smoke（环境未就绪）。
- 不做签名/公证、Keychain 迁移。
- 不发布 v1.0.4 Release（仅对齐版本号与 RELEASE_NOTES，发布待用户指令）。
- 不新增 Swift 测试 target 体系（工作量独立立项）。

## Decisions

1. **load() 失败语义：备份失败 → 保留原文件与内存配置。**
   备选：仍回退默认但标记错误。选择前者，因为数据安全优先于启动成功率；UI 通过 `lastPersistenceError` 提示用户手动处理。
2. **并发管道读取：用 `readabilityHandler` 后台读取 + `waitUntilExit` 超时轮询。**
   备选：`readDataToEndOfFile` 顺序读（现状，死锁源）；GCD `DispatchIO`。选择 readabilityHandler，改动最小且同步/异步两条路径可共用。
3. **Compose 保留策略：存在即跳过并 warning。**
   备选：每次备份后覆盖（现状，违背 v1.0.1 承诺）；三向合并（过度设计）。选择存在即跳过，用户需重新生成时手动删除或后续加显式开关。
4. **模板转义：compose 路径值用双引号包裹并转义 `"` 与 `\`。**
   备选：引入 YAML 库（新依赖，违背最小改动）。手写的引号转义覆盖空格、`#`、`:`、换行主要风险。
5. **busy 锁补充 defer 语义**：up/down/restart 用 defer 保证 `isBusy` 复位，避免异常路径永久占用。
6. **上一 change 的 spec 补 Scenario** 而不新建迁移：内容未变，仅补验收场景使 strict 校验通过。

## Risks / Trade-offs

- Compose 存在即跳过 → 用户改端口后重新生成不生效。→ warning 文案明确提示删除旧文件再生成。
- 备份命名改毫秒+hash → 备份目录文件变多。→ 文件名仍可排序，保留现有清理策略不变。
- `cargo build --locked` → lockfile 过期时构建失败。→ 这是预期行为，防止再次发出不一致包。
