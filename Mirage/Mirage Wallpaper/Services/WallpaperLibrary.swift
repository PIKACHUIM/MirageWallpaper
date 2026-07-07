//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import AppKit
import AVFoundation
import Foundation

enum WPImportError: LocalizedError, Identifiable {
    case permissionDenied
    case doesNotContainWallpaper
    case unsupportedType
    case copyFailed(String)
    case unknown

    var id: String { errorDescription ?? "unknown" }

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "没有访问权限"
        case .doesNotContainWallpaper: return "文件夹内没有壁纸"
        case .unsupportedType: return "不支持的壁纸类型"
        case .copyFailed(let m): return "复制失败：\(m)"
        case .unknown: return "未知错误"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied: return "请在“系统设置 - 隐私与安全性”中授予访问权限后重试。"
        case .doesNotContainWallpaper: return "所选文件夹需包含 project.json，请确认后重试。"
        case .unsupportedType: return "Mirage 仅支持 场景 / 网页 / 视频 类壁纸。"
        case .copyFailed: return "请检查磁盘空间与权限后重试。"
        case .unknown: return nil
        }
    }
}

final class WallpaperLibrary {
    static let shared = WallpaperLibrary()

    private let fm = FileManager.default

    private let workshopKey = "CustomWorkshopDirectory"
    private let importedKey = "CustomImportedDirectory"

    private var workshopMonitorSource: DispatchSourceFileSystemObject?
    private var workshopMonitorFD: Int32 = -1

    var defaultSteamWorkshopDirectory: URL {
        fm.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Steam/steamapps/workshop/content/431960")
    }

    var defaultImportedDirectory: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Mirage/Wallpapers")
    }

    var steamWorkshopDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: workshopKey), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return defaultSteamWorkshopDirectory
    }

    var importedDirectory: URL {
        let base: URL
        if let path = UserDefaults.standard.string(forKey: importedKey), !path.isEmpty {
            base = URL(fileURLWithPath: path)
        } else {
            base = defaultImportedDirectory
        }
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    var isWorkshopDirectoryCustomized: Bool {
        !(UserDefaults.standard.string(forKey: workshopKey) ?? "").isEmpty
    }
    var isImportedDirectoryCustomized: Bool {
        !(UserDefaults.standard.string(forKey: importedKey) ?? "").isEmpty
    }

    func setWorkshopDirectory(_ url: URL?) {
        UserDefaults.standard.set(url?.path, forKey: workshopKey)
    }
    func setImportedDirectory(_ url: URL?) {
        UserDefaults.standard.set(url?.path, forKey: importedKey)
    }

    private var sourceDirectories: [URL] {
        var dirs = [steamWorkshopDirectory, importedDirectory]
        if SteamCMDManager.shared.steamCMDPath != nil {
            let steamCMDContent = SteamCMDManager.shared.steamCMDContentDirectory
            if fm.fileExists(atPath: steamCMDContent.path) {
                dirs.append(steamCMDContent)
            }
        }
        return dirs
    }

    func allWallpaperURLs() -> [URL] {
        var result: [URL] = []
        for dir in sourceDirectories {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in contents {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                if fm.fileExists(atPath: url.appending(path: "project.json").path) {
                    result.append(url)
                }
            }
        }
        return result
    }

    func loadAll() -> [WEWallpaper] {
        allWallpaperURLs().map { WEWallpaper.load(from: $0) }
    }

    // MARK: - 导入

    @discardableResult
    func importWallpaperFolder(at url: URL) throws -> URL {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw WPImportError.doesNotContainWallpaper
        }
        guard fm.fileExists(atPath: url.appending(path: "project.json").path) else {
            throw WPImportError.doesNotContainWallpaper
        }
        let dest = uniqueDestination(for: url.lastPathComponent)
        do {
            try fm.copyItem(at: url, to: dest)
        } catch {
            throw WPImportError.copyFailed(error.localizedDescription)
        }
        return dest
    }

    @discardableResult
    func importVideoFile(at url: URL) throws -> URL {
        let ext = url.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(ext) else {
            throw WPImportError.unsupportedType
        }
        let baseName = url.deletingPathExtension().lastPathComponent
        let dest = uniqueDestination(for: baseName)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            let fileName = url.lastPathComponent
            try fm.copyItem(at: url, to: dest.appending(path: fileName))

            let previewName = "preview.jpg"
            if let jpeg = try? Self.generateThumbnail(for: url) {
                try? jpeg.write(to: dest.appending(path: previewName), options: .atomic)
            }

            let project = WEProject(file: fileName,
                                    preview: previewName,
                                    title: baseName,
                                    type: "video")
            let data = try JSONEncoder().encode(project)
            try data.write(to: dest.appending(path: "project.json"), options: .atomic)
        } catch let e as WPImportError {
            throw e
        } catch {
            throw WPImportError.copyFailed(error.localizedDescription)
        }
        return dest
    }

    @discardableResult
    func importAny(at url: URL) throws -> URL {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            return try importWallpaperFolder(at: url)
        } else {
            return try importVideoFile(at: url)
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        var dest = importedDirectory.appending(path: name)
        var counter = 1
        while fm.fileExists(atPath: dest.path) {
            dest = importedDirectory.appending(path: "\(name)_\(counter)")
            counter += 1
        }
        return dest
    }

    static func generateThumbnail(for videoURL: URL) throws -> Data? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTimeMake(value: 1, timescale: 1)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    func trash(_ wallpaper: WEWallpaper) throws {
        try fm.trashItem(at: wallpaper.wallpaperDirectory, resultingItemURL: nil)
    }

    func delete(_ wallpaper: WEWallpaper) throws {
        try fm.removeItem(at: wallpaper.wallpaperDirectory)
    }

    func isImported(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.wallpaperDirectory.path.hasPrefix(importedDirectory.path)
    }

    // MARK: - Directory Monitoring

    func startMonitoringWorkshopDirectory(onChange: @escaping () -> Void) {
        stopMonitoringWorkshopDirectory()

        let dirPath = steamWorkshopDirectory.path
        guard fm.fileExists(atPath: dirPath) else { return }

        workshopMonitorFD = open(dirPath, O_EVTONLY)
        guard workshopMonitorFD >= 0 else { return }

        workshopMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: workshopMonitorFD,
            eventMask: .write,
            queue: .main
        )

        workshopMonitorSource?.setEventHandler {
            onChange()
        }

        workshopMonitorSource?.setCancelHandler { [weak self] in
            if let fd = self?.workshopMonitorFD, fd >= 0 {
                close(fd)
                self?.workshopMonitorFD = -1
            }
        }

        workshopMonitorSource?.resume()
    }

    func stopMonitoringWorkshopDirectory() {
        workshopMonitorSource?.cancel()
        workshopMonitorSource = nil
    }
}
