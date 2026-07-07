#!/usr/bin/env python3
"""VibeBoard Web 配置 + 按键守护进程（支持「按住」语义）。

单进程：
  1. HTTP server (http://127.0.0.1:8765) —— 可视化配置 UI，读写 config.json。
  2. 后台线程监听 /dev/cu.usbmodem3101 —— 解析按键日志，按 config 触发动作。

动作模式 mode：
  - "tap"  瞬时：按下即触发一次（osascript keystroke）。启动应用、Ctrl+C 等用此。
  - "hold" 按住：按下→key-down 保持，松开→key-up 释放（CGEvent）。
                语音转文字等"按住录音"软件用此。需辅助功能权限。

前置：
  1. 退出 VibeBoard 客户端释放串口。
  2. tap 击键需授权「自动化」(System Events)；hold 需授权「辅助功能」。

运行：
  uv run python -u vibe_control.py
"""
import json
import os
import re
import shlex
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import serial
except ImportError:
    sys.exit("缺少 pyserial: 运行 uv sync 安装依赖")

try:
    from Quartz import (CGEventSourceCreate, kCGEventSourceStateHIDSystemState,
                        CGEventCreateKeyboardEvent, CGEventPost, kCGHIDEventTap,
                        CGEventSetFlags, kCGEventFlagMaskAlternate,
                        kCGEventFlagMaskControl, kCGEventFlagMaskCommand,
                        kCGEventFlagMaskShift)
    _SRC = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
    HAS_CGEVENT = _SRC is not None
    _FLAG = {"ctrl": kCGEventFlagMaskControl, "control": kCGEventFlagMaskControl,
             "cmd": kCGEventFlagMaskCommand, "command": kCGEventFlagMaskCommand,
             "shift": kCGEventFlagMaskShift, "option": kCGEventFlagMaskAlternate,
             "alt": kCGEventFlagMaskAlternate, "opt": kCGEventFlagMaskAlternate}

    def _post(code, down, flag=0):
        ev = CGEventCreateKeyboardEvent(_SRC, code, down)
        if flag:
            CGEventSetFlags(ev, flag)
        CGEventPost(kCGHIDEventTap, ev)
except ImportError:
    HAS_CGEVENT = False
    _FLAG = {}

    def _post(code, down, flag=0):
        pass

BASE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE, "config.json")
HTML_PATH = os.path.join(BASE, "index.html")
PORT_SERIAL = "/dev/cu.usbmodem3101"
BAUD = 115200
WEB_PORT = 8765

# macOS virtual key codes
MOD_CODES = {"ctrl": 59, "control": 59, "cmd": 55, "command": 55, "shift": 56,
             "option": 58, "alt": 58, "opt": 58}
KEY_CODES = {"ctrl": 59, "esc": 53, "cmd": 55, "shift": 56, "opt": 58, "tab": 48,
             "enter": 36, "return": 36, "space": 49, "up": 126, "down": 125,
             "left": 123, "right": 124, "delete": 51}
CHAR_CODES = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
    "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
    "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
    "k": 40, "n": 45, "m": 46, " ": 49,
}

DOWN_RE = re.compile(r"button down (k\d)")
UP_RE = re.compile(r"button up (k\d)")

CONFIG = {}
CONFIG_LOCK = threading.Lock()


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def load_config():
    global CONFIG
    with open(CONFIG_PATH, encoding="utf-8") as f:
        CONFIG = json.load(f)


def save_config(cfg):
    global CONFIG
    with CONFIG_LOCK:
        CONFIG = cfg
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def run_cmd(cmd):
    subprocess.Popen(shlex.split(cmd),
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def osa(script):
    return subprocess.run(["osascript", "-e", script],
                          capture_output=True, text=True)


def send_key(key):
    """tap: 瞬时击键 (osascript)。"""
    if "+" in key:
        mod, ch = key.split("+", 1)
        mod_map = {"ctrl": "control down", "cmd": "command down",
                   "shift": "shift down", "option": "option down",
                   "opt": "option down", "alt": "option down"}
        osa(f'tell application "System Events" to keystroke "{ch}" '
            f'using {{{mod_map.get(mod.lower(), "control down")}}}')
    elif key.lower() in KEY_CODES:
        osa(f'tell application "System Events" to key code {KEY_CODES[key.lower()]}')
    else:
        osa(f'tell application "System Events" to keystroke "{key}"')


def send_text(text, enter=True):
    """text 动作：剪贴板粘贴文本（绕过输入法对中文的不确定性），可选末尾回车。

    用 pbcopy + Cmd+V 而非 osascript keystroke：keystroke 依赖当前输入法，
    中文模式下可能触发拼音；剪贴板直接粘贴字符最可靠。代价是覆盖一次剪贴板。
    """
    subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=False)
    send_key("cmd+v")
    if enter:
        time.sleep(0.05)  # 等粘贴事件落地，避免与回车重叠
        send_key("enter")


def _char_code(key):
    """'option+d' -> d 的 keycode；单键 -> 自身 keycode。"""
    ch = key.split("+", 1)[1] if "+" in key else key
    return CHAR_CODES.get(ch.lower()) or KEY_CODES.get(ch.lower())


def hold_down(key):
    """组合键：char keydown 直接挂 modifier flag（不单独发 modifier keydown，
    避免 modifier 状态丢失/残留、避免字符 key repeat）。纯修饰键：直接 keydown。"""
    if "+" in key:
        mod = key.split("+", 1)[0].lower()
        cc = _char_code(key)
        if cc is not None:
            _post(cc, True, _FLAG.get(mod, 0))
    else:
        code = KEY_CODES.get(key.lower()) or CHAR_CODES.get(key.lower())
        if code is not None:
            _post(code, True)


def hold_up(key):
    if "+" in key:
        cc = _char_code(key)
        if cc is not None:
            _post(cc, False)
    else:
        code = KEY_CODES.get(key.lower()) or CHAR_CODES.get(key.lower())
        if code is not None:
            _post(code, False)


def fire_down(button):
    with CONFIG_LOCK:
        cfg = CONFIG.get(button)
    if not cfg:
        return
    desc = cfg.get("desc", cfg.get("value", ""))
    if cfg.get("type") == "cmd":
        log(f"{button} -> {desc}")
        run_cmd(cfg.get("value", ""))
    elif cfg.get("type") == "text":
        log(f"{button} -> 输入文本 {desc}")
        send_text(cfg.get("value", ""), cfg.get("enter", True))
    elif cfg.get("type") == "key":
        if cfg.get("mode") == "hold":
            if HAS_CGEVENT:
                log(f"{button} ▼ 按住 {cfg.get('value')}")
                hold_down(cfg.get("value", ""))
            else:
                log(f"{button} ⚠ hold 需要 pyobjc + 辅助功能权限")
        else:
            log(f"{button} -> {desc}")
            send_key(cfg.get("value", ""))


def fire_up(button):
    with CONFIG_LOCK:
        cfg = CONFIG.get(button)
    if not cfg or cfg.get("type") != "key" or cfg.get("mode") != "hold":
        return
    if HAS_CGEVENT:
        log(f"{button} ▲ 释放")
        hold_up(cfg.get("value", ""))


def serial_loop():
    try:
        with serial.Serial(PORT_SERIAL, BAUD, timeout=1) as s:
            log("串口监听已启动")
            buf = b""
            while True:
                chunk = s.read(256)
                if not chunk:
                    continue
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    text = line.decode("utf-8", "ignore")
                    m = DOWN_RE.search(text)
                    if m:
                        fire_down(m.group(1))
                        continue
                    m = UP_RE.search(text)
                    if m:
                        fire_up(m.group(1))
    except serial.SerialException as e:
        log(f"⚠️ 串口错误: {e}（确认已退出 VibeBoard 客户端）")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/":
            self._serve_file(HTML_PATH, "text/html; charset=utf-8")
        elif self.path == "/api/config":
            with CONFIG_LOCK:
                data = json.dumps(CONFIG, ensure_ascii=False).encode("utf-8")
            self._send(200, data, "application/json")
        else:
            self._send(404, b"not found", "text/plain")

    def do_POST(self):
        if self.path == "/api/config":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                cfg = json.loads(body)
                if not isinstance(cfg, dict):
                    raise ValueError("配置需为对象")
                save_config(cfg)
                log("配置已更新并热生效")
                self._send(200, json.dumps({"ok": True}).encode(),
                           "application/json")
            except Exception as e:
                self._send(400,
                           json.dumps({"ok": False, "err": str(e)}).encode(),
                           "application/json")
        else:
            self._send(404, b"not found", "text/plain")

    def _serve_file(self, path, ctype):
        try:
            with open(path, "rb") as f:
                data = f.read()
            self._send(200, data, ctype)
        except FileNotFoundError:
            self._send(404, b"not found", "text/plain")

    def _send(self, code, data, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    load_config()
    threading.Thread(target=serial_loop, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", WEB_PORT), Handler)
    log(f"Web 配置界面: http://127.0.0.1:{WEB_PORT}  (CGEvent hold: {'on' if HAS_CGEVENT else 'off'})")
    log("Ctrl+C 退出")
    srv.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("已退出")
