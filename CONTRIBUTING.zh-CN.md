[English](./CONTRIBUTING.md) | **简体中文**

# 贡献指南

欢迎贡献！提 issue 或 PR 前请先读这份指南。

## 开发环境

```bash
git clone https://github.com/Ethereal49/openvibeboard.git
cd openvibeboard
xcodegen generate                            # 读 project.yml 生成 OpenVibeBoard.xcodeproj
open OpenVibeBoard.xcodeproj                 # Xcode 里 ⌘R 运行
```

运行需要：macOS 15+、Xcode 16+、[xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）、授权「辅助功能」（见 [README](README.md) 权限章节）。依赖（ORSSerialPort）由 SPM 自动拉取。

## 编码约定

本项目用 Trellis 管理开发流程，**编码约定的唯一事实来源是 `.trellis/spec/`**：

- [`backend/`](.trellis/spec/backend/) —— Swift app 约定（CGEvent modifier flag 坑、串口协议、Config schema、actor 并发、串口错误码、stderr 日志）
- [`guides/`](.trellis/spec/guides/) —— 通用思考指南（语言无关）

改代码前先读对应 spec。**约定优先于个人偏好**；若认为某约定有害，先开 issue 讨论，不要偷偷另搞一套。

> v0.1 的 Web UI 约定已弃（SwiftUI Settings 替代），`frontend/` 目录已删除。

## 提交规范

- 小步提交，commit message 写清「改了什么 + 为什么」。
- 不引入新依赖前先讨论（SPM 依赖尤其要先过 `project.yml`）。
- 改 `Key/KeyInjector.swift` 或 `Actions/ActionDispatcher.swift` 的按键注入 / 动作分发逻辑后，务必手动回归验证 `cmd` / `key tap` / `key hold` / `text` 四种动作（C 实测门，验证步骤见 `.trellis/spec/backend/quality-guidelines.md`）。
- 改 `Serial/SerialMonitor.swift` 的行解析后，补 `OpenVibeBoardTests/SerialMonitorTests.swift` 对应分支。
