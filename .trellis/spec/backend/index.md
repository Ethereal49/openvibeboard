# Backend 开发约定

> VibeBoard PC 端守护进程的编码约定。

本项目 **不是** 传统后端服务，没有数据库、ORM、迁移、路由框架。它是单个 Python 守护进程，核心是「HTTP 配置服务 + 串口监听 + 按键动作分发」。读这里的 spec 之前，先接受这个前提，不要臆造数据库层或服务化抽象。

---

## 技术栈

- Python 3 标准库为主（`http.server`、`threading`、`subprocess`、`json`、`re`）
- `pyserial` —— 串口监听（必需）
- `pyobjc` / `Quartz` —— CGEvent 注入（**可选**，hold 模式必需，import 失败时降级）
- macOS 系统调用：`osascript`（tap 击键）、`open` 等 shell 命令

---

## 约定索引

| 文件 | 内容 |
|------|------|
| [Directory Structure](./directory-structure.md) | 单文件架构、分发链、config.json schema |
| [Error Handling](./error-handling.md) | optional import 降级、守护进程不崩、API 错误响应 |
| [Logging Guidelines](./logging-guidelines.md) | `log()` 格式、何时记、不记什么 |
| [Quality Guidelines](./quality-guidelines.md) | CGEvent flags 坑、CONFIG_LOCK、权限前置、禁止模式 |

> 数据库约定：本项目无数据库，`config.json` 是唯一的持久化（键映射配置）。无需 ORM/迁移 spec。

---

**语言**：spec 与代码注释/docstring 统一用中文。
