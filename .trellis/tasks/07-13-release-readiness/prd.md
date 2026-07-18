# OpenVibeBoard release readiness

## Goal

把 OpenVibeBoard 从“本机可构建运行”推进到可重复构建、可公开展示、可分发更新的 v0.2.0：串口可配置、README 有真实截图、GitHub Actions 持续验证、产物具备清晰的签名/公证边界，并发布 GitHub Release。

## Confirmed facts

- 当前版本为 `0.2.0 (1)`，仓库默认分支 `master`，GitHub 仓库公开。
- GitHub 当前没有 tag 或 Release，也没有 `.github/workflows/`。
- 串口路径在 `SerialMonitor.path` 硬编码为 `/dev/cu.usbmodem3101`，波特率固定 115200。
- Settings 已有 sidebar-detail 编辑工作流，但没有通用/设备配置区。
- 仓库没有截图或 asset catalog。
- App 开启 sandbox 和 `com.apple.security.device.serial` entitlement。
- 本机只有 `Apple Development` identity，没有 `Developer ID Application` identity。
- 本机存在 `notarytool 1.1.2`，但环境中没有可识别的 notarization credential 变量。
- 用户确认当前没有 Developer ID / App Store Connect 公证凭据；公开签名、公证、staple 只能保留可执行脚本与 CI 接口，实际公证标记为 blocked。
- 当前显式 roadmap：串口路径配置、README 截图、CI/CD、签名/公证、GitHub Release；历史材料还提过 Sparkle 自动更新和 badge。

## Requirements

### R1. Serial device configuration

- 用户能在 Settings 中选择可用串口，而不是修改源码。
- 默认优先匹配 ESP32-S3 的 `/dev/cu.usbmodem*`；已保存路径不存在时应显示状态并允许重新选择。
- 串口切换后监听器安全关闭旧端口并连接新端口，不重启 App。
- 配置持久化，现有按键映射 schema 保持兼容。

### R2. Documentation visuals

- 使用最新安装版生成真实 Settings 截图，仓库内有稳定的文档资源目录和命名约定。
- README 中英文版都展示截图，并保持相对链接可用。

### R3. CI and badge

- GitHub Actions 在 macOS runner 上执行 xcodegen、构建和测试。
- README 中英文版显示 CI 状态 badge。
- workflow 不依赖本机硬件、辅助功能权限或真实串口。

### R4. Packaging, signing, notarization

- 提供可重复的 Release 构建和打包脚本，生成版本化归档与 checksum。
- 本地 ad-hoc 开发安装与公开分发签名必须明确区分。
- 若具备 Developer ID 与 notarization credentials，产物完成签名、公证、staple 和 Gatekeeper 验证；否则不得声称已公证。
- 本轮缺少 Developer ID 与 notarization credentials，因此只能验证 ad-hoc 测试产物；Developer ID 签名、公证、staple、Gatekeeper 通过状态必须明确标记为 blocked。

### R5. GitHub Release v0.2.0

- 创建目标版本为 `v0.2.0` 的 **Draft GitHub Release**，附双语摘要、源码构建说明、权限说明、测试归档和 checksum。
- 测试归档必须显著标记为 `ad-hoc signed, unnotarized`，不得描述为生产安装包或正式发布。
- Draft 阶段不创建正式 Git tag；未来取得凭据、生成 Developer ID 签名且已公证的产物后，再单独验收并发布 tag/Release。
- 创建 Draft 前必须验证版本、目标 commit、产物和 checksum 一致，且 Git 工作区干净、目标 commit 已 push。

### R6. Update strategy

- v0.2.0 不引入 Sparkle，不生成或保管更新签名密钥。
- README 明确当前通过 GitHub Releases 手动更新；自动更新作为未来独立任务评估。

## Acceptance Criteria

- [x] 串口可在 UI 中选择并持久化，切换后 live reconnect；有纯逻辑与状态测试。
- [x] 中英文 README 展示来自最新 App 的真实截图。
- [x] GitHub Actions build/test 通过，badge 指向真实 workflow。
- [x] Release 脚本能从 clean checkout 生成版本化产物与 SHA-256 checksum。
- [x] 签名、公证、staple、Gatekeeper 的实际状态有命令证据；缺凭据时明确 blocked，不做虚假完成声明。
- [x] 目标版本为 `v0.2.0` 的 Draft GitHub Release 已创建，测试附件、checksum 和目标 commit 一致，且未创建正式 Git tag、未公开发布。
- [x] README 已说明通过 GitHub Releases 手动更新，Sparkle 延期原因已记录。
- [x] 相关 spec、README、CHANGELOG 同步，测试通过，提交与 push 完成。

## Out of Scope

- Mac App Store 上架。
- iOS/iPadOS 移植。
- 修改 ESP32-S3 固件或串口协议。
- v0.2.0 引入 Sparkle 或其他 app 内自动更新框架。
- 在取得 Developer ID 与 notarization credentials 前公开发布生产安装包。
