# 错误处理

> 守护进程优先「不崩」+ 可选依赖降级。不定义自定义异常类（这个规模不需要）。

---

## Optional import 降级模式

`pyobjc` 是可选依赖。用 try/except ImportError 包住，降级到功能 flag：

```python
try:
    from Quartz import (...)
    _SRC = CGEventSourceCreate(...)
    HAS_CGEVENT = _SRC is not None
    def _post(code, down, flag=0): ...
except ImportError:
    HAS_CGEVENT = False
    def _post(code, down, flag=0):
        pass   # 降级：hold 模式静默无效
```

调用点必须先判 `HAS_CGEVENT`，缺失时 `log` 警告而非崩溃（`vibe_control.py:173-177`）。新增可选系统依赖时沿用这个模式。

---

## 守护进程不崩

- `serial_loop` 外层 `try/except serial.SerialException`：串口被占用/断开时只 `log` 警告，**不**让线程死掉影响 HTTP 服务（`:213-214`）。
- HTTP `POST /api/config` 解析 JSON 时 `try/except Exception`：坏请求返回 `400`，不让 server 挂（`:235-246`）。

```python
try:
    cfg = json.loads(body)
    if not isinstance(cfg, dict):
        raise ValueError("配置需为对象")
    save_config(cfg)
    self._send(200, json.dumps({"ok": True}).encode(), "application/json")
except Exception as e:
    self._send(400, json.dumps({"ok": False, "err": str(e)}).encode(), "application/json")
```

---

## API 错误响应格式

所有 API 错误统一返回：

```json
{ "ok": false, "err": "<原因>" }
```

成功返回 `{ "ok": true }`。前端按 `j.ok` 分支显示。不要引入 HTTP 状态码之外的错误码体系。

---

## 串口解析容错

`serial_loop` 用 `decode("utf-8", "ignore")` 丢弃坏字节，正则没匹配就跳过（`:205-212`）。不要对每条坏日志报警，会刷屏。

---

## 权限缺失 = 警告，非崩溃

- tap 击键缺「自动化」授权 → `osascript` 调用失败，`osa()` 用 `capture_output=True` 吞掉错误，不抛。
- hold 缺「辅助功能」授权 → `HAS_CGEVENT` 为 false，`log` 警告。

权限授权是运行前置条件，在 docstring 和启动日志里声明（见 quality-guidelines）。
