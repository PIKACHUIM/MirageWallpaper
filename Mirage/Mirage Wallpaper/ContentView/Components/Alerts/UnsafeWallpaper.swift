//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct UnsafeWallpaper: View {
    @Environment(\.dismiss) var dismiss
    
    var wallpaper: WEWallpaper
    
    @State var seconds: Int = 5
    @State var isIgnored = false
    
    var typeStringDict: [String : String] =
    [
        "web": "网页",
        "application": "应用程序"
    ]

    init(wallpaper: WEWallpaper) {
        self.wallpaper = wallpaper
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("正在打开\(typeStringDict[wallpaper.project.type.lowercased()] ?? "未知")类壁纸")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .font(.title2)
            Divider()
            HStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 6)
                    .frame(maxWidth: 100)
                VStack(alignment: .leading, spacing: 10) {
                    Text("你即将把以下\(typeStringDict[wallpaper.project.type.lowercased()] ?? "未知来源")类文件作为壁纸运行：")
                    Text(wallpaper.resolvedEntryURL.path(percentEncoded: false)).bold()
                    Text("Mirage 无法控制该文件的行为，网页壁纸可能包含可执行脚本。请确认它来自可信来源后再继续。")
                    Text(seconds > 0 ? "请等待 \(seconds) 秒。" : "请注意潜在的恶意代码风险。")
                    Toggle("对此壁纸不再提示", isOn: $isIgnored)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal)
            Divider()
            HStack {
                Button {
                    AppDelegate.shared.wallpaperViewModel.currentWallpaper =
                    AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper
                    
                    if isIgnored {
                        var trustedWallpapers =
                        UserDefaults.standard.array(forKey: "TrustedWallpapers") as? [String] ?? [String]()
                        
                        trustedWallpapers.append(AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper.wallpaperDirectory.path(percentEncoded: false))
                        
                        UserDefaults.standard.set(trustedWallpapers, forKey: "TrustedWallpapers")
                    }
                    
                    dismiss()
                } label: {
                    Text("继续")
                        .padding(.horizontal, 10)
                }
                .animation(.default, value: seconds)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(seconds > 0 ? true : false)
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .padding(.horizontal, 10)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear {
            let _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if self.seconds <= 0 {
                    timer.invalidate()
                } else {
                    self.seconds -= 1
                }
            }
        }
    }
}
