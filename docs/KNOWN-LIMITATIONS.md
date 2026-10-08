# 已知限制

- 桌面组件和原生状态栏胶囊都是 macOS 功能，桌面组件要求 macOS 14 或更高版本；Windows 构建不提供这两项原生入口。
- 状态栏胶囊只展示服务返回的有效五小时窗口。没有五小时窗口时，不用周额度替代，而是显示不可用或标记已保留数据为过期；桌面组件仍支持仅周窗口布局。
- Codex 数据来自非公开只读额度接口，字段或认证方式可能变化；不根据本地 token 消耗估算额度。
- WidgetKit 决定桌面组件的实际刷新时间。主程序每分钟同步和调用 timeline reload 不保证系统每分钟重绘组件。
- 普通 Tauri CI/Release 构建不会自动嵌入 WidgetKit 扩展；桌面组件需要包含扩展且主应用与扩展 Team、App Group 一致的签名整合安装。
- 当前 CI/Release 包未签名、未公证。现有本地整合脚本使用 Apple Development 签名，不等于已完成公开分发或公证验收。
- macOS Universal 普通 Tauri 包由 GitHub Actions 构建；本地签名整合脚本不声明 Universal 输出。
- 原生胶囊点击验证脚本需要活动的 macOS 图形会话。
- Claude provider 未启用，重置机会只能读取，不能在应用内兑换。
