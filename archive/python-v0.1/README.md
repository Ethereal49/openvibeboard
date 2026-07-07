# OpenVibeBoard v0.1（Python 版，已归档）

> ⚠️ 本目录是 OpenVibeBoard **v0.1**（单文件 Python 守护进程）的归档代码，**不再维护、不参与构建**。
>
> v0.2.0 起项目已整体重写为 Swift 原生 menu bar app（见仓库根 `OpenVibeBoard/`）。日常使用和开发请看[根 README](../../README.md)。

## 为什么保留

v0.2.0 的 Swift 实现多处以本目录 Python 代码为**逻辑参考**，遇到行为对照时回这里查：

| 领域 | 参考价值 | Swift 对应 |
|------|----------|-----------|
| 串口协议 | 解析 ESP-IDF `button down/up kN` 日志、行读取与重连 | `OpenVibeBoard/Serial/SerialMonitor.swift` |
| CGEvent modifier flags 坑 | 用 `CGEventSetFlags` 挂 flag，**不**单独发 modifier keydown（否则组合键只打出单字符 / 卡住） | `OpenVibeBoard/Key/KeyInjector.swift` |
| 剪贴板绕中文输入法 | `text` 动作走剪贴板 + `Cmd+V`（v0.1 `pbcopy`；v0.2 `NSPasteboard`），不用 osascript keystroke | `OpenVibeBoard/Actions/ActionDispatcher.swift` |
| config.json schema | 键名 / 字段（`type`/`value`/`mode`/`enter`/`desc`） | `OpenVibeBoard/Models/Config.swift`（保持 schema 兼容） |

## 文件清单

- `vibe_control.py` —— 守护进程（HTTP 配置服务 + 串口监听 + 动作分发）
- `index.html` —— Web 配置 UI（原生 HTML/JS，无框架）
- `config.json` —— 默认按键映射（v0.1 用；v0.2.0 首启用 Swift 硬编码 `defaultConfig`，根 config.json 不再被运行时读取）
- `pyproject.toml` / `uv.lock` —— 依赖声明与锁文件（uv 管理）

## 历史运行方式（仅供回溯参考）

```bash
cd archive/python-v0.1
uv sync
uv run python -u vibe_control.py   # http://127.0.0.1:8765 配置，需退出 VibeBoard 客户端释放串口
```
