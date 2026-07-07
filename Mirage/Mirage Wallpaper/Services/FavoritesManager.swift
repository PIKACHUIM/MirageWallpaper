//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import Foundation

final class FavoritesManager {
    static let shared = FavoritesManager()

    private let key = "FavoriteWallpapers"

    private var ids: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: key)
        }
    }

    func isFavorite(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        var current = ids
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        ids = current
    }

    func add(_ id: String) {
        var current = ids
        current.insert(id)
        ids = current
    }

    func remove(_ id: String) {
        var current = ids
        current.remove(id)
        ids = current
    }
}
