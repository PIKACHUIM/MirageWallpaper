//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct WorkshopView: View {
    @ObservedObject var workshopViewModel: WorkshopViewModel
    @ObservedObject var viewModel: ContentViewModel

    @State private var hoveredId: String?
    @State private var isDownloadPopoverPresented = false
    @State private var isSyncLogPresented = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                WorkshopSearchBar(workshopViewModel: workshopViewModel)

                Spacer()

                Button {
                    isDownloadPopoverPresented.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                        if workshopViewModel.activeDownloadCount > 0 {
                            Text("\(workshopViewModel.activeDownloadCount)")
                                .font(.system(size: 9))
                                .bold()
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 6, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isDownloadPopoverPresented) {
                    DownloadPopover(workshopViewModel: workshopViewModel)
                }

                steamAccountSection
            }

            if workshopViewModel.steamSetupState != .ready && workshopViewModel.items.isEmpty && !workshopViewModel.isLoading {
                steamSetupBanner
            }

            if workshopViewModel.syncState == .syncing {
                syncProgressBanner
            }

            if workshopViewModel.isLoading && workshopViewModel.items.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在搜索创意工坊...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if workshopViewModel.items.isEmpty && !workshopViewModel.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    if let error = workshopViewModel.error {
                        Text("加载失败")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("重试") { workshopViewModel.search() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("没有找到壁纸")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("试试调整搜索条件或筛选标签")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 440))], alignment: .leading, spacing: 12) {
                        ForEach(workshopViewModel.items) { item in
                            WorkshopItemCard(
                                item: item,
                                isHovered: hoveredId == item.id,
                                isDownloaded: SteamWebAPI.shared.isItemDownloaded(item.publishedFileId),
                                downloadState: workshopViewModel.downloadState(for: item.publishedFileId)
                            )
                            .onHover { hovered in
                                hoveredId = hovered ? item.id : nil
                            }
                            .onTapGesture {
                                workshopViewModel.showCustomization = false
                                workshopViewModel.selectedItem = item
                            }
                            .overlay {
                                if workshopViewModel.selectedItem?.id == item.id {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if workshopViewModel.isLoading {
                        ProgressView()
                            .padding()
                    }

                    pageControls
                        .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            workshopViewModel.checkSteamSetup()
            if workshopViewModel.items.isEmpty {
                workshopViewModel.search()
            }
        }
        .onChange(of: viewModel.topTabBarSelection) { _ in
            if viewModel.topTabBarSelection == 2 {
                workshopViewModel.checkSteamSetup()
            }
        }
    }

    // MARK: - Steam Account Section (#2)

    @ViewBuilder
    var steamAccountSection: some View {
        if workshopViewModel.steamSetupState == .ready {
            HStack(spacing: 8) {
                Button {
                    workshopViewModel.syncSubscribed()
                } label: {
                    switch workshopViewModel.syncState {
                    case .syncing:
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                            Text("同步中...")
                                .font(.caption)
                        }
                    default:
                        Label("同步已订阅", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                }
                .disabled(workshopViewModel.syncState == .syncing)
                .help("同步 Steam 上已订阅的 Wallpaper Engine 壁纸到本地")

                Divider()
                    .frame(height: 16)

                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(SteamCMDManager.shared.savedUsername)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    workshopViewModel.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("登出 Steam")
            }
        } else {
            Button {
                AppDelegate.shared.openSteamSetup()
            } label: {
                Label("设置 Steam", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Sync Progress Banner (#7)

    var syncProgressBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                Text("正在同步已订阅壁纸...")
                    .font(.caption)
                    .bold()
                Spacer()
                Button {
                    isSyncLogPresented.toggle()
                } label: {
                    Label(isSyncLogPresented ? "隐藏日志" : "查看日志", systemImage: "terminal")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if isSyncLogPresented {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(workshopViewModel.syncLog.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .id(idx)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: workshopViewModel.syncLog.count) { _ in
                            if let last = workshopViewModel.syncLog.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(6)
                .background(Color.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
    }

    var pageControls: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                workshopViewModel.loadPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(workshopViewModel.currentPage <= 1)

            Text("\(workshopViewModel.currentPage) / \(workshopViewModel.totalPages)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60)

            Button {
                workshopViewModel.loadNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(workshopViewModel.currentPage >= workshopViewModel.totalPages)
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    var steamSetupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("连接 Steam 以下载壁纸")
                    .font(.callout)
                    .bold()
                Text("设置 SteamCMD 后可直接从创意工坊下载壁纸到本地（需拥有 Wallpaper Engine）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                AppDelegate.shared.openSteamSetup()
            } label: {
                Text("立即设置")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}
