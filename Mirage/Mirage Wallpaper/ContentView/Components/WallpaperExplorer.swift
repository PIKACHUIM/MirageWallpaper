//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct WallpaperExplorer: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    
    init(contentViewModel viewModel: ContentViewModel, wallpaperViewModel: WallpaperViewModel) {
        self.viewModel = viewModel
        self.wallpaperViewModel = wallpaperViewModel
    }
    
    var body: some View {
        let page = viewModel.wallpaperPage
        ScrollView {
            if page.items.isEmpty {
                HStack {
                    Spacer()
                    Text("""
                        没有找到匹配的壁纸。
                        请调整或重置左侧筛选条件，或更换搜索关键词。
                        也可以点击底部“导入壁纸”添加新壁纸。
                        """)
                    .font(.title)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .lineSpacing(10)
                    Spacer()
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 50)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: viewModel.explorerIconSize, 
                                                       maximum: viewModel.explorerIconSize * 2)
                )], alignment: .leading) {
                    ForEach(Array(page.items.enumerated()), id: \.element.id) { (index, wallpaper) in
                        ExplorerItem(viewModel: viewModel, wallpaperViewModel: wallpaperViewModel, wallpaper: wallpaper, index: index)
                            .contextMenu {
                                ExplorerItemMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel, current: wallpaper)
                                ExplorerGlobalMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                            }
                            .animation(.spring(), value: viewModel.imageScaleIndex)
                    }
                }
                .padding(.trailing)
            }
        }
        .overlay {
            VStack {
                Spacer()
                HStack {
                    ForEach(0..<page.pageCount, id: \.self) { pageIndex in
                        Button("\(pageIndex + 1)") {
                            viewModel.currentPage = pageIndex + 1
                        }
                    }
                }
                .padding(.bottom)
            }
        }
    }
}

struct SelectedItem: ViewModifier {
    var selected: Bool
    
    init(_ selected: Bool) {
        self.selected = selected
    }
    
    func body(content: Content) -> some View {
        content
            .border(Color.accentColor, width: selected ? 3 : 0)
    }
}

extension View {
    func selected(_ selected: Bool = true) -> some View {
        modifier(SelectedItem(selected))
    }
}
