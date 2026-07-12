# 用户文档 i18n（README / CONTRIBUTING / CHANGELOG 中英双语）

## Goal

面向国际开源受众，把用户文档从纯中文改为**中英双语、英文为主**（GitHub 默认展示英文 README），顶部双向语言切换链接。提升项目国际可见性与可贡献性。

## Background

- v0.2.0 Swift 重写已闭环（A-G + Settings 改进，commit 至 `0e42733`），代码已 push origin。
- 当前 `README.md` / `CONTRIBUTING.md` / `CHANGELOG.md` 均纯中文（G 阶段刚改写为 Swift 主体）。
- 用户提出 i18n = 项目目标转向**开源分发导向**（P0 开源可见性第一项）。
- 项目无现成 i18n 惯例（首次引入）。

## Confirmed Decisions

- **主语言英文**：原名保留（`README.md` / `CONTRIBUTING.md` / `CHANGELOG.md` = 英文），GitHub 默认展示英文 README。
- **中文版命名**：`.zh-CN.md` 后缀（`README.zh-CN.md` 等，GitHub 开源惯例）。
- **范围**：README + CONTRIBUTING + CHANGELOG 三件双语。
- **英文版策略**：重写适配国际开源惯例（非逐字翻译），调整结构 / 语气 / 精简度；CONTRIBUTING 适度加 PR/issue 指引，不引入 CoC/CLA。
- **中文版策略**：当前内容原样迁移到 `.zh-CN.md`（信息零丢失），仅加切换链接。
- **双向切换链接**：文件顶部，当前语言加粗无链接、另一语言链接。

## Out of Scope

- **`.trellis/spec/` 保持中文** —— AI 内部约定，spec 明确「统一中文」。
- **`AGENTS.md` 保持中文** —— AI 工具入口文档。
- **代码 UI i18n** —— macOS app 跟随系统语言（SwiftUI 自动）。
- **其他语言**（日/韩等）—— 本次只中英。
- **CoC / CLA / issue 模板** —— 小项目，不正式化（CONTRIBUTING 只加简短 PR/issue 指引文字）。

## Requirements

- `README.md`（英文，重写适配）+ `README.zh-CN.md`（中文，当前内容迁移）
- `CONTRIBUTING.md`（英文，重写 + 适度 PR/issue 指引）+ `CONTRIBUTING.zh-CN.md`（中文，当前迁移）
- `CHANGELOG.md`（英文，翻译现有 v0.1.0/v0.2.0 条目）+ `CHANGELOG.zh-CN.md`（中文，当前迁移）
- 每个文件顶部双向语言切换链接
- 中文版核心信息零丢失（构建/安装/权限/配置/动作/路线图等完整保留）

## Acceptance Criteria

- [x] 6 个文件齐：`README.md` / `README.zh-CN.md` / `CONTRIBUTING.md` / `CONTRIBUTING.zh-CN.md` / `CHANGELOG.md` / `CHANGELOG.zh-CN.md`
- [x] 每个文件顶部有双向切换链接（当前语言加粗）
- [x] GitHub 仓库首页默认展示英文 README
- [x] 中文版（`.zh-CN.md`）内容与改前一致（git diff 仅文件名 + 顶部链接）
- [x] 英文版核心信息完整（对照中文版验收，无信息丢失）
- [x] spec / AGENTS.md 未被改动
