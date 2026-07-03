# 开源项目发布文件补全

## Goal

补全开源发布标配文件，使仓库达到成熟开源项目的发布标准。**不新增功能**，仅补文档与配置文件。

## Requirements

新增 7 个文件：

| 文件 | 内容要点 |
|------|----------|
| `README.md` | 一句话定位、功能特性、前提（macOS/Python3/VibeBoard 客户端）、快速开始（venv+依赖+运行）、Web 配置、按键映射与动作类型（cmd/key/text、tap/hold）、权限（自动化/辅助功能）、项目结构、串口协议、故障排查、开发（trellis spec）、MIT 许可 |
| `LICENSE` | MIT 标准全文，版权 `Copyright (c) 2026 ethereal` |
| `.gitignore` | Python（`__pycache__`/`*.pyc`/venv）、macOS（`.DS_Store`）、项目产物（`.playwright-mcp/`、`*.tmp`）、保留 `.trellis/`/`.claude/`/`.codex/`/`.agents/` 不忽略 |
| `pyproject.toml` + `uv.lock` | 依赖声明 + 锁定版本（uv 管理；取代 requirements.txt） |
| `CHANGELOG.md` | Keep a Changelog 格式，v0.1.0 初始发布（含 cmd/key/tap/hold + text/录制） |
| `CONTRIBUTING.md` | 简短：环境搭建、提 issue/PR 流程、代码约定指向 `.trellis/spec/` |
| `.editorconfig` | UTF-8、LF、缩进 2 空格（html/css）+ 4 空格（py）、末尾换行 |

## 关键决策

- **协议**：MIT（用户确认）。
- **改用 uv 管理环境**（用户后续要求，推翻原「不加 pyproject」）：`pyproject.toml`（application 模式 `package = false`）声明依赖 + `uv.lock` 锁版本；`uv sync` 建 `.venv`、`uv run` 运行；删除 `requirements.txt`（单源）。`requires-python = ">=3.10"`（pyobjc 12.x 要求）。
- **AI 工具目录策略**：`.trellis/` `.claude/` `.codex/` `.agents/` → 提交（团队共享 spec/skills）；`.playwright-mcp/` → 忽略并清理（测试残留）。
- **README 语言**：中文（与项目 UI、docstring、用户群一致）。
- **git init**：项目当前非 git 仓库，发布前必须 `git init`（操作非文件，收尾时提示用户执行）。

## Acceptance Criteria

- [x] 7 个文件全部就位，内容非占位（README 引用真实端口 8765、串口路径、venv 路径）。
- [x] `LICENSE` 为 MIT 标准全文，含版权行 `Copyright (c) 2026 ethereal`。
- [x] `.gitignore` 忽略 Python/macOS/产物，且不忽略 `.trellis/` 等 AI 目录（git status 验证）。
- [x] `.playwright-mcp/` 目录已清理。
- [x] `pyproject.toml` + `uv.lock` 能 `uv sync` 复现运行环境（已验证依赖 import + uv.lock 生成 + .venv 忽略）。
- [x] README 的「快速开始」步骤可被陌生人照做跑起来。
- [x] `git init` 后 `git status` 不显示应被忽略的产物（playwright-mcp/__pycache__/.DS_Store/.runtime/settings.local 均未出现）。

> 待办（非阻塞，发布前用户处理）：README/CHANGELOG 的 GitHub URL `github.com/ethereal/openvibeboard` 为占位，需改成真实仓库地址；首次 commit + 推 GitHub。

## Out of Scope

- 功能代码改动（`vibe_control.py`/`index.html`/`config.json` 不动）。
- CI/CD（GitHub Actions）、badge、截图素材（后续单独做）。
- 打包成 .app / launchd 自启（已在项目待办里，不属本次）。
