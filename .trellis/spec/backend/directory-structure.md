# 目录与架构

> 全部后端逻辑在单个文件 `vibe_control.py`（根目录，约 280 行）。**不要**按惯例拆成 routes/services/utils —— 那是对这个规模的过度设计。

---

## 单文件三职责

`vibe_control.py` 一个进程做三件事：

1. **HTTP 配置服务** —— `ThreadingHTTPServer` 监听 `127.0.0.1:8765`，`Handler` 类提供 `GET /`（UI）、`GET /api/config`、`POST /api/config`。
2. **串口监听线程** —— `serial_loop()` 守护线程读 `/dev/cu.usbmodem3101`，按行解析按键事件。
3. **动作分发** —— `fire_down` / `fire_up` 按 config 的 `type`/`mode` 触发动作。

`main()` 启动顺序：`load_config()` → 起 `serial_loop` 守护线程 → `serve_forever()`。

---

## 文件内部分区（按出现顺序）

| 区 | 内容 | 位置 |
|----|------|------|
| optional import | `pyserial`、`Quartz` 的 try/except，降级到 `HAS_CGEVENT` flag | `vibe_control.py:30-58` |
| 常量 | 路径、端口、串口、keycode 映射表、正则 | `:60-82` |
| 全局状态 | `CONFIG` + `CONFIG_LOCK` | `:84-85` |
| 工具函数 | `log`、`load_config`、`save_config`、`run_cmd`、`osa` | `:88-113` |
| 动作执行 | `send_key`(tap) / `hold_down`/`hold_up`(hold) / `fire_down`/`fire_up`(分发) | `:116-191` |
| 串口循环 | `serial_loop` | `:193-214` |
| HTTP handler | `Handler` 类 | `:217-263` |
| 入口 | `main`、`__main__` | `:266-279` |

---

## 分发链（核心数据流）

```
串口字节流
  └─ serial_loop 按行切，DOWN_RE/UP_RE 正则匹配 "button down kN"
       └─ fire_down(button)        # fire_up 同理
            └─ 查 CONFIG[button]
                 ├─ type=="cmd"   → run_cmd(value)           # subprocess.Popen
                 ├─ type=="text"  → send_text(value, enter)  # pbcopy + Cmd+V + 可选 enter
                 └─ type=="key"
                      ├─ mode=="tap"  → send_key(value)      # osascript keystroke
                      └─ mode=="hold" → hold_down(value)     # CGEvent（需 HAS_CGEVENT）
```

新增动作类型时，在 `fire_down` / `fire_up` 的分支里加，**不要**绕过分发链直接在 `serial_loop` 里调 subprocess。

---

## config.json schema

```json
{
  "k1": {"type": "cmd",  "value": "open -a Codex", "mode": "tap",  "desc": "打开 Codex"},
  "k3": {"type": "key",  "value": "ctrl+c",        "mode": "tap",  "desc": "Ctrl+C"},
  "k4": {"type": "key",  "value": "option+d",      "mode": "hold", "desc": "语音(按住)"}
}
```

- 键名：`k1`/`k2`/...，对应固件日志里的 `kN`。
- `type`：`"cmd"`（shell 命令）、`"key"`（击键）或 `"text"`（输入文本）。cmd/text 的 mode 无效。
- `value`：cmd 时是 shell 字符串；key 时是 `option+d` / `ctrl+c` / `esc` / `enter` / 单字符；text 时是要输入的文本（中文等任意字符）。
- `mode`：`"tap"`（瞬时，osascript）或 `"hold"`（按住，CGEvent，需 pyobjc + 辅助功能权限）。**仅 key 类型有效**。
- `enter`：仅 text 类型，布尔（默认 true），控制粘贴后是否补一个回车。
- `desc`：纯展示用，UI header 和日志里出现。

`save_config()` 会原子地更新内存 `CONFIG`（持锁）并落盘 `config.json`，**热生效**，无需重启。
