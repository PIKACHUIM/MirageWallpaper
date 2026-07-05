//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct ExplorerBottomBar: View {
    var body: some View {
        VStack {
            HStack {
                Text("播放列表")
                    .font(.largeTitle)
                HStack(spacing: 2) {
                    Button { } label: {
                        Label("载入", systemImage: "folder.fill")
                    }
                    Button { } label: {
                        Label("保存", systemImage: "square.and.arrow.down.fill")
                    }
                    Button { } label: {
                        Label("配置", systemImage: "gearshape.2.fill")
                    }
                    Button { } label: {
                        Label("添加壁纸", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .disabled(true)
            HStack {
                Button {
                    AppDelegate.shared.openImportFromFolderPanel()
                } label: {
                    Label("导入壁纸", systemImage: "arrow.up.bin.fill")
                        .frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
    }
}
