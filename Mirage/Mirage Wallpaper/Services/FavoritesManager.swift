//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import Foundation

final class FavoritesManager {
    static let shared = FavoritesManager()

    private let key = "FavoriteWallpapers"

    private var ids: Set<String>

    private init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    func isFavorite(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        persist()
    }

    func add(_ id: String) {
        ids.insert(id)
        persist()
    }

    func remove(_ id: String) {
        ids.remove(id)
        persist()
    }
}
