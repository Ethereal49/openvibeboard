# Design — 用户文档 i18n

文档任务，无代码架构。design 只记命名约定、切换链接格式、重写边界、对应关系。

## 文件命名约定

| 主语言（英文） | 中文版 |
|---|---|
| `README.md`（GitHub 默认展示） | `README.zh-CN.md` |
| `CONTRIBUTING.md` | `CONTRIBUTING.zh-CN.md` |
| `CHANGELOG.md` | `CHANGELOG.zh-CN.md` |

- 后缀 `.zh-CN.md`（GitHub 开源惯例，优于 `.cn.md` / `_zh.md`）
- 英文版占用原名 → GitHub 仓库首页自动展示英文 README

## 切换链接格式

文件顶部插入一行（当前语言加粗、无链接；另一语言为链接）：

- 英文版：`**English** | [简体中文](./README.zh-CN.md)`
- 中文版：`[English](./README.md) | **简体中文**`

相对路径 `./`（同目录），GitHub Markdown 渲染可靠。

## 中英对应关系

- 核心**信息对等**（中文版有什么，英文版也有）
- **呈现不同**：英文版重写（结构/语气/精简度适配国际惯例），非逐字翻译
- 一对一对应，无跨文件依赖

## 英文版重写边界

**保留**（核心信息）：
- what/why（ESP32-S3 键盘 macOS 接管，不改固件）
- 构建（xcodegen + xcodebuild）、安装、权限（辅助功能 / 自动化）、配置（Settings UI）、动作类型表、模式表、路线图
- 技术示例：`open -a Codex`、`option+d`、串口路径 `/dev/cu.usbmodem3101`
- 中文语境示例（k2=粘贴「继续」）保留，英文版说明这是中文输入法绕过方案

**调整**：
- 语气：国际开源惯例（简洁、祈使句、主动语态、技术词英文不译）
- 结构：故障排查表保留但精简表述；冗长段合并
- CONTRIBUTING：加「Reporting Issues / Pull Requests」简短段（如何报 bug、提 PR），不引入 CoC/CLA

**不丢**：对照 `.zh-CN.md` 验收，英文版必须覆盖所有核心信息点。

## 中文版来源

当前 `README.md` / `CONTRIBUTING.md` / `CHANGELOG.md` → `git mv` 到 `.zh-CN.md`，内容不改，仅顶部加切换链接。零风险（信息不丢）。

## Trade-offs

| 决策 | 选择 | 代价 |
|---|---|---|
| 英文版策略 | 重写适配（非翻译） | 工作量大，但专业 + 国际友好 |
| CHANGELOG | 双语 | 每次发版维护双份 |
| CONTRIBUTING | 适度加 PR/issue 指引 | 不正式化（无 CoC/CLA），平衡小项目姿态 |

## Rollback

- 文件级 `git revert`：英文版不满意可单独回滚，不影响中文版
- 中文版 = 当前内容迁移，零风险
- 整批回滚：`git revert` 提交即可（mv 用 git rename，历史保留）
