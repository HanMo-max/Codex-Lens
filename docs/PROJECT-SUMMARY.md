# Codex Lens 项目简介

## 一句话定位

Codex Lens 是一个本地运行的 macOS 额度工具，同时提供**桌面组件**和**状态栏胶囊**，使用本机 Codex Desktop 登录态只读查询当前模型、额度与重置时间。项目独立维护，非 OpenAI 官方产品。

## 当前功能

- 桌面组件：WidgetKit 原生小、中两种尺寸，根据实际响应展示五小时和每周额度；只有周窗口时使用单窗口布局。
- 状态栏胶囊：AppKit 原生菜单栏入口，显示五小时剩余额度、额度环和重置倒计时，按完整文字调整宽度。
- 点击详情：点击胶囊打开或关闭原生弹出卡片，查看当前模型、重置时间与同步状态，手动刷新、设置开机启动或退出；右键可打开托盘菜单。
- 数据边界：胶囊只展示五小时额度，不用周额度替代；缺失或刷新失败时保留最近有效五小时值并标记过期，没有有效旧值时显示不可用。
- 同步：启动、每分钟后台轮询、唤醒、重新打开及手动操作触发刷新；共享快照成功发布后请求 WidgetKit 重新加载。
- 隐私：共享容器只保存显示快照，不持久化 token、账户标识或原始额度响应。

## 代码入口与技术栈

Tauri 启动入口 `src-tauri/src/main.rs` 调用 `src-tauri/src/lib.rs`，先建立托盘与原生胶囊，再启动后台同步。一次刷新同时更新胶囊展示和 WidgetKit 共享快照。

- React 19、TypeScript、Vite：前端与浏览器 mock 开发环境。
- Tauri 2、Rust：后台同步、额度解析、托盘与应用生命周期。
- `src-tauri/src/codex.rs`：本机登录态读取及只读额度请求。
- `src-tauri/src/status_bar.rs`：五小时窗口选择、过期状态、百分比与重置倒计时格式化。
- `src-tauri/src/status_popover.swift`：AppKit 胶囊、完整点击区域与原生详情交互。
- `src-tauri/build.rs`：仅在 macOS 编译 Swift 桥接。
- `native-widget/CodexLensWidgetExtension/CodexLensWidget.swift`：桌面组件布局、快照解析与时间线。
- `scripts/check-status-popover.sh`：使用 fixture 验证胶囊不同区域及宽度变化后的点击。
- `scripts/package-codex-lens-macos.sh`：签名并嵌入 WidgetKit 扩展，生成一个整合应用。

## 构建边界

桌面组件和原生状态栏胶囊都是 macOS 功能。现有 CI 仍保留 Windows 和 macOS Universal 的 Tauri 构建，但普通 Tauri 包不自动嵌入 WidgetKit 扩展。包含桌面组件的本地整合包需使用同一 Apple Team 签名主应用与扩展，详见 [README](../README.md) 和 [发布说明](RELEASE.md)。

## 验证

```bash
npm test
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
cargo check --manifest-path src-tauri/Cargo.toml
scripts/check-status-popover.sh
```

原生点击检查需要活动的 macOS 图形会话，使用 fixture，不读取真实账号。浏览器 mock、单元测试与本地构建不能代替真实额度、签名整合安装和实机验收。
