// Compiled together with status_popover.swift by scripts/check-status-popover.sh.

extension StatusPopoverController {
    func verifyClick(at fraction: CGFloat, expected: Bool) {
        popover.animates = false
        let button = statusItem!.button!
        let local = NSPoint(x: button.bounds.width * fraction, y: button.bounds.midY)
        let hit = button.hitTest(button.convert(local, to: button.superview))
        precondition(hit === clickView, "Button region did not hit the native click view")
        let event = NSEvent.mouseEvent(with: .leftMouseUp, location: button.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: button.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        clickView.mouseDown(with: event)
        clickView.mouseUp(with: event)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        print("click x=\(fraction): shown=\(popover.isShown), expected=\(expected), hitWidth=\(clickView.bounds.width), buttonWidth=\(button.bounds.width)"); fflush(stdout)
        precondition(popover.isShown == expected, "Popover click toggle failed")
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
private let controller = StatusPopoverController(statusItem: item, callback: { _ in })
controller.update(title: "41%  ·  4小时后重置", percentage: "41%", windowName: "5-hour quota", progress: 0.41, modelName: "gpt-6-astra", resetTime: "2026-10-04 22:41 +08:00", statusText: "Synced", statusCode: 0, startAtLogin: true)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
controller.verifyClick(at: 0.15, expected: true)
controller.verifyClick(at: 0.85, expected: false)
controller.update(title: "100%  ·  3小时25分钟后重置", percentage: "100%", windowName: "5-hour quota", progress: 1, modelName: "gpt-6-astra", resetTime: "2026-10-05 00:41 +08:00", statusText: "Synced", statusCode: 0, startAtLogin: true)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
controller.verifyClick(at: 0.95, expected: true)
controller.verifyClick(at: 0.05, expected: false)
NSStatusBar.system.removeStatusItem(item)
