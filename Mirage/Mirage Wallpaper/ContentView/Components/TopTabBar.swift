//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct TopTabBar: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel
    
    init(contentViewModel viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(alignment: .bottom) {
                    Button {
                        viewModel.topTabBarSelection = 0
                    } label: {
                        Label("已安装", systemImage: "square.and.arrow.down.fill")
                            .contentShape(Rectangle())
                            .foregroundStyle(viewModel.topTabBarSelection == 0 || viewModel.topTabBarHoverSelection == 0 ? .white : .primary)
                            .font(.title2)
                            .padding(4)
                    }
                    .background(viewModel.topTabBarSelection == 0 ? Color.blue : Color.clear)
                    .background(viewModel.topTabBarHoverSelection == 0 ? Color.blue : Color.clear)
                    .overlay(Rectangle()
                        .stroke(lineWidth: 2)
                        .foregroundStyle(Color.accentColor))
                    .onHover { hovering in
                        viewModel.topTabBarHoverSelection = hovering ? 0 : -1
                    }

                    Button {
                        viewModel.topTabBarSelection = 1
                    } label: {
                        Label("发现", systemImage: "sparkle.magnifyingglass")
                            .contentShape(Rectangle())
                            .foregroundStyle(viewModel.topTabBarSelection == 1 ? .white : .primary)
                            .foregroundStyle(viewModel.topTabBarHoverSelection == 1 ? .white : .primary)
                            .font(.title3)
                            .padding(4)
                    }
                    .background(viewModel.topTabBarSelection == 1 ? Color.blue : Color.clear)
                    .background(viewModel.topTabBarHoverSelection == 1 ? Color.blue : Color.clear)
                    .overlay(Rectangle()
                        .stroke(lineWidth: 2)
                        .foregroundStyle(Color.accentColor))
                    .onHover { hovering in
                        viewModel.topTabBarHoverSelection = hovering ? 1 : -1
                    }

                    Button {
                        viewModel.topTabBarSelection = 2
                    } label: {
                        Label("创意工坊", systemImage: "cloud.fill")
                            .contentShape(Rectangle())
                            .foregroundStyle(viewModel.topTabBarSelection == 2 ? .white : .primary)
                            .foregroundStyle(viewModel.topTabBarHoverSelection == 2 ? .white : .primary)
                            .font(.title3)
                            .padding(.vertical, 4)
                            .padding(.leading, 4)
                            .padding(.trailing, AppDelegate.shared.workshopViewModel.activeDownloadCount > 0 ? 16 : 4)
                    }
                    .background(viewModel.topTabBarSelection == 2 ? Color.blue : Color.clear)
                    .background(viewModel.topTabBarHoverSelection == 2 ? Color.blue : Color.clear)
                    .overlay(Rectangle()
                        .stroke(lineWidth: 2)
                        .foregroundStyle(Color.accentColor))
                    .overlay(alignment: .topTrailing) {
                        if AppDelegate.shared.workshopViewModel.activeDownloadCount > 0 {
                            Text("\(AppDelegate.shared.workshopViewModel.activeDownloadCount)")
                                .font(.system(size: 9))
                                .bold()
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Color.red, in: Capsule())
                                .padding(2)
                        }
                    }
                    .onHover { hovering in
                        viewModel.topTabBarHoverSelection = hovering ? 2 : -1
                    }
                }
                .animation(.default, value: viewModel.topTabBarSelection)
                .animation(.default, value: viewModel.topTabBarHoverSelection)
                .fixedSize()
                .buttonStyle(.plain)

                Spacer()
                    .frame(minWidth: 10)

                Group {
                    Divider()
                    Button { } label: {
                        Label("移动端", systemImage: "platter.filled.bottom.iphone")
                            .contentShape(Rectangle())
                    }
                    Divider()
                    Button {
                        viewModel.isDisplaySettingsReveal = true
                    } label: {
                        Label("显示器", systemImage: "display")
                            .contentShape(Rectangle())
                    }
                    Divider()
                    Button {
                        AppDelegate.shared.openSettingsWindow()
                    } label: {
                        Label("设置", systemImage: "gearshape.fill")
                            .contentShape(Rectangle())
                    }
                    Divider()
                }
                .fixedSize()
                .buttonStyle(.plain)
            }
            .offset(x: 1)
            Divider()
                .frame(height: 4)
                .overlay(Color.accentColor)
        }
    }
}
