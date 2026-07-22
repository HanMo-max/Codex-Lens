# Codex Lens WidgetKit 实现状态

## 已完成

- 原生 Xcode 工程：`CodexLensWidgets.xcodeproj`
- 最终 Host App：`Codex Lens.app`（Tauri 主程序）
- WidgetKit Extension：`CodexLensWidgetExtension.appex`
- A 小尺寸：`systemSmall`，显示当前可用额度环、百分比、重置时间与同步状态。
- B 展开尺寸：`systemMedium`，显示当前可用额度、本周额度、下次重置与重置机会。Codex 不提供 5 小时窗口时，额度环回退为本周剩余额度。
- WidgetKit 时间线：每分钟读取一次本地快照。
- 主程序后台同步：启动时立即同步，之后每 1 分钟同时写入额度、当前模型与本周剩余额度。
- Tauri 数据桥：通过构建时展开的 Team-ID App Group `<YOUR_TEAM_ID>.dev.codexlens.shared` 原子写入不含凭据的 `widget-snapshot.json`，不写入 access token 或账户标识。
- 无签名 Xcode 编译：通过。
- Tauri 前端构建、Rust 单元测试与 WidgetKit 编译：通过。

## 快照数据位置

动态 Team-ID App Group 内的 `widget-snapshot.json`，并保留 `widget-snapshot.last-known-good.json` 作为损坏或不兼容数据的安全回退。实际标识由 `CodexLensAppGroup.xcconfig` 的后缀与构建者选择的 `DEVELOPMENT_TEAM` 组成，不在源码中固化个人 Team ID。

该文件由 Codex Lens 在刷新额度后以原子写入方式生成，内容仅限显示数据。

## 打包与部署

运行整合脚本：

```sh
CODE_SIGN_IDENTITY="Apple Development: …" DEVELOPMENT_TEAM="…" scripts/package-codex-lens-macos.sh
```

脚本会生成单一的 `Codex Lens.app`，并在内部嵌入已签名的 WidgetKit 扩展。安装后：

1. 运行 `Codex Lens.app`。
2. 在桌面空白处右键，选择“编辑小组件”。
3. 搜索 `Codex Lens`。
4. 选择小尺寸 A 或中尺寸 B。
