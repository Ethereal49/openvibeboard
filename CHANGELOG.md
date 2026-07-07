# Changelog

本项目所有重要变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.0] - 2026-07-07

Swift 原生重写：从单文件 Python 守护进程改为 SwiftUI menu bar app。

### 重写

- SwiftUI `MenuBarExtra` 状态栏常驻（替代 v0.1 退出 Web 客户端、命令行跑守护进程的体验）
- ORSSerialPort 串口监听（SPM 依赖）
- CGEvent 按键注入：`tap` 与 `hold` 统一走 CGEvent，modifier 用 `CGEventSetFlags` 挂 flag（合并 v0.1 的 osascript + CGEvent 双路径）
- SwiftUI Settings 配置面板（替代 Web UI `index.html`），保存即热生效；deployment target 提到 macOS 15
- `SMAppService` 应用内开机自启（菜单勾选，无需 launchd / 改系统文件）
- 配置持久化迁移到 `~/Library/Application Support/OpenVibeBoard/config.json`（schema 与 v0.1 兼容，首启用硬编码 `defaultConfig`）
- 改名 VibeBoard → OpenVibeBoard（避开 `/Applications/VibeBoard.app` 的 Accessibility TCC 授权混淆）

### 测试

- Swift Testing：`parseKey` / Codable / `parseLine` / `decideAction` 纯逻辑参数化测试（30 tests / 5 suites）
- 为可测性抽纯函数（`ConfigStore` 注入 URL、`SerialMonitor.parseLine` 抽离 delegate、`ActionDispatcher.decideAction` + `Action` 枚举），行为不变（C 实测门仍是权威）

### 变更

- v0.1 Python 版（`vibe_control.py` / `index.html` / `config.json` / `pyproject.toml` / `uv.lock`）移至 `archive/python-v0.1/`，保留作串口协议 / CGEvent flags 坑的逻辑参考

## [0.1.0] - 2026-07-03

首个开源发布。

### 新增

- 单进程守护进程 `vibe_control.py`：HTTP 配置服务（`127.0.0.1:8765`）+ 串口监听线程
- 三种动作类型：`cmd`（shell 命令）、`key`（击键）、`text`（文本粘贴）
- 两种击键模式：`tap`（osascript keystroke）、`hold`（CGEvent，按住语义）
- Web 配置 UI（`index.html`）：热生效保存、组合键物理录制、文本动作 textarea
- `text` 动作用剪贴板方案（pbcopy + Cmd+V）绕过中文输入法
- 串口协议：解析 ESP-IDF `button down kN` / `button up kN` 日志
- 组合键录制用 `event.code` 规避 macOS Option 让 `event.key` 失真的坑
- 用 [uv](https://docs.astral.sh/uv/) 管理环境与依赖：`pyproject.toml` 声明依赖、`uv.lock` 锁版本、`uv sync` 复现、`uv run` 运行（取代 requirements.txt）

[0.2.0]: https://github.com/Ethereal49/openvibeboard/releases/tag/v0.2.0
[0.1.0]: https://github.com/Ethereal49/openvibeboard/releases/tag/v0.1.0
