//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct GeneralPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel

    @State private var pathRefresh = 0
    @State private var showMirrorWarning = false

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }

    private func applyEndpointChange() {
        AppDelegate.shared.workshopViewModel.items = []
        AppDelegate.shared.workshopViewModel.currentPage = 1
        AppDelegate.shared.workshopViewModel.search()
    }

    private func chooseDirectory(message: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = message
        panel.begin { resp in
            if resp == .OK, let url = panel.url { completion(url) }
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("开机时自动启动 Mirage", isOn: $viewModel.settings.autoStart)
            } header: {
                Label("启动", systemImage: "star.fill")
            }

            Section {
                Picker("外观", selection: $viewModel.settings.appearance) {
                    Text("浅色").tag(GSAppearance.light)
                    Text("深色").tag(GSAppearance.dark)
                    Text("跟随系统").tag(GSAppearance.followSystem)
                }
            } header: {
                Label("外观", systemImage: "paintpalette.fill")
            }

            Section {
                HStack {
                    Text("全局音量")
                    Slider(value: $viewModel.settings.masterVolume, in: 0...1)
                        .onChange(of: viewModel.settings.masterVolume) { _, _ in
                            AppDelegate.shared.wallpaperViewModel.reapplyVolume()
                        }
                    Text("\(Int(viewModel.settings.masterVolume * 100))%")
                        .monospacedDigit().frame(width: 40)
                }
                Toggle("全局静音", isOn: $viewModel.settings.globalMuted)
                    .onChange(of: viewModel.settings.globalMuted) { _, _ in
                        AppDelegate.shared.wallpaperViewModel.reapplyVolume()
                    }
            } header: {
                Label("音频", systemImage: "speaker.wave.3.fill")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("创意工坊目录").font(.callout)
                    Text(WallpaperLibrary.shared.steamWorkshopDirectory.path(percentEncoded: false))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack {
                        Button("选择目录…") {
                            chooseDirectory(message: "选择 Wallpaper Engine 创意工坊壁纸所在目录（431960）") { url in
                                WallpaperLibrary.shared.setWorkshopDirectory(url)
                                pathRefresh += 1
                                AppDelegate.shared.contentViewModel.refresh()
                            }
                        }
                        Button("在访达中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([WallpaperLibrary.shared.steamWorkshopDirectory])
                        }
                        if WallpaperLibrary.shared.isWorkshopDirectoryCustomized {
                            Button("恢复默认") {
                                WallpaperLibrary.shared.setWorkshopDirectory(nil)
                                pathRefresh += 1
                                AppDelegate.shared.contentViewModel.refresh()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("导入壁纸目录").font(.callout)
                    Text(WallpaperLibrary.shared.importedDirectory.path(percentEncoded: false))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack {
                        Button("选择目录…") {
                            chooseDirectory(message: "选择用于存放导入壁纸的目录") { url in
                                WallpaperLibrary.shared.setImportedDirectory(url)
                                pathRefresh += 1
                                AppDelegate.shared.contentViewModel.refresh()
                            }
                        }
                        Button("在访达中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([WallpaperLibrary.shared.importedDirectory])
                        }
                        if WallpaperLibrary.shared.isImportedDirectoryCustomized {
                            Button("恢复默认") {
                                WallpaperLibrary.shared.setImportedDirectory(nil)
                                pathRefresh += 1
                                AppDelegate.shared.contentViewModel.refresh()
                            }
                        }
                    }
                }

                Toggle("自动刷新壁纸库", isOn: $viewModel.settings.autoRefresh)
            } header: {
                Label("壁纸库", systemImage: "folder.fill")
            }
            .id(pathRefresh)

            if TimeZone.current.secondsFromGMT() == 8 * 3600 {
                Section {
                    Picker("Steam API 线路", selection: $viewModel.settings.steamAPIEndpoint) {
                        Text("SteamWebAPI").tag(GSSteamAPIEndpoint.official)
                        Text("SteamCF 镜像").tag(GSSteamAPIEndpoint.mirror)
                    }
                    .onChange(of: viewModel.settings.steamAPIEndpoint) { _, newValue in
                        if newValue == .mirror {
                            showMirrorWarning = true
                        } else {
                            applyEndpointChange()
                        }
                    }
                } header: {
                    Label("创意工坊", systemImage: "network")
                }
                .alert("SteamCF 镜像警告", isPresented: $showMirrorWarning) {
                    Button("仍要使用") {
                        applyEndpointChange()
                    }
                    Button("取消", role: .cancel) {
                        viewModel.settings.steamAPIEndpoint = .official
                    }
                } message: {
                    Text("这是镜像 API，非官方，不保证安全性和可用性。镜像 API 不镜像下载，只能加速 API 回应而不能加速下载。")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Steam Web API Key", text: $viewModel.settings.steamAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Text("可前往 [steamcommunity.com/dev/apikey](https://steamcommunity.com/dev/apikey) 申请。填写域名时随意编写即可，不要使用已被注册的大型域名（如 baidu.com）。留空则使用内置 Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Steam API Key", systemImage: "key.fill")
            }

            Section {
                Toggle("详细日志（供调试）", isOn: $viewModel.settings.verboseLog)
                HStack {
                    Text("重置所有设置")
                    Spacer()
                    Button {
                        viewModel.settings = GlobalSettings()
                    } label: {
                        Text("重置").frame(width: 100)
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Label("高级", systemImage: "wrench.and.screwdriver.fill")
            }
        }
        .formStyle(.grouped)
        .onChange(of: viewModel.settings) { _, _ in viewModel.save() }
    }
}
