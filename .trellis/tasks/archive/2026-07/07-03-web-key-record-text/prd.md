# 网页端组合键录制与文本输入动作

## Goal

增强 VibeBoard 配置网页端（`index.html`）：① 击键动作支持「录制」物理组合键自动填入；② 新增「输入文本」动作类型，并把 k2 改为输入「继续」并回车。

## Requirements

### R1. 组合键录制（前端）
- key 类型动作的 value 输入框旁增加「录制」按钮。
- 点击后进入录制态（按钮文案变为「按下组合键… / Esc 取消」），监听**一次** keydown。
- 把捕获的事件映射成后端支持的字符串格式填入 value：
  - modifier：`ctrlKey→ctrl`、`metaKey→cmd`、`altKey→option`、`shiftKey→shift`
  - 主键：单字符小写；`Escape→esc`、`Tab→tab`、`Enter→enter`、`Space→space`、`Backspace→delete`、`ArrowUp/Down/Left/Right→up/down/left/right`
  - 单 modifier 组合 → `mod+key`（如 `option+d`）；无 modifier → 单键（如 `esc`）
- 录制期间 `preventDefault`，避免浏览器/系统默认行为。
- Esc 取消录制，不写入。

### R2. 文本输入动作（前后端）
- 后端 `fire_down` 新增 `type == "text"` 分支，调用新增的 `send_text()`。
- k2 改为：`{"type": "text", "value": "继续", "enter": true, "desc": "输入'继续'并回车"}`。
- 前端动作类型下拉新增「输入文本」选项，选中时 value 改用 `<textarea>`。

## 关键决策与约束

- **中文输入用剪贴板方案**：`send_text` 用 `pbcopy` + `Cmd+V`，不用 osascript `keystroke`。原因：`keystroke` 依赖当前输入法，中文模式下可能触发拼音；剪贴板绕过输入法最可靠。副作用：覆盖一次剪贴板内容（可接受，快捷键场景用户专为输入这段文字）。
- **单 modifier 限制**：后端 `hold_down` 只支持单 modifier（`split("+", 1)` + 单 `_FLAG`）。录制对齐此能力，只支持 `mod+key`。多 modifier（如 `ctrl+shift+d`）为后续扩展，本次不做。
- **回车控制**：text 类型用 config 的 `enter` 布尔字段控制末尾回车，默认 true（贴合 k2「然后回车」语义）。value 文本本身不含 `\n` 处理（保持简单）。
- **剪贴板时序**：`pbcopy`（同步）→ `Cmd+V`（osascript）→ 若 enter，再 `enter`。粘贴与回车之间加 `time.sleep(0.05)` 间隔，避免事件重叠。
- **架构对齐**：新动作类型加到 `fire_down` 分发链（spec/backend/directory-structure.md 已约定），不绕过。
- **mode 对 text 无效**：text 只支持 tap 语义（瞬时输入），UI 上 text 类型隐藏 mode 选择。

## Acceptance Criteria

代码与 UI 已验证（Playwright 自动化）：
- [x] key 类型 value 旁有「录制」按钮；按 `option+d`→`option+d`、`ctrl+c`→`ctrl+c`、单键 `a`→`a`。Esc 取消录制不写入。（注：原 acceptance 误写「按 esc 填入 esc」，与 R1「Esc 取消」矛盾，此处更正为 Esc=取消。）
- [x] 后端新增 `send_text()`，走剪贴板 + Cmd+V，`enter=true` 时补 enter。
- [x] 前端动作类型可选「输入文本」，选中后 value 为 textarea、mode 隐藏、enter 复选框。
- [x] save() 正确收集 textarea value 与 checkbox enter（boolean），POST body 验证通过。
- [x] cmd / key(tap) / key(hold) 类型 UI 渲染未受影响（回归）。
- [x] spec 更新：directory-structure 分发链+schema 补 text；quality-guidelines 补 text/剪贴板/单modifier；frontend 补录制 e.code 坑。

已手动验证通过（2026-07-03，物理按键 + 串口设备）：
- [x] k2 物理按键：聚焦输入框 → 按 k2 → 出现「继续」+ 回车提交。
- [x] k2 在中文输入法开启状态下同样生效（剪贴板方案核心验证点）。
- [x] hold 回归：k4（option+d hold）物理按键仍正常。

## Out of Scope

- 多 modifier 组合键录制与 hold。
- text 类型的多行输入（`\n` 分段）。
- 剪贴板内容保存/恢复。
