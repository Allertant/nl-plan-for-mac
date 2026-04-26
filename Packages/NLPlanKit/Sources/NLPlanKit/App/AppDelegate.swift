import AppKit

/// AppDelegate — 处理菜单栏图标右键上下文菜单
/// SwiftUI 的 MenuBarExtra(.window) 不自带右键菜单，需通过 AppKit 补充
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var rightClickMonitor: Any?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 延迟执行，等待 SwiftUI 创建完 MenuBarExtra 对应的 NSStatusItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.setupRightClickMenu()
        }
    }

    // MARK: - Right-Click Context Menu

    private func setupRightClickMenu() {
        guard let button = findMenuBarButton() else { return }

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "退出 NL Plan",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            if self?.showMenuIfRightClicked(on: button, menu: menu, event: event) == true {
                return nil // 消费事件，阻止传播
            }
            return event
        }
    }

    /// 查找 SwiftUI MenuBarExtra 创建的 NSStatusItem 的 button
    private func findMenuBarButton() -> NSStatusBarButton? {
        let statusBar = NSStatusBar.system
        guard let items = statusBar.value(forKey: "statusItems") as? [NSObject] else {
            return nil
        }
        // MenuBarExtra 通常是最后注册的 statusItem，逆序查找
        for item in items.reversed() {
            if let button = item.value(forKey: "button") as? NSStatusBarButton {
                return button
            }
        }
        return nil
    }

    /// 检测右键是否点击在菜单栏图标上，是则弹出上下文菜单
    @discardableResult
    private func showMenuIfRightClicked(
        on button: NSStatusBarButton,
        menu: NSMenu,
        event: NSEvent
    ) -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        guard let buttonWindow = button.window else { return false }

        // 将按钮 frame 转换到屏幕坐标系
        let buttonFrameInScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        guard buttonFrameInScreen.contains(mouseLocation) else { return false }

        // 在按钮左下角弹出菜单
        let menuOrigin = NSPoint(x: buttonFrameInScreen.minX, y: buttonFrameInScreen.minY)
        menu.popUp(positioning: nil, at: menuOrigin, in: nil)
        return true
    }

    // MARK: - Deinit

    deinit {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
