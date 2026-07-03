# 贡献指南

欢迎贡献！提 issue 或 PR 前请先读这份指南。

## 开发环境

```bash
git clone https://github.com/ethereal/openvibeboard.git
cd openvibeboard
uv sync                                   # 创建 .venv 并装依赖
uv run python -u vibe_control.py          # 运行守护进程
```

运行需要：macOS、已退出 VibeBoard 客户端、授权「自动化」+「辅助功能」（见 [README](README.md) 权限章节）。环境用 [uv](https://docs.astral.sh/uv/) 管理，依赖声明在 `pyproject.toml`，锁定版本在 `uv.lock`。

## 编码约定

本项目用 Trellis 管理开发流程，**编码约定的唯一事实来源是 `.trellis/spec/`**：

- [`backend/`](.trellis/spec/backend/) —— Python 守护进程约定（CGEvent modifier flag 坑、剪贴板方案、错误处理、日志、质量）
- [`frontend/`](.trellis/spec/frontend/) —— Web UI 约定（录制 `event.code` 坑、XSS 防护、内联风格）
- [`guides/`](.trellis/spec/guides/) —— 通用思考指南

改代码前先读对应 spec。**约定优先于个人偏好**；若认为某约定有害，先开 issue 讨论，不要偷偷另搞一套。

## 提交规范

- 小步提交，commit message 写清「改了什么 + 为什么」。
- 不引入新依赖前先讨论。
- 改 `vibe_control.py` 的 CGEvent / 动作分发逻辑后，务必手动回归验证 `cmd` / `key tap` / `key hold` / `text` 四种动作（验证步骤见 [`.trellis/spec/backend/quality-guidelines.md`](.trellis/spec/backend/quality-guidelines.md)）。

