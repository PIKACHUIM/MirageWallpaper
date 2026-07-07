//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct SteamCMDStep: View {
    @ObservedObject var viewModel: SteamSetupViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Group {
                switch viewModel.steamCMDInstallState {
                case .detecting:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在检测 SteamCMD...")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                case .found(let path):
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))

                        Text("已找到 SteamCMD")
                            .font(.title2)
                            .bold()

                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                case .notFound:
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("未找到 SteamCMD")
                            .font(.title2)
                            .bold()

                        Text("SteamCMD 是 Valve 的官方命令行工具，用于下载 Steam 创意工坊内容。\n安装大小约 50MB。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)

                        Button {
                            viewModel.installSteamCMD()
                        } label: {
                            Label("安装 SteamCMD", systemImage: "arrow.down.app.fill")
                                .frame(width: 160)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .downloading(let progress):
                    VStack(spacing: 16) {
                        ProgressView(value: progress)
                            .frame(width: 200)
                            .animation(.linear, value: progress)

                        Text("正在下载 SteamCMD...")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Text("\(Int(progress * 100))%")
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.blue)
                    }

                case .extracting:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("正在解压...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                case .installed(let path):
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))

                        Text("安装完成")
                            .font(.title2)
                            .bold()

                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                case .failed(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)

                        Text("安装失败")
                            .font(.title2)
                            .bold()

                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        Button {
                            viewModel.installSteamCMD()
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.steamCMDInstallState)

            Spacer()
        }
        .padding()
        .onAppear {
            viewModel.detectSteamCMD()
        }
    }
}
