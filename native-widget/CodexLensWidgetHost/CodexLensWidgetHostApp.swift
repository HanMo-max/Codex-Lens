import AppKit
import SwiftUI
import WidgetKit

@main
struct CodexLensWidgetHostApp: App {
    var body: some Scene {
        WindowGroup("Codex Lens Widgets") {
            WidgetHostView()
                .frame(minWidth: 420, minHeight: 250)
                .onAppear(perform: launchPreviewRendererIfRequested)
        }
    }

    private func launchPreviewRendererIfRequested() {
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexLensWidget")
    }
}

private struct WidgetHostView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.tint)

            Text("Codex Lens 系统小组件")
                .font(.title2.weight(.semibold))

            Text("在桌面空白处右键，选择“编辑小组件”，然后搜索 Codex Lens。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Label("小组件显示的是 Codex Lens 写入的本地额度快照。", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }
}
