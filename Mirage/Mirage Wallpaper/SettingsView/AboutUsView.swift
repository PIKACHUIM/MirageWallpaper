//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

extension AppDelegate {
    @objc func showAboutUs() {
        let window = NSWindow()
        window.styleMask = [.closable, .titled]
        window.isReleasedWhenClosed = false
        window.title = ""
        window.contentView = NSHostingView(rootView: AboutUsView())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

struct AboutUsView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 88, height: 88)
                }
                Divider().frame(maxHeight: 90)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mirage").bold().font(.largeTitle)
                    Text("macOS 动态壁纸引擎").font(.footnote).foregroundStyle(.secondary)
                    Text("场景 · 网页 · 视频").font(.caption).foregroundStyle(.tertiary)
                }
            }
            VStack(spacing: 14) {
                Text("版本 \(version)").foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("作者")
                    Text("王孝慈 (laobamac)").bold()
                }
                Link("github.com/laobamac/MirageWallpaper",
                     destination: URL(string: "https://github.com/laobamac/MirageWallpaper")!)
                    .font(.footnote)
            }
            .font(.callout)
            ProjectFeedbackBanner(showsActions: false)
                .padding(.horizontal, 20)
        }
        .textSelection(.enabled)
        .frame(width: 460, height: 390)
    }
}

struct AboutUsView_Previews: PreviewProvider {
    static var previews: some View {
        AboutUsView()
    }
}
