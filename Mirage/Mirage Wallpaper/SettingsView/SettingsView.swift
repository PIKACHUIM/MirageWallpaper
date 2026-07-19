//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import Cocoa
import SwiftUI

protocol SettingsPage: View {
    var viewModel: GlobalSettingsViewModel { get set }
    
    init(globalSettings: GlobalSettingsViewModel)
}

extension AppDelegate {
    @objc func jumpToPerformance() {
        self.globalSettingsViewModel.selection = 0
    }
    
    @objc func jumpToGeneral() {
        self.globalSettingsViewModel.selection = 1
    }
    
    @objc func jumpToPlugins() {
        self.globalSettingsViewModel.selection = 2
    }

    @objc func jumpToScreenSaver() {
        self.globalSettingsViewModel.selection = 3
    }
    
    @objc func jumpToAbout() {
        self.globalSettingsViewModel.selection = 4
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: GlobalSettingsViewModel
    @ObservedObject private var localization = MirageLocalization.shared
    
    var body: some View {
        VStack {
            Group {
                switch viewModel.selection {
                case 0:
                    PerformancePage(globalSettings: viewModel)
                case 1:
                    GeneralPage(globalSettings: viewModel)
                case 2:
                    PluginsPage(globalSettings: viewModel)
                case 3:
                    ScreenSaverPage(globalSettings: viewModel)
                case 4:
                    AboutUsView()
                default:
                    fatalError()
                }
            }
            .frame(minHeight: 400, maxHeight: 800)

            HStack {
                if let savedSettings = try? JSONDecoder()
                    .decode(GlobalSettings.self,
                        from: UserDefaults.standard.data(forKey: "GlobalSettings")
                            ?? Data()), viewModel.settings != savedSettings {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.yellow)
                    Text("已修改")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.save()
                    AppDelegate.shared.settingsWindow.close()
                } label: {
                    Text("好").frame(width: 50)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    AppDelegate.shared.settingsWindow.close()
                } label: {
                    Text("取消").frame(width: 50)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 500)
        .environment(\.locale, localization.locale)
    }
}

extension AppDelegate: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [SettingsToolbarIdentifiers.performance, SettingsToolbarIdentifiers.general, SettingsToolbarIdentifiers.plugins, SettingsToolbarIdentifiers.screenSaver, SettingsToolbarIdentifiers.about]
    }
        
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [SettingsToolbarIdentifiers.performance, SettingsToolbarIdentifiers.general, SettingsToolbarIdentifiers.plugins, SettingsToolbarIdentifiers.screenSaver, SettingsToolbarIdentifiers.about]
    }
    
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [SettingsToolbarIdentifiers.performance, SettingsToolbarIdentifiers.general, SettingsToolbarIdentifiers.plugins, SettingsToolbarIdentifiers.screenSaver, SettingsToolbarIdentifiers.about]
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        switch itemIdentifier {
        case SettingsToolbarIdentifiers.performance:
            toolbarItem.action = #selector(jumpToPerformance)
            toolbarItem.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil)
            toolbarItem.label = L("性能")

        case SettingsToolbarIdentifiers.general:
            toolbarItem.action = #selector(jumpToGeneral)
            toolbarItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
            toolbarItem.label = L("通用")
            
        case SettingsToolbarIdentifiers.plugins:
            toolbarItem.action = #selector(jumpToPlugins)
            toolbarItem.image = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
            toolbarItem.label = L("插件")

        case SettingsToolbarIdentifiers.screenSaver:
            toolbarItem.action = #selector(jumpToScreenSaver)
            toolbarItem.image = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: nil)
            toolbarItem.label = L("屏保")
            
        case SettingsToolbarIdentifiers.about:
            toolbarItem.action = #selector(jumpToAbout)
            toolbarItem.image = NSImage(systemSymbolName: "person.3", accessibilityDescription: nil)
            toolbarItem.label = L("关于")
            
        default:
            fatalError()
        }
        
        toolbarItem.isBordered = false
        
        return toolbarItem
    }
}

extension AppDelegate {
    func refreshSettingsToolbarLocalization() {
        guard let toolbar = settingsWindow?.toolbar else { return }
        for item in toolbar.items {
            switch item.itemIdentifier {
            case SettingsToolbarIdentifiers.performance: item.label = L("性能")
            case SettingsToolbarIdentifiers.general: item.label = L("通用")
            case SettingsToolbarIdentifiers.plugins: item.label = L("插件")
            case SettingsToolbarIdentifiers.screenSaver: item.label = L("屏保")
            case SettingsToolbarIdentifiers.about: item.label = L("关于")
            default: continue
            }
            item.paletteLabel = item.label
            item.toolTip = item.label
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject({ () -> GlobalSettingsViewModel in 
                let viewModel = GlobalSettingsViewModel()
                viewModel.selection = 2
                return viewModel
            }())
            .frame(width: 500, height: 600)
    }
}
