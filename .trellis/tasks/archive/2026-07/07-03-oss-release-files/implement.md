# 执行计划

## 步骤

### Step 1 — 清理测试产物
- 删除 `.playwright-mcp/`（本会话 Playwright 测试残留）。

### Step 2 — 配置类文件（先写，README 会引用）
- `LICENSE`：MIT 标准全文，`Copyright (c) 2026 ethereal`。
- `.gitignore`：Python + macOS + 产物；不忽略 `.trellis/` `.claude/` `.codex/` `.agents/`。
- `requirements.txt`：`pyserial`、`pyobjc-framework-Quartz`。
- `.editorconfig`：UTF-8/LF，html css js 2 空格，py 4 空格，末尾换行。

### Step 3 — 文档类
- `README.md`：按 prd 结构，引用真实端口 `8765`、串口 `/dev/cu.usbmodem3101`、venv 路径、按键映射（k1-k4）、动作类型表、权限两项、故障排查（串口占用/CGEvent off/中文输入法/权限弹窗）。
- `CHANGELOG.md`：Keep a Changelog 格式，`## [0.1.0] - 2026-07-03`，列已实现动作类型。
- `CONTRIBUTING.md`：环境搭建（指向 requirements.txt + venv）、PR 流程、约定指向 `.trellis/spec/`。

### Step 4 — git init（验证 .gitignore）
- `git init` + `git add -A` + `git status`：确认 `.playwright-mcp/` 等产物不出现、`.trellis/` 等被纳入。

## Review Gate

- README 写完先自检：陌生人能否照「快速开始」跑起来（端口/串口/权限三处真实可执行）。
- git status 是 .gitignore 的硬验证：产物不出现才算通过。

## 回滚

- 全部为新增文件，回滚 = 删除新增的 7 个文件 + 保留 git init（或 `rm -rf .git`）。
- 不影响 `vibe_control.py`/`index.html`/`config.json`。
