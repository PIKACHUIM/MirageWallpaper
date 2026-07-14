//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct ExplorerItem: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel

    private let animates = true

    var wallpaper: WEWallpaper
    var index: Int
    
    var body: some View {
        ZStack(alignment: .bottom) {
            GifImage(contentsOf: wallpaper.project.preview.isEmpty
                ? Bundle.main.url(forResource: "WallpaperNotFound", withExtension: "mp4")!
                : wallpaper.previewURL, animates: animates)
            .resizable()
            .scaleEffect(viewModel.imageScaleIndex == index ? 1.2 : 1.0)
            .aspectRatio(1.0, contentMode: .fit)
            .clipped()
            
            Text(wallpaper.project.title)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(4)
                .background(Color(white: 0, opacity: viewModel.imageScaleIndex == index ? 0.4 : 0.2))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(white: viewModel.imageScaleIndex == index ? 0.9 : 0.7))
        }
        .selected(wallpaper.wallpaperDirectory == wallpaperViewModel.currentWallpaper.wallpaperDirectory)
        .border(Color.accentColor, width: viewModel.imageScaleIndex == index ? 1.0 : 0)
        .overlay(alignment: .topLeading) {
            if wallpaper.isPreset {
                VStack(alignment: .leading, spacing: 3) {
                    Label("预设", systemImage: "slider.horizontal.3")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.purple, in: RoundedRectangle(cornerRadius: 4))
                    if let status = wallpaper.presetStatusDescription {
                        Label(status, systemImage: "exclamationmark.triangle.fill")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(6)
            }
        }
        .onTapGesture {
            AppDelegate.shared.workshopViewModel.openInstalledWallpaper(wallpaper)
        }
    }
}
