# 发布说明

## 当前版本内容

当前源码版本为 `0.1.8`。Codex Lens 同时提供 macOS **桌面组件**和**状态栏胶囊**：

- 桌面组件：原生 WidgetKit 小、中尺寸，支持五小时与每周额度以及周窗口单独显示。
- 状态栏胶囊：原生 AppKit 额度环、五小时剩余百分比、重置倒计时与点击详情卡片。
- 详情操作：手动刷新、开机启动设置和退出，刷新期间与过期数据具有明确状态。
- 胶囊只使用五小时额度；缺失时显示不可用，或保留此前有效五小时值并标记过期。

## 源码更新与下载版本

推送 `main` 更新 GitHub 源码和文档，并触发 CI，不会自动创建新下载版本。

推送 `v*` tag 会触发 `.github/workflows/release.yml`，构建并发布 GitHub Release。当前工作流配置为 `draft: false`，因此 tag 推送是公开发布动作。不要把普通源码同步当成已经完成安装包发布。

## 当前 CI 和 Release 产物

- `quota-float-windows-unsigned.zip`
- `quota-float-macos-universal-unsigned.zip`

以上文件名是现有工作流沿用的历史名称。macOS Universal 构建包含 Apple Silicon 与 Intel 的 Tauri 主应用和原生状态栏胶囊；**普通 Tauri 构建不会自动编译、签名并嵌入 WidgetKit 桌面组件扩展**。Windows 包不包含 WidgetKit 桌面组件或 AppKit 状态栏胶囊。

CI 在 push/PR 时执行前端测试、前端构建、npm audit、Windows/macOS Rust 测试及 Tauri 构建。macOS 安装 `aarch64-apple-darwin` 和 `x86_64-apple-darwin`，使用：

```bash
npm run tauri -- build --target universal-apple-darwin
```

## 包含桌面组件和状态栏胶囊的本地整合包

在 Xcode 选择 Apple Development Team，并用同一 Team 签名主应用与扩展：

```bash
CODE_SIGN_IDENTITY="Apple Development: …" DEVELOPMENT_TEAM="…" \
  scripts/package-codex-lens-macos.sh
```

脚本将 `CodexLensWidgetExtension.appex` 嵌入 `Codex Lens.app/Contents/PlugIns`，校验主应用和扩展的签名、Team 与 App Group。安装并启动这个单一应用后，可使用状态栏胶囊，也可在桌面“编辑小组件”中添加小、中尺寸桌面组件。

这个脚本用于本地签名整合，不会上传、发布或公证。当前整合脚本使用本机 Rust 默认 target，不应把它描述为已经验证的 Universal 分发流程。仓库只保存 App Group 后缀，不保存个人 Team ID、证书或 provisioning profile。

## 安装与分发限制

现有 CI/Release 下载包未签名、未公证。macOS 首次打开可通过右键应用选择 Open，并按系统提示操作；Windows 可能出现未知发布者提示。公开分发整合 WidgetKit 的安装包需要单独验证签名、entitlements、安装与分发流程。

发布前按 [测试矩阵](TEST-MATRIX.md) 记录实际结果；不能把普通 Tauri 包构建成功写成桌面组件签名整合验收通过。
