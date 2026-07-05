//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct ExplorerGlobalMenu: SubviewOfContentView {
    
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    
    init(contentViewModel viewModel: ContentViewModel, wallpaperViewModel: WallpaperViewModel) {
        self.wallpaperViewModel = wallpaperViewModel
        self.viewModel = viewModel
    }
    
    var body: some View {
        Section {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path(percentEncoded: false))
            } label: {
                Label("在访达中打开全部", systemImage: "folder.badge.gearshape")
            }
            Menu("视图") {
                Section {
                    Picker("Icon Size", selection: $viewModel.explorerIconSize) {
                        Text("小图标").tag(Double(100))
                        Text("中图标").tag(Double(125))
                        Text("大图标").tag(Double(150))
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Picker("Titles per page", selection: $viewModel.wallpapersPerPage) {
                        Text("10 per page").tag(10)
                        Text("25 per page").tag(25)
                        Text("50 per page").tag(50)
                        Text("1 per page (developer)").tag(1)
                        Text("1 per page (developer)").tag(2)
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }
}
