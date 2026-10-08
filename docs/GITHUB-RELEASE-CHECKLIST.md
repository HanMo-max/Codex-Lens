# GitHub 更新与发布清单

## 更新源码

1. 确认 origin 指向 `https://github.com/HanMo-max/Codex-Lens.git`，拉取并核对远端 `main`。
2. 同步最新代码，首页明确说明 **桌面组件**和**状态栏胶囊**，分别说明平台、数据窗口与交互。
3. 执行前端测试、前端构建、Rust 测试；在活动 macOS 图形会话运行 `scripts/check-status-popover.sh`。
4. 检查 diff、敏感信息与待提交清单。构建产物、个人截图、凭据、证书和 provisioning profile 不加入源码提交。
5. 提交并正常推送到 `main`，核对 GitHub 远端提交与 CI 状态。

推送 `main` 只更新源码和文档，不创建新 Release。

## 发布下载版本

当前 `.github/workflows/release.yml` 在 `v*` tag 推送后构建并公开发布 Release，配置为 `draft: false`。执行 tag 推送前，应完成以下检查：

- 明确发布版本和说明，写出桌面组件与状态栏胶囊的支持边界。
- 前端、Rust 与对应平台构建通过，实机验证结果已记录。
- 当前工作流生成 `quota-float-windows-unsigned.zip` 与 `quota-float-macos-universal-unsigned.zip`。
- 普通 macOS Tauri 包提供原生状态栏胶囊，但不自动包含 WidgetKit 桌面组件；Windows 包不提供这两项 macOS 原生功能。
- 若发布包含桌面组件的整合包，先单独验证主应用与嵌入扩展的签名、Team、App Group、安装及分发方式。详见 [发布说明](RELEASE.md)。
- Release 附件与文字描述一致，未将本地构建或 fixture 测试描述为公开安装包验收通过。
