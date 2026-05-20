import ApplicationServices
import SwiftUI

@main
struct TodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastRightShiftPressTime: TimeInterval = 0
    private var rightShiftWasDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // フローティングパネル
        let contentView = NSHostingView(rootView: PanelContentView(onClose: { [weak self] in
            self?.panel.orderOut(nil)
        }))

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: 300, height: 400)

        // 右下に配置
        positionAtBottomRight()
        panel.orderFront(nil)

        // メニューバーアイコン
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo")
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupGlobalHotkey()
    }

    // MARK: - 右Shift ダブルタップでパネル表示/非表示をトグル

    private func setupGlobalHotkey() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // keyCode 60 = Right Shift, raw bit 0x4 = NX_DEVICERSHIFTKEYMASK
        guard event.keyCode == 60 else { return }
        let isDown = (event.modifierFlags.rawValue & 0x4) != 0

        defer { rightShiftWasDown = isDown }
        guard isDown, !rightShiftWasDown else { return }

        let now = event.timestamp
        if now - lastRightShiftPressTime < 0.3 {
            lastRightShiftPressTime = 0
            hotkeyToggle()
        } else {
            lastRightShiftPressTime = now
        }
    }

    private func hotkeyToggle() {
        if panel.isVisible && NSApp.isActive {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func positionAtBottomRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - panel.frame.width - 16
        let y = screenFrame.minY + 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let versionItem = NSMenuItem(title: "v\(version)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            // メニューを消した後、左クリックが効くように menu を外す
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    private func showPanel() {
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .panelDidShow, object: nil)
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }
}

// MARK: - Panel Content View (with close button)

struct PanelContentView: View {
    var onClose: () -> Void

    private var colors: AppColors { Theme.current }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ContentView()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(colors.closeButtonBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
}

extension Notification.Name {
    static let panelDidShow = Notification.Name("panelDidShow")
    static let backgroundTapped = Notification.Name("backgroundTapped")
}
