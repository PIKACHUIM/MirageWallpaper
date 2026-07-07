//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct DiscoverView: View {
    @ObservedObject var workshopViewModel: WorkshopViewModel
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        ScrollView {
            if workshopViewModel.isDiscoverLoading && workshopViewModel.bannerItems.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在加载推荐内容...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                VStack(spacing: 24) {
                    if !workshopViewModel.trendingItems.isEmpty {
                        DiscoverSectionView(
                            title: "本周最热",
                            icon: "flame.fill",
                            iconColor: .orange,
                            items: workshopViewModel.trendingItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithSort(.trending)
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    if !workshopViewModel.mostRecentItems.isEmpty {
                        DiscoverSectionView(
                            title: "最新上架",
                            icon: "clock.fill",
                            iconColor: .blue,
                            items: workshopViewModel.mostRecentItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithSort(.mostRecent)
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    if !workshopViewModel.mostSubscribedItems.isEmpty {
                        DiscoverSectionView(
                            title: "订阅最多",
                            icon: "arrow.down.circle.fill",
                            iconColor: .green,
                            items: workshopViewModel.mostSubscribedItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithSort(.mostSubscribed)
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    if !workshopViewModel.topRatedItems.isEmpty {
                        DiscoverSectionView(
                            title: "评分最高",
                            icon: "star.fill",
                            iconColor: .yellow,
                            items: workshopViewModel.topRatedItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithSort(.topRated)
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    if !workshopViewModel.animeItems.isEmpty {
                        DiscoverSectionView(
                            title: "动漫精选",
                            icon: "sparkles",
                            iconColor: .purple,
                            items: workshopViewModel.animeItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithTag("Anime")
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    if !workshopViewModel.natureItems.isEmpty {
                        DiscoverSectionView(
                            title: "自然风光",
                            icon: "leaf.fill",
                            iconColor: .green,
                            items: workshopViewModel.natureItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithTag("Nature")
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    if !workshopViewModel.abstractItems.isEmpty {
                        DiscoverSectionView(
                            title: "抽象艺术",
                            icon: "circle.hexagongrid.fill",
                            iconColor: .cyan,
                            items: workshopViewModel.abstractItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithTag("Abstract")
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    if !workshopViewModel.landscapeItems.isEmpty {
                        DiscoverSectionView(
                            title: "风景壁纸",
                            icon: "mountain.2.fill",
                            iconColor: .teal,
                            items: workshopViewModel.landscapeItems,
                            workshopViewModel: workshopViewModel,
                            contentViewModel: viewModel,
                            onSeeAll: {
                                workshopViewModel.navigateToWorkshopWithTag("Landscape")
                                viewModel.topTabBarSelection = 2
                            }
                        )
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            if workshopViewModel.bannerItems.isEmpty {
                workshopViewModel.loadDiscover()
            }
        }
    }
}
