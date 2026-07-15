//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import Cocoa
import SwiftUI

class MainWindowController: NSWindowController, NSWindowDelegate {
    override var window: NSWindow! {
        get {
            return super.window
        }
        set {
            super.window = newValue
        }
    }
    
    override init(window: NSWindow?) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1029, height: 669),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.isRestorable = false
        super.init(window: win)
        self.window.delegate = self
        self.window.isReleasedWhenClosed = false
        self.window.title = "Mirage \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")"
        self.window.titlebarAppearsTransparent = true
        self.window.setFrameAutosaveName("MainWindow")
        self.window.isMovableByWindowBackground = true
        self.window.contentMinSize = NSSize(width: 1000, height: 640)

        let hostingView = NSHostingView(rootView: ContentView(
                viewModel: AppDelegate.shared.contentViewModel,
                wallpaperViewModel: AppDelegate.shared.wallpaperViewModel
            ).environmentObject(AppDelegate.shared.globalSettingsViewModel)
        )
        // 关键修复: 禁用 NSHostingView 基于 SwiftUI 内容尺寸自动生成/更新
        // Auto Layout 约束的行为。默认情况下 NSHostingView 会根据内容的
        // intrinsicContentSize/minSize 等在每次 graph change 时更新约束，
        // 当窗口内含 TextField / .background 等桥接 AppKit 的子视图时，
        // 会在 display cycle 中形成 setNeedsUpdateConstraints 无限循环。
        // 设为 [] 后改由 autoresizingMask 驱动尺寸，彻底切断循环。
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(origin: .zero, size: self.window.contentLayoutRect.size)
        self.window.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared.contentViewModel.isStaging = false
        if !AppDelegate.shared.settingsWindow.isVisible {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    func windowDidResignKey(_ notification: Notification) { }

    func windowDidResignMain(_ notification: Notification) { }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // 延迟到下一个 runloop 周期，避免在 display cycle 中触发约束更新循环
        DispatchQueue.main.async {
            AppDelegate.shared.contentViewModel.isStaging = true
        }
    }
}
