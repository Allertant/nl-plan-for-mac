import AppKit

/// AppDelegate — 处理菜单栏图标右键上下文菜单
/// SwiftUI 的 MenuBarExtra(.window) 不自带右键菜单，需通过 AppKit 补充
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var rightClickMonitor: Any?
    private weak var statusBarButton: NSStatusBarButton?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 延迟执行，等待 SwiftUI 创建完 MenuBarExtra 对应的 NSStatusItem
        attemptSetup(retry: 0)
    }

    // MARK: - Setup with Retry

    private func attemptSetup(retry: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if let button = self.findMenuBarButton() {
                self.setupRightClickMenu(for: button)
            } else if retry < 5 {
                self.attemptSetup(retry: retry + 1)
            }
        }
    }

    // MARK: - Right-Click Context Menu

    private func setupRightClickMenu(for button: NSStatusBarButton) {
        statusBarButton = button

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            if self?.showMenuIfRightClicked(event: event) == true {
                return nil
            }
            return event
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = nil
        menu.addItem(quitItem)
        return menu
    }

    /// 通过窗口层级查找 MenuBarExtra 创建的 NSStatusBarButton
    private func findMenuBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            // MenuBarExtra 的窗口类名包含 "StatusBar"
            guard className.contains("StatusBar") else { continue }
            if let button = findStatusBarButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    /// 递归搜索视图层级中的 NSStatusBarButton
    private func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let found = findStatusBarButton(in: subview) {
                return found
            }
        }
        return nil
    }

    /// 检测右键是否点击在菜单栏图标上，是则弹出上下文菜单
    @discardableResult
    private func showMenuIfRightClicked(event: NSEvent) -> Bool {
        guard let button = statusBarButton else { return false }
        let mouseLocation = NSEvent.mouseLocation
        guard let buttonWindow = button.window else { return false }

        let buttonFrameInScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        guard buttonFrameInScreen.contains(mouseLocation) else { return false }

        let menu = buildMenu()
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
