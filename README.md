# ⌨️ VibeBoard

> 不改固件，给 ESP32-S3 键盘（VibeBoard / 上游代号 voicestick）做 macOS 端接管：把物理按键映射成 shell 命令、击键或文本输入。

单文件 Python 守护进程：内置 Web 配置页 + 串口监听，物理按键即触发动作，配置改完热生效（无需重启）。

## 特性

- 🔌 **串口接管** —— 直接读 ESP32-S3 的 USB CDC 日志，不碰固件
- 🌐 **Web 配置** —— 浏览器改按键，保存即热生效
- ⌨️ **三种动作** —— `cmd`（shell 命令）/ `key`（击键）/ `text`（粘贴文本）
- 🎯 **两种模式** —— `tap`（瞬时）/ `hold`（按住，CGEvent 实现，支持语音软件「按住录音」）
- 🎙 **组合键录制** —— Web UI 上直接按物理键录制（option+d 等）
- 🀄 **中文友好** —— text 动作走剪贴板粘贴，绕过中文输入法

## 前提条件

- **macOS**（依赖 osascript / CGEvent / System Events）
- **Python 3.10+**（pyobjc 12.x 要求）
- **[uv](https://docs.astral.sh/uv/)** —— 环境与依赖管理（macOS：`brew install uv`）
- **VibeBoard 客户端已退出**（释放串口 `/dev/cu.usbmodem3101`）
- 键盘仍以 ESP-IDF 日志形式输出按键事件（无需改固件）

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/ethereal/openvibeboard.git
cd openvibeboard

# 2. 同步依赖（uv 自动创建 .venv 并安装，生成 uv.lock）
uv sync

# 3. 退出 VibeBoard 客户端释放串口

# 4. 运行
uv run python -u vibe_control.py
```

预期输出：

```
[HH:MM:SS] 串口监听已启动
[HH:MM:SS] Web 配置界面: http://127.0.0.1:8765  (CGEvent hold: on)
[HH:MM:SS] Ctrl+C 退出
```

浏览器开 `http://127.0.0.1:8765` 配置按键，物理按键即触发。

## 工作原理

键盘（ESP32-S3）通过 USB CDC 持续输出 ESP-IDF 日志，按键事件行格式：

```
button down kN    # 按下（N = 1-4）
button up kN      # 松开
```

守护进程 `vibe_control.py` 单进程做两件事：

1. **HTTP server**（`127.0.0.1:8765`）—— Web 配置页，读写 `config.json`
2. **串口监听线程** —— 正则匹配 `button down/up kN` → 查 config → 分发动作

### 动作类型

| type | 说明 | 触发方式 | value 示例 |
|------|------|----------|-----------|
| `cmd` | Shell 命令 | `subprocess`（非阻塞） | `open -a Codex` |
| `key` | 击键 | `tap`→osascript；`hold`→CGEvent | `ctrl+c`、`option+d`、`esc` |
| `text` | 输入文本 | 剪贴板 `pbcopy`+`Cmd+V`（绕过输入法） | `继续` |

### 模式（仅 `key` 类型有效）

| mode | 行为 | 实现 | 权限 |
|------|------|------|------|
| `tap` | 按下即触发一次 | osascript `keystroke` | 自动化 |
| `hold` | 按下保持 key-down，松开 key-up | CGEvent | 辅助功能 |

> `text` 类型用 `enter` 字段（默认 `true`）控制粘贴后是否补一个回车；`mode` 对 `cmd`/`text` 无效。

## 配置

Web UI 改完点「💾 保存并生效」即写入 `config.json` 并热生效；也可直接编辑 `config.json`（下次重启加载）。

默认按键映射：

| 键 | 动作 |
|----|------|
| k1 | `cmd`：`open -a Codex` |
| k2 | `text`：粘贴「继续」+ 回车 |
| k3 | `key` tap：`ctrl+c` |
| k4 | `key` hold：`option+d`（语音软件按住录音） |

击键 value 格式：`option+d` / `ctrl+c` / `cmd+v` / `esc` / `tab` / `enter` / `space` / 单字符。Web UI 的「录制」按钮可直接按物理键自动填入。

## 权限

首次运行 macOS 会弹授权（系统设置 → 隐私与安全性）：

- **自动化**（System Events）—— `tap` 击键、`text` 粘贴、`cmd` 调 osascript 都需要
- **辅助功能** —— `hold`（CGEvent）需要；缺失则日志显示 `CGEvent hold: off`，hold 动作静默失效

## 故障排查

| 现象 | 原因 / 解决 |
|------|------------|
| `⚠️ 串口错误` / 监听不起 | VibeBoard 客户端没退出，占用 `/dev/cu.usbmodem3101` |
| `CGEvent hold: off` | 没装 pyobjc 或没授权辅助功能；装依赖 + 系统设置授权 |
| `缺少 pyserial` | 依赖未装，`uv sync` 重新同步 |
| text 动作中文变拼音 | 不应出现（剪贴板方案）；若出现确认走的是 `send_text` 而非 osascript keystroke |
| hold 组合键只打出单字符 / 卡住 | 单独发 modifier keydown 的已知坑，本项目用 `CGEventSetFlags` 挂 flag 规避 |
| 多 modifier 组合（如 `ctrl+shift+d`）无效 | 当前只支持单 modifier，见路线图 |

### 重建环境

`.venv` 在项目根（不在 `/tmp`，不随系统重启丢失）。换机器或重新 clone 后：

```bash
uv sync
```

## 项目结构

```
openvibeboard/
├── vibe_control.py            # 守护进程（HTTP server + 串口监听 + 动作分发）
├── index.html                 # Web 配置 UI（原生 HTML/JS，无框架）
├── config.json                # 按键映射（Web UI 读写）
├── pyproject.toml            # 项目元数据 + 依赖声明（uv 管理）
├── uv.lock                   # 锁定依赖版本（提交，保证可复现）
├── .trellis/spec/             # 编码约定（AI sub-agent 自动加载）
│   ├── backend/               #   Python 约定（CGEvent 坑、剪贴板方案…）
│   ├── frontend/              #   Web UI 约定（录制 event.code 坑…）
│   └── guides/                #   通用思考指南
└── .claude/ .codex/ .agents/  # AI 工具配置（团队共享）
```

## 开发

本项目用 Trellis 管理开发流程，编码约定沉淀在 `.trellis/spec/`。改代码前先读对应 spec，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 路线图

- [ ] launchd 开机自启（当前需手动运行）
- [ ] 打包 .app / 状态栏图标（替代退出 VibeBoard 客户端的体验）
- [ ] 多 modifier 组合键支持（当前 hold/录制均只支持单 modifier）

## 许可证

[MIT](LICENSE)
