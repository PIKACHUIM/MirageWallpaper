//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import Cocoa

extension AppDelegate {
    func setMainMenu() {
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu(title: "Mirage")
        appMenu.submenu?.items = [
            .init(title: "关于 Mirage", action: #selector(self.showAboutUs), keyEquivalent: ""),
            .init(title: "检查更新…", action: #selector(UpdateManager.checkForUpdates(_:)), keyEquivalent: ""),
            .separator(),
            .init(title: "设置…", action: #selector(openSettingsWindow), keyEquivalent: ","),
            .separator(),
            .init(title: "隐藏 Mirage", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            {
                let item = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
                item.keyEquivalentModifierMask = [.command, .option]
                return item
            }(),
            .separator(),
            .init(title: "退出 Mirage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]

        let fileMenu = NSMenuItem()
        fileMenu.submenu = NSMenu(title: "文件")
        fileMenu.submenu?.items = [
            .init(title: "导入壁纸…", action: #selector(openImportFromFolderPanel), keyEquivalent: "i"),
            .separator(),
            .init(title: "关闭窗口", action: #selector(AppDelegate.shared.mainWindowController.window.performClose), keyEquivalent: "w")
        ]

        let editMenu = NSMenuItem()
        editMenu.submenu = NSMenu(title: "编辑")
        editMenu.submenu?.items = [
            .init(title: "撤销", action: #selector(UndoManager.undo), keyEquivalent: "z"),
            .init(title: "重做", action: #selector(UndoManager.redo), keyEquivalent: "Z"),
            .separator(),
            .init(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            .init(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            .init(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            .init(title: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: String(NSBackspaceCharacter)),
            .separator(),
            .init(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        ]

        let viewMenu = NSMenuItem()
        viewMenu.submenu = NSMenu(title: "查看")
        viewMenu.submenu?.items = [
            {
                let item = NSMenuItem(title: "显示筛选结果", action: #selector(self.toggleFilter), keyEquivalent: "s")
                item.keyEquivalentModifierMask = [.command, .control]
                return item
            }(),
            .separator(),
            {
                let item = NSMenuItem(title: "进入全屏", action: #selector(AppDelegate.shared.mainWindowController.window.toggleFullScreen(_:)), keyEquivalent: "f")
                item.keyEquivalentModifierMask = [.command, .control]
                return item
            }()
        ]

        let windowMenu = NSMenuItem()
        windowMenu.submenu = NSMenu(title: "窗口")
        windowMenu.submenu?.items = [
            {
                let item = NSMenuItem(title: "壁纸库", action: #selector(openMainWindow), keyEquivalent: "1")
                item.keyEquivalentModifierMask = [.command, .shift]
                return item
            }()
        ]

        let debugMenu = NSMenuItem(title: "调试", action: nil, keyEquivalent: "")
        debugMenu.submenu = NSMenu()
        debugMenu.submenu?.items = [
            .init(title: "重置首次启动标记", action: #selector(resetFirstLaunch), keyEquivalent: ""),
            .init(title: "重新渲染当前壁纸", action: #selector(reloadWallpaper), keyEquivalent: ""),
            .init(title: "重置所有已信任壁纸", action: #selector(resetTrustedWallpapers), keyEquivalent: "")
        ]

        let helpMenu = NSMenuItem()
        helpMenu.submenu = NSMenu(title: "帮助")
        helpMenu.submenu?.items = [
            .init(title: "Mirage 项目主页", action: #selector(openProjectPage), keyEquivalent: ""),
            debugMenu
        ]

        let mainMenu = NSMenu()
        mainMenu.items = [appMenu, fileMenu, editMenu, viewMenu, windowMenu, helpMenu]
        appMenu.submenu?.items.first { $0.action == #selector(UpdateManager.checkForUpdates(_:)) }?.target = UpdateManager.shared
        NSApplication.shared.mainMenu = mainMenu
    }

    @objc func reloadWallpaper() {
        wallpaperViewModel.reapplyCurrent()
    }

    @objc func resetTrustedWallpapers() {
        UserDefaults.standard.set([String](), forKey: "TrustedWallpapers")
    }
}

extension NSMenuItem {
    public convenience init(title: String, systemImage: String, action: Selector?, keyEquivalent: String) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
    }
}
