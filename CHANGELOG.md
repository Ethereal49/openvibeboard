# Changelog

本项目所有重要变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

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

[0.1.0]: https://github.com/Ethereal49/openvibeboard/releases/tag/v0.1.0
