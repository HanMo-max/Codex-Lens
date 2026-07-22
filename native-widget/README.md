# Codex Lens WidgetKit

这是 Codex Lens 内嵌的原生 macOS 系统小组件工程。

- A：`systemSmall`，显示当前可用额度与额度环。
- B：`systemMedium`，额外显示下次重置、本周额度与重置机会。当 Codex 不提供 5 小时窗口时，当前可用额度直接使用本周剩余额度。

Tauri App 会把不含凭据的快照写入 App Group 容器：

`<YOUR_TEAM_ID>.dev.codexlens.shared/widget-snapshot.json`

`CodexLensAppGroup.xcconfig` 是唯一后缀配置来源。Xcode 在构建时用当前开发者选择的 `DEVELOPMENT_TEAM` 展开实际 App Group；仓库不保存个人 Team ID。

WidgetKit 每分钟读取一次共享快照；Codex Lens 主程序启动时立即同步，之后每分钟在后台刷新额度与当前模型。共享容器不可用时，Widget 保留最近一次有效快照或显示不可用状态，不会把私有沙盒路径当作共享成功。

本地编译（不签名）：

```sh
xcodebuild -project CodexLensWidgets.xcodeproj -target CodexLensWidgetExtension -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

正式构建由 `scripts/package-codex-lens-macos.sh` 完成。脚本会把签名后的扩展嵌入 `Codex Lens.app/Contents/PlugIns`，最终只安装一个应用。
