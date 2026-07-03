# 质量约定（含 CGEvent 核心坑）

> 这里是本项目最容易踩坑的地方。改 `fire_down`/`hold_down`/`hold_up` 之前必读。

---

## ⚠ CGEvent hold 的 modifier flag 坑（最重要）

**组合键 hold 时，modifier flag 必须直接挂在 char keydown 上，不要单独发 modifier 的 keydown/up。**

错误写法（会让 modifier 状态丢失/残留，并触发字符 repeat）：
```python
# 禁止：分两步发
_post(MOD_CODES["option"], True)      # 先发 option keydown
_post(CHAR_CODES["d"], True)          # 再发 d keydown
```

正确写法（`hold_down` 实际实现，`:137-148`）：
```python
def hold_down(key):
    if "+" in key:
        mod = key.split("+", 1)[0].lower()
        cc = _char_code(key)
        if cc is not None:
            _post(cc, True, _FLAG.get(mod, 0))   # flag 随 char keydown 一起发
    else:
        code = KEY_CODES.get(key.lower()) or CHAR_CODES.get(key.lower())
        if code is not None:
            _post(code, True)
```

`hold_up` 只发 char keyup（**不**带 flag），让系统自动释放 modifier（`:151-159`）。原因：CGEvent 的 modifier 是 keydown 的 flag 属性，不是独立的键状态；分开发会破坏系统对 modifier 的状态跟踪。

---

## 必须遵守

- **CONFIG_LOCK 保护 CONFIG 读写**。`fire_down` 读 config 前持锁拷贝引用，`save_config` 写时持锁。否则串口线程和 HTTP 线程会竞争（`:163-166`、`:98-103`）。
  ```python
  with CONFIG_LOCK:
      cfg = CONFIG.get(button)
  ```
- **tap 与 hold 不可混**。tap 走 `send_key`（osascript `keystroke`），hold 走 `hold_down`/`hold_up`（CGEvent）。在 `fire_down` 里按 `mode` 二选一，不要让 tap 路径调 CGEvent 或反之。
- **optional import 降级**。新增 macOS 私有 API 调用时，包在 try/except ImportError 里，配 `HAS_*` flag（见 error-handling）。

---

## 文本输入动作（type == "text"）

`send_text()` 用 **剪贴板方案**，不用 osascript `keystroke`：

```python
def send_text(text, enter=True):
    subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=False)
    send_key("cmd+v")
    if enter:
        time.sleep(0.05)
        send_key("enter")
```

- **为什么不用 keystroke**：`keystroke "继续"` 依赖当前输入法，中文模式下可能触发拼音输入。`pbcopy` + `Cmd+V` 直接粘贴字符，绕过输入法，对中文最可靠。
- **副作用**：覆盖一次剪贴板内容。快捷键场景可接受（用户专为输入这段文字才按这个键）。不保存/恢复原剪贴板（时序复杂，刻意不做）。
- **时序**：`pbcopy` 同步 → `Cmd+V` → 若 enter，`sleep(0.05)` 后再发 enter，避免粘贴与回车事件重叠。
- `pbcopy` 用 `subprocess.run`（同步快命令）而非 `Popen` —— 与 cmd 动作的 `Popen`（不阻塞）区分：文本粘贴必须等 pbcopy 写完才能粘贴，所以要阻塞。
- 单 modifier 限制：`hold_down` 的 `key.split("+", 1)` + 单个 `_FLAG` 只支持 `mod+key`。多 modifier（如 `ctrl+shift+d`）是后续扩展，前端录制也对齐此限制。

## 禁止模式

- ❌ 绕过 `fire_down`/`fire_up` 在 `serial_loop` 里直接调 `subprocess` 或 `_post`。所有动作必须走分发链，方便统一加日志和权限检查。
- ❌ 用 `subprocess.run`（阻塞）执行 cmd 动作。cmd 动作用 `run_cmd` → `subprocess.Popen`（不阻塞，`:106-108`），否则会卡住串口线程。
- ❌ `print` 不加 `flush=True`（见 logging）。
- ❌ 给 `CONFIG` 赋值时不持锁。

---

## 权限前置（运行时，非代码）

启动前必须授权，否则功能静默失效：
- tap 击键 → 系统设置 → 隐私 → **自动化**（授权 System Events）
- hold 模式 → 系统设置 → 隐私 → **辅助功能**（授权运行 python 的终端/进程）
- 串口 → **退出 VibeBoard 客户端**释放 `/dev/cu.usbmodem3101`

这些写在模块 docstring（`:1-19`）和启动日志里，改动涉及权限时同步更新。

---

## 测试与验证

**如实记录：本项目当前没有自动化测试。** 这是已知 tech debt，不是理想状态。

改动的验证方式（手动）：
1. 确认已退出 VibeBoard 客户端（释放串口）。
2. `uv run python -u vibe_control.py` 启动（uv 管理，见 README）。
3. 看启动日志 `CGEvent hold: on/off` 是否符合预期。
4. 浏览器开 `http://127.0.0.1:8765` 改配置保存，看「配置已更新并热生效」。
5. 按物理键验证 cmd / tap / hold 三种动作。

涉及 CGEvent 的改动，**必须**测 hold 模式的组合键（如 `option+d`）：按下不松 → 系统应持续识别 modifier 状态 → 松开干净释放，无残留。

---

## 编码风格

- 中文 docstring 和注释（与现有代码一致）。
- 常量全大写（`PORT_SERIAL`、`KEY_CODES`）；函数 snake_case。
- keycode 映射表（`KEY_CODES`/`CHAR_CODES`/`MOD_CODES`/`_FLAG`）集中在文件顶部，不在函数内散落魔法数字。
