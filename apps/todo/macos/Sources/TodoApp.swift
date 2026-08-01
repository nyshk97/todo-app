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

        // 初回はカーソルを中心に配置
        positionAtCursor()
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
        // ローカルモニターは Accessibility 権限不要なので即座に登録
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // 起動直後は TCC デーモンの初期化が完了していないことがあるため遅延させる
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.registerGlobalMonitor()
        }
    }

    private func registerGlobalMonitor() {
        // 起動時は prompt を出さない。未権限でも登録はできる（コールバックが届かないだけ）
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    @objc private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
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

    private func positionAtCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = panel.frame.size

        // カーソル中心に配置し、visibleFrame からはみ出る場合はクランプ
        let centeredX = mouse.x - size.width / 2
        let centeredY = mouse.y - size.height / 2
        let x = max(visible.minX, min(centeredX, visible.maxX - size.width))
        let y = max(visible.minY, min(centeredY, visible.maxY - size.height))

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
            if !AXIsProcessTrusted() {
                menu.addItem(NSMenuItem(title: "アクセシビリティ権限を許可...", action: #selector(requestAccessibilityPermission), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }
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
        positionAtCursor()
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
