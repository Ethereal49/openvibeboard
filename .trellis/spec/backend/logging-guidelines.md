# 日志约定

> 用 `print` + `flush`，不引入日志库。守护进程在终端前台跑，日志直接给人看。

---

## 唯一函数

```python
def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)
```

格式固定：`[HH:MM:SS] <msg>`。`flush=True` 是必须的 —— 不 flush 的 print 在重定向到文件时会缓冲，调试时看不到实时输出。

不要用 `logging` 模块或 print 以外的输出方式（除非未来引入日志聚合，那是单独决策）。

---

## 何时记

| 事件 | 示例 | 位置 |
|------|------|------|
| 启动 | `Web 配置界面: http://127.0.0.1:8765 (CGEvent hold: on)` | `:270` |
| 线程就绪 | `串口监听已启动` | `:196` |
| 按键触发 | `k1 -> 打开 Codex` / `k4 ▼ 按住 option+d` / `k4 ▲ 释放` | `:169-190` |
| 配置更新 | `配置已更新并热生效` | `:240` |
| 降级/错误 | `⚠ hold 需要 pyobjc + 辅助功能权限` / `⚠️ 串口错误: ...` | `:177,214` |

用 emoji/箭头（`▼` `▲` `⚠`）做视觉区分，便于在终端滚动里快速定位 down/up/告警。

---

## 不记什么

- **不记** `config.json` 的完整内容 —— value 字段可能含 shell 命令或敏感路径，只记 `desc`。
- **不记** 串口原始字节流 —— 量大且无用；只记解析后的按键事件。
- **不记** 每次 HTTP GET —— `Handler.log_message` 已被覆盖成空（`:218-219`），保持安静。

---

## 关闭 HTTP 访问日志

```python
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
```

`BaseHTTPRequestHandler` 默认每条请求打印一行日志，已显式关闭。新增 handler 保持这个覆盖。
