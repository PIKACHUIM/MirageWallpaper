//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct WallpaperDiscover: View {
    var body: some View {
        ScrollView {
            WorkingInProgress()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 50)
        }
    }
}

struct WallpaperDiscover_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: .init(isStaging: true, topTabBarSelection: 1), wallpaperViewModel: .init())
            .environmentObject(GlobalSettingsViewModel())
    }
}
