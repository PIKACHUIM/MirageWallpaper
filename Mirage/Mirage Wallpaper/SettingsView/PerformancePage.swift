//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct PerformancePage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel

    @State private var isEditingFPS = false

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            Section {
                Picker("其他应用获得焦点时", selection: $viewModel.settings.otherApplicationFocused) {
                    Text("保持运行").tag(GSPlayback.keepRunning)
                    Text("静音").tag(GSPlayback.mute)
                    Text("暂停").tag(GSPlayback.pause)
                }
                Picker("其他应用全屏时", selection: $viewModel.settings.otherApplicationFullscreen) {
                    Text("保持运行").tag(GSPlayback.keepRunning)
                    Text("静音").tag(GSPlayback.mute)
                    Text("暂停").tag(GSPlayback.pause)
                    Text("停止（释放内存）").tag(GSPlayback.stop)
                }
                Picker("其他应用播放音频时", selection: $viewModel.settings.otherApplicationPlayingAudio) {
                    Text("保持运行").tag(GSPlayback.keepRunning)
                    Text("静音").tag(GSPlayback.mute)
                    Text("暂停").tag(GSPlayback.pause)
                }
                Picker("显示器睡眠时", selection: $viewModel.settings.displayAsleep) {
                    Text("保持运行").tag(GSPlayback.keepRunning)
                    Text("暂停").tag(GSPlayback.pause)
                    Text("停止（释放内存）").tag(GSPlayback.stop)
                }
                Picker("笔记本使用电池时", selection: $viewModel.settings.laptopOnBattery) {
                    Text("保持运行").tag(GSPlayback.keepRunning)
                    Text("暂停").tag(GSPlayback.pause)
                    Text("停止（释放内存）").tag(GSPlayback.stop)
                }
            } header: {
                Label("播放规则", systemImage: "play.fill")
            }

            Section {
                HStack(spacing: 1) {
                    Button { viewModel.setQuality(.low) } label: { Text("低").frame(maxWidth: .infinity) }
                    Divider()
                    Button { viewModel.setQuality(.medium) } label: { Text("中").frame(maxWidth: .infinity) }
                    Divider()
                    Button { viewModel.setQuality(.high) } label: { Text("高").frame(maxWidth: .infinity) }
                    Divider()
                    Button { viewModel.setQuality(.ultra) } label: { Text("极致").frame(maxWidth: .infinity) }
                }
                .padding(6)
                .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                .buttonStyle(.borderless)
                .clipShape(RoundedRectangle(cornerRadius: 5.0))

                Picker("抗锯齿", selection: $viewModel.settings.antiAliasing) {
                    Text("关闭").tag(GSAntiAliasingQuality.none)
                    Text("MSAA ×2").tag(GSAntiAliasingQuality.msaa_x2)
                    Text("MSAA ×4").tag(GSAntiAliasingQuality.msaa_x4)
                    Text("MSAA ×8").tag(GSAntiAliasingQuality.msaa_x8)
                }

                Picker("渲染分辨率", selection: $viewModel.settings.textureResolution) {
                    Text("原生（最高画质）").tag(GSTextureResolutionQuality.highQuality)
                    Text("75%（自动）").tag(GSTextureResolutionQuality.automatic)
                    Text("50%（高性能）").tag(GSTextureResolutionQuality.highPerformance)
                }

                Picker("壁纸加载方式", selection: Binding(
                    get: { viewModel.settings.wallpaperLoadSource ?? .disk },
                    set: { viewModel.settings.wallpaperLoadSource = $0 }
                )) {
                    Text("从磁盘加载（较低内存占用）").tag(GSWallpaperLoadSource.disk)
                    Text("从内存加载（减少磁盘读取）").tag(GSWallpaperLoadSource.memory)
                }

                HStack {
                    Text("帧率")
                    Spacer()
                    Slider(value: $viewModel.settings.fps, in: 10...120, step: 1)
                        .frame(width: 150)
                        .onChange(of: viewModel.settings.fps) { _, v in
                            AppDelegate.shared.wallpaperViewModel.renderer.setFps(Int(v))
                        }
                    Text(String(format: "%.0f", viewModel.settings.fps))
                        .frame(width: 30).monospacedDigit()
                    if viewModel.settings.fps > 60 {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            .help("过高的帧率会显著增加耗电与占用。")
                    } else if viewModel.settings.fps > 30 {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            .help("较高的帧率会增加耗电。")
                    }
                }

                Toggle("启用音频频谱（场景与网页壁纸）", isOn: $viewModel.settings.enableSpectrum)
            } header: {
                Label("渲染质量", systemImage: "memorychip.fill")
            } footer: {
                Text("抗锯齿、渲染分辨率和壁纸加载方式在切换壁纸后生效；内存模式会增加内存占用，但可避免播放期间反复读取壁纸文件。帧率调节实时生效。网页帧率限制只约束主页面动画回调，不是媒体、CSS 和 WebKit 合成的硬上限。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: viewModel.settings) { _, _ in viewModel.save() }
    }
}
