# Implement — 用户文档 i18n

跨多次会话可一次完成。按序，每步可验证。

## 执行顺序

### 1. 中文版迁移（机械，零风险）
```bash
git mv README.md README.zh-CN.md
git mv CONTRIBUTING.md CONTRIBUTING.zh-CN.md
git mv CHANGELOG.md CHANGELOG.zh-CN.md
```
内容不改。注意：mv 后英文版未建，仓库临时无 `README.md` → 本地预览会异常，但 git 历史 OK，与第 3 步同提交即解决。

### 2. 中文版加切换链接
3 个 `.zh-CN.md` 文件顶部插入：
```
[English](./README.md) | **简体中文**

```
（CONTRIBUTING / CHANGELOG 同理换文件名）

### 3. 英文版重写（AI 产出）
基于 `.zh-CN.md` 核心信息，重写（非翻译）：
- `README.md`：英文，重写适配（按 design 重写边界）
- `CONTRIBUTING.md`：英文 + 加「Reporting Issues / Pull Requests」简短段
- `CHANGELOG.md`：英文，翻译现有 v0.1.0 / v0.2.0 条目（版本记录事实性强，翻译非重写）

顶部插入：
```
**English** | [简体中文](./README.zh-CN.md)

```

### 4. 验证
- `ls README.md README.zh-CN.md CONTRIBUTING.md CONTRIBUTING.zh-CN.md CHANGELOG.md CHANGELOG.zh-CN.md`（6 齐）
- 每个文件顶部切换链接互通（点链接到对应文件）
- `git diff README.zh-CN.md` 仅顶部链接变化（内容与改前一致）—— 守护信息零丢失
- 英文版对照中文版：核心信息点全覆盖（人工对照 acceptance 清单）

### 5. 提交（无 Co-Authored-By）
单提交：`feat: user docs i18n (bilingual README/CONTRIBUTING/CHANGELOG)`

## 翻译质量流程

- **主会话 AI 重写**英文版三件（基于 design 重写边界）
- **用户审校定稿**：重点审
  - 技术术语保留英文（CGEvent / MenuBarExtra / ORSSerialPort / SMAppService / xcodegen）
  - 语气自然（避免中式英语）
  - CONTRIBUTING 惯例段措辞
- 不满意处用户标出，AI 改到满意

## 风险点

- 中文版 mv 后英文版建前临时无 README.md → 第 1+3 步同提交避免
- 英文重写别丢中文核心信息 → 第 4 步人工对照验收
- 切换链接相对路径 → push 后 GitHub 渲染验证（或本地 markdown 预览）

## 回滚点

- 每个文件独立，单文件 `git revert`
- 整批：`git revert <i18n commit>`

## 不做

- 不改 spec / AGENTS.md / 代码
- 不加 CoC / CLA / issue 模板（out of scope）
- 不引入 i18n 工具/脚本（手维护双语，文件少）
