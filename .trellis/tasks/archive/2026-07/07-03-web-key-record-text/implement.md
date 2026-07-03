# 执行计划

## 顺序与验证

### Step 1 — 后端：新增 text 动作（`vibe_control.py`）
- 在 `send_key` 附近加 `send_text(text, enter)`：
  - `subprocess.run(["pbcopy"], input=text.encode("utf-8"))`
  - `send_key("cmd+v")`（复用 tap 击键）
  - 若 `enter`：`time.sleep(0.05)` → `send_key("enter")`
- 在 `fire_down` 加分支：`elif cfg.get("type") == "text": send_text(cfg.get("value",""), cfg.get("enter", True))`，配 `log`。
- `fire_up` 不动（text 无 hold 语义）。
- **验证**：`python -c "import ast; ast.parse(open('vibe_control.py').read())"` 语法通过。

### Step 2 — 前端：录制按钮 + text UI（`index.html`）
- 给 key 类型的 value 输入框旁加「录制」按钮，data 属性标记。
- 加录制函数：进入录制态 → 监听一次 keydown → preventDefault → 映射组装 → 写入对应 input → 退出录制态；Esc 取消。
- 动作类型下拉加 `<option value="text">输入文本</option>`；`onType` 切换：text 时把 value 输入替换为 `<textarea>` 并隐藏 mode 选择。
- `save()` 收集逻辑兼容 textarea（data-f=value 通用）。
- **验证**：浏览器开 `http://127.0.0.1:8765`，点录制→按 option+d→value 显示 `option+d`。

### Step 3 — 配置：改 k2（`config.json`）
- k2 改为 `{"type": "text", "value": "继续", "enter": true, "desc": "输入'继续'并回车"}`。
- 其余 k1/k3/k4 不动。

### Step 4 — spec 更新
- `backend/directory-structure.md`：分发链图补 text 分支；config schema 补 text 类型字段。
- `backend/quality-guidelines.md`：补「text 动作走剪贴板不污染输入法」「单 modifier 限制」。

### Step 5 — 手动验证（回归）
1. 退出 VibeBoard 客户端释放串口。
2. `/tmp/vb_venv/bin/python -u vibe_control.py`，看启动日志 CGEvent 状态。
3. 浏览器开配置页：
   - 录制 `option+d` 写入 k4（hold），物理按 k4 验证 hold 仍生效（回归）。
   - k2 选「输入文本」，value 填「继续」。
4. 聚焦任一输入框（如浏览器地址栏旁的搜索框，或 AI CLI 输入区），物理按 k2 → 出现「继续」并回车提交。
5. **中文输入法开启**状态下重复按 k2，验证「继续」仍正确输入（剪贴板方案核心验证点）。
6. 按 k1（cmd: open -a Codex）、k3（key tap: ctrl+c）验证既有动作未坏。

## 回滚点

- 每个 Step 独立可回滚：Step1 后端改坏 → 注释掉 text 分支即可恢复（text 配置不会被旧代码识别，安全降级）。
- Step3 k2 改动 → 改回 `{"type":"cmd","value":"claude",...}` 即恢复。
- 全量回滚：`git` 不适用（非 git 仓库），手工还原三个文件（改动集中在 vibe_control.py 的 send_text/fire_down、index.html 的录制段、config.json 的 k2 行）。

## Review Gate

- Step 1-2 完成后先在浏览器自测录制 + text UI 渲染，再进 Step 3 改配置。
- Step 5 中文输入法验证是核心验收点，必须通过才算 done。
