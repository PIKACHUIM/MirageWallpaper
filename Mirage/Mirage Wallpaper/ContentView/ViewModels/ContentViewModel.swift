//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ScreenSaverFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

class ContentViewModel: ObservableObject, DropDelegate {
    @AppStorage("SortingBy") var sortingBy: WEWallpaperSortingMethod = .name {
        didSet {
            currentPage = 1
            if sortingBy == .fileSize { prewarmWallpaperSizes() }
        }
    }
    @AppStorage("SortingSequence") var sortingSequence: WEWallpaperSortingSequence = .increase {
        didSet { currentPage = 1 }
    }

    @AppStorage("FRShowOnly") public var showOnly = FRShowOnly.all { didSet { currentPage = 1 } }
    @AppStorage("FRType") public var type = FRType.all { didSet { currentPage = 1 } }
    @AppStorage("FRAgeRating") public var ageRating = FRAgeRating.all { didSet { currentPage = 1 } }
    @AppStorage("FRWidescreenResolution") public var widescreenResolution = FRWidescreenResolution.all { didSet { currentPage = 1 } }
    @AppStorage("FRUltraWidescreenResolution") public var ultraWidescreenResolution = FRUltraWidescreenResolution.all { didSet { currentPage = 1 } }
    @AppStorage("FRDualscreenResolution") public var dualscreenResolution = FRDualscreenResolution.all { didSet { currentPage = 1 } }
    @AppStorage("FRTriplescreenResolution") public var triplescreenResolution = FRTriplescreenResolution.all { didSet { currentPage = 1 } }
    @AppStorage("FRPortraitScreenResolution") public var potraitscreenResolution = FRPortraitScreenResolution.all { didSet { currentPage = 1 } }
    @AppStorage("FRMiscResolution") public var miscResolution = FRMiscResolution.all { didSet { currentPage = 1 } }
    @AppStorage("FRSource") public var source = FRSource.all { didSet { currentPage = 1 } }
    @AppStorage("FRTag") public var tag = FRTag.all { didSet { currentPage = 1 } }
    
    @AppStorage("FilterReveal") var isFilterReveal = false
    @AppStorage("ExplorerIconSize") var explorerIconSize: Double = 200
    
    @Published var isDisplaySettingsReveal = false
    @Published var importAlertPresented = false
    @Published var isStaging = false
    
    @Published var topTabBarSelection: Int = 0
    @Published var topTabBarHoverSelection: Int = -1
    
    @Published var imageScaleIndex: Int = -1
    
    @Published var wallpapers = [WEWallpaper]()
    
    @Published var isUnsafeWallpaperWarningPresented = false
    
    @Published var hoveredWallpaper: WEWallpaper?
    
    @Published var isUnsubscribeConfirming = false

    @Published var screenSaverFeedback: ScreenSaverFeedback?

    @Published var searchText = "" { didSet { currentPage = 1 } }

    @Published var isSteamSetupPresented = false
    
    @AppStorage("WallpapersPerPage") var wallpapersPerPage: Int = 50 {
        didSet { currentPage = 1 }
    }
    
    var importAlertError: WPImportError? = nil

    private var downloadObserver: AnyCancellable?
    private var favoritesObserver: AnyCancellable?
    private var refreshWorkItem: DispatchWorkItem?
    private var refreshInFlight = false
    private var refreshAgain = false

    convenience init(isStaging: Bool, topTabBarSelection: Int = 0) {
        self.init()
        self.isStaging = isStaging
        self.topTabBarSelection = topTabBarSelection
        refresh()
    }

    init() {
        downloadObserver = NotificationCenter.default.publisher(for: .workshopItemDownloaded)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }

        favoritesObserver = NotificationCenter.default.publisher(for: .favoritesChanged)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            WallpaperLibrary.shared.startMonitoringWorkshopDirectory { [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    @Published public var currentPage: Int = 1

    private var allWallpapers: [WEWallpaper] { wallpapers }

    func importWallpapers(urls: [URL]) {
        self.isStaging = true
        DispatchQueue.global(qos: .userInitiated).async {
            var lastError: WPImportError?
            for url in urls {
                do { try WallpaperLibrary.shared.importAny(at: url) }
                catch let e as WPImportError { lastError = e }
                catch { lastError = .unknown }
            }
            DispatchQueue.main.async {
                WEWallpaper.invalidateSizeCache()
                if let e = lastError { self.alertImportModal(which: e) }
                self.refresh()
            }
        }
    }
    
    private var searchedWallpapers: [WEWallpaper] {
        let query = searchText.lowercased()
        return allWallpapers.filter { wallpaper in
            let project = wallpaper.project
            
            guard !query.isEmpty else { return true }
            
            guard !project.title.lowercased().contains(query) else { return true }
            
            guard !project.type.lowercased().contains(query) else { return true }
            
            if let description = project.description?.lowercased() {
                guard !description.contains(query) else { return true }
            }
            
            if let tags = project.tags {
                if tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                    return true
                }
            }
            
            if let workshopid = project.workshopid {
                guard !workshopid.rawValue.contains(query) else { return true }
            }
            
            guard !wallpaper.wallpaperDirectory.lastPathComponent
                .lowercased()
                .contains(query) else { return true }
            
            return false
        }
    }
    
    private var filteredWallpapers: [WEWallpaper] {
        searchedWallpapers.filter { wallpaper in
            // 仅显示：未选或全选时不筛选；否则按 AND 逻辑要求每项命中
            let activeShowOnly = self.showOnly
            if !activeShowOnly.isEmpty && activeShowOnly != FRShowOnly.all {
                if activeShowOnly.contains(.approved) {
                    guard wallpaper.project.approved == true else { return false }
                }
                if activeShowOnly.contains(.myFavourites) {
                    guard FavoritesManager.shared.isFavorite(wallpaper.id) else { return false }
                }
                if activeShowOnly.contains(.customizable) {
                    guard let props = wallpaper.project.general?.properties,
                          !props.items.isEmpty else { return false }
                }
                if activeShowOnly.contains(.mobileCompatible) {
                    let tags = (wallpaper.project.tags ?? []).map { $0.lowercased() }
                    guard tags.contains(where: { $0.contains("mobile") }) else { return false }
                }
                if activeShowOnly.contains(.audioResponsive) {
                    let tags = (wallpaper.project.tags ?? []).map { $0.lowercased() }
                    guard tags.contains(where: { $0.contains("audio") }) else { return false }
                }
            }
            
            var type = FRType.none
            if wallpaper.isPreset {
                type = .preset
            } else {
                switch wallpaper.project.type.lowercased() {
                case "video":
                    type = .video
                case "scene":
                    type = .scene
                case "web":
                    type = .web
                case "application":
                    type = .application
                default:
                    break
                }
            }
            let selectedTypes = self.type == .legacyAll ? FRType.all : self.type
            guard selectedTypes.contains(type) else { return false }
            
            var ageRating: FRAgeRating
            switch wallpaper.project.contentrating {
            case "Everyone":
                ageRating = .everyone
            case "Questionable":
                ageRating = .partialNudity
            case "Mature":
                ageRating = .mature
            default:
                ageRating = .none
            }
            guard self.ageRating.contains(ageRating) else { return false }
            
            var source = FRSource.none
            if WallpaperLibrary.shared.isImported(wallpaper) {
                source = .myWallpapers
            } else {
                source = .workshop
            }
            guard self.source.contains(source) else { return false }

            if self.tag != FRTag.all {
                let wallpaperTags = FRTag.bits(from: wallpaper.project.tags ?? [])
                if wallpaperTags.isEmpty {
                    guard self.tag.contains(.unspecifiedGenre) else { return false }
                } else {
                    guard !self.tag.intersection(wallpaperTags).isEmpty else { return false }
                }
            }

            return true
        }
    }
    
    private var sortedWallpapers: [WEWallpaper] {
        filteredWallpapers.sorted {
            let comparison: ComparisonResult
            switch sortingBy {
            case .name:
                comparison = $0.project.title.localizedStandardCompare($1.project.title)
            case .rating:
                comparison = ($0.project.contentrating ?? "0")
                    .localizedStandardCompare($1.project.contentrating ?? "0")
            case .fileSize:
                if $0.wallpaperSize == $1.wallpaperSize {
                    comparison = $0.project.title.localizedStandardCompare($1.project.title)
                } else {
                    comparison = $0.wallpaperSize < $1.wallpaperSize ? .orderedAscending : .orderedDescending
                }
            }
            return sortingSequence == .increase
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    struct WallpaperPage {
        let items: [WEWallpaper]
        let pageCount: Int
    }

    var wallpaperPage: WallpaperPage {
        let all = sortedWallpapers
        guard wallpapersPerPage > 0 else {
            return WallpaperPage(items: all, pageCount: 1)
        }
        let pageCount = max(1, Int(ceil(Double(all.count) / Double(wallpapersPerPage))))
        let page = min(max(currentPage, 1), pageCount)
        let startIndex = (page - 1) * wallpapersPerPage
        guard startIndex < all.count else {
            return WallpaperPage(items: [], pageCount: pageCount)
        }
        let endIndex = min(startIndex + wallpapersPerPage, all.count)
        return WallpaperPage(items: Array(all[startIndex..<endIndex]), pageCount: pageCount)
    }

    public var autoRefreshWallpapers: [WEWallpaper] {
        wallpaperPage.items
    }

    var maxPage: Int {
        wallpaperPage.pageCount
    }
    
    func toggleFilter() {
        isFilterReveal.toggle()
    }
    
    func alertImportModal(which error: WPImportError) {
        self.importAlertError = error
        self.importAlertPresented = true
    }
    
    func warningUnsafeWallpaperModal(which wallpaper: WEWallpaper) {
        self.isUnsafeWallpaperWarningPresented = true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let proposal = DropProposal(operation: .copy)
        return proposal
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else {
            alertImportModal(which: .unknown)
            return false
        }
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.importWallpapers(urls: urls)
        }
        return true
    }
    
    public func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        if refreshInFlight {
            refreshAgain = true
            return
        }
        refreshInFlight = true
        let shouldPrewarmSizes = sortingBy == .fileSize
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = WallpaperLibrary.shared.loadAll()
            if shouldPrewarmSizes {
                loaded.forEach { _ = $0.wallpaperSize }
            }
            DispatchQueue.main.async {
                self.wallpapers = loaded
                self.refreshInFlight = false
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    private func scheduleRefresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            self.refreshWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    private func prewarmWallpaperSizes() {
        let snapshot = wallpapers
        DispatchQueue.global(qos: .utility).async {
            snapshot.forEach { _ = $0.wallpaperSize }
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
    }
    
    public func reset() {
        self.showOnly = .none
        self.type = .all
        self.ageRating = .all
        self.widescreenResolution = .all
        self.ultraWidescreenResolution = .all
        self.dualscreenResolution = .all
        self.triplescreenResolution = .all
        self.potraitscreenResolution = .all
        self.miscResolution = .all
        self.source = .all
        self.tag = .all
    }
}

extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
