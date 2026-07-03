# Frontend 开发约定（原生 HTML/JS，无框架）

> 本项目前端是**单个静态文件** `index.html`（根目录），内联 CSS + 原生 JS，无构建、无打包、无 TypeScript、无组件框架、无状态管理库。

`trellis init` 生成的 component / hook / state-management / type-safety 模板对本项目不适用，已删除。所有前端约定合并在这一个文件里。

---

## 技术栈

- 一个 `index.html`，由 Python 的 `Handler.do_GET /` 直接读盘返回（`vibe_control.py:222-223`）。
- 内联 `<style>` + 内联 `<script>`，无外部资源、无 CDN。
- 原生 `fetch` 调两个端点：`GET /api/config`、`POST /api/config`。

改前端 = 改 `index.html` → 浏览器刷新，**无构建步骤**。

---

## 数据流

```
load()  → GET /api/config → 填全局 cfg → 渲染 #keys
save()  → 遍历 [data-k] 收集到 cfg → POST /api/config → 显示 ok/err
```

- 全局变量 `cfg` 是唯一状态，无 store / observable。函数式更新而非响应式。
- UI 用 `innerHTML` 模板字符串生成，绑定用 `data-k`（键名）+ `data-f`（字段名）attribute。

---

## 必须遵守

- **组合键录制必须用 `event.code`，不能用 `event.key`**。macOS 下 Option+字母 会让 `event.key` 变成特殊字符（Option+D → `"∂"`），录制会失真。`mapKey()` 用 `event.code`（物理键位，如 `KeyD`/`Digit1`/`Space`/`ArrowUp`）映射，modifier 取 `ctrlKey/metaKey/altKey/shiftKey`。这是 macOS 专属坑，别图省事用 `event.key`。
- **录制态 Esc = 取消录制**（不写入 `esc` 键）。用户真要 `esc` 动作就手敲。录制监听挂在 `document` 上，只监听一次，`preventDefault` 阻止浏览器/系统默认。
- **单 modifier 限制**：录制只生成 `mod+key`（如 `option+d`），多 modifier 取第一个并在 hint 提示。对齐后端 `hold_down` 的单 modifier 能力。
- **用户输入必须 `esc()` 转义再插 HTML**。`index.html` 的 `esc()` 把 `"` → `&quot;`、`<` → `&lt;`。config 的 `value`/`desc` 是用户输入，不转义直接插 `innerHTML` = XSS。新增任何把 config 写进 HTML 的地方都要过 `esc()`。textarea 内容同样要转义（防 `</textarea>` 闭合）。
- **保存时按 `data-k` / `data-f` 反向收集**，不要维护独立的表单状态（`:94-96`）。
- **风格保持内联**。新 CSS 进 `<style>`，新 JS 进 `<script>`，不引入外部文件（除非有强需求，那是单独架构决策）。
- **视觉用 emoji 做轻量图标**（⌨️ 💾 ✅ ❌），与 macOS 审美一致，不引图标库。

---

## 命名与风格

- 函数：`load`、`save`、`onType`、`updateHint`、`esc` —— 短名、驼峰。
- CSS 类：短横线（`.key`、`.sub`、`.actions`）。
- data attribute：`data-k`、`data-f`（短，因为生成 HTML 时高频出现）。
- 颜色取 macOS 系统色（`#007aff` 蓝、`#f5f5f7` 背景、`#1d1d1f` 文字），新增组件沿用。

---

## 验证

无前端测试。改 `index.html` 后：
1. 启动 `vibe_control.py`（见 backend quality-guidelines）。
2. 浏览器开 `http://127.0.0.1:8765`，硬刷新（⌘⇧R）避免缓存。
3. 改字段保存 → 看「✅ 已保存并生效」+ 后端日志「配置已更新并热生效」。
4. 输入含 `"` `<` 的字符测 `esc()` 是否生效（页面不崩、不被解释成 HTML）。
