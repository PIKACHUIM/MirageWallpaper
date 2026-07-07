//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import Foundation
import Darwin

final class SteamCMDManager: ObservableObject {
    static let shared = SteamCMDManager()

    @Published var steamCMDPath: URL?
    @Published var isLoggedIn = false

    private let fm = FileManager.default
    private var downloadProcesses: [String: Process] = [:]
    private let maxConcurrentDownloads = 2
    private var activeDownloadCount = 0

    private let steamCMDDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Mirage/steamcmd")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let usernameKey = "SteamCMDUsername"
    private let pathKey = "SteamCMDPath"
    private var hasRefreshedSession = false

    var savedUsername: String {
        get { UserDefaults.standard.string(forKey: usernameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }

    init() {
        if let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if fm.isExecutableFile(atPath: url.path) {
                steamCMDPath = url
            }
        }
    }

    func refreshSessionIfNeeded() {
        guard !hasRefreshedSession,
              steamCMDPath != nil,
              !savedUsername.isEmpty else { return }
        hasRefreshedSession = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let cmdPath = self.steamCMDPath else { return }

            let process = Process()
            process.executableURL = cmdPath
            process.arguments = ["+login", self.savedUsername, "+quit"]
            process.currentDirectoryURL = self.steamCMDDir

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    if output.contains("Logged in OK") || output.contains("Login Successful") ||
                       output.contains("Waiting for user info...OK") {
                        self.isLoggedIn = true
                        NSLog("[Mirage] Steam 会话刷新成功")
                    } else {
                        NSLog("[Mirage] Steam 会话已过期，需要重新登录")
                    }
                }
            } catch {
                NSLog("[Mirage] Steam 会话刷新失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Detect

    func detectSteamCMD() -> URL? {
        let candidates = [
            "/usr/local/bin/steamcmd",
            "/opt/homebrew/bin/steamcmd",
            steamCMDDir.appending(path: "steamcmd").path,
            NSHomeDirectory() + "/steamcmd/steamcmd.sh",
        ]

        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                let url = URL(fileURLWithPath: path)
                steamCMDPath = url
                UserDefaults.standard.set(path, forKey: pathKey)
                return url
            }
        }

        if let whichResult = try? runShellSync("/usr/bin/which", arguments: ["steamcmd"]),
           !whichResult.isEmpty {
            let path = whichResult.trimmingCharacters(in: .whitespacesAndNewlines)
            if fm.isExecutableFile(atPath: path) {
                let url = URL(fileURLWithPath: path)
                steamCMDPath = url
                UserDefaults.standard.set(path, forKey: pathKey)
                return url
            }
        }

        return nil
    }

    // MARK: - Install

    func installSteamCMD(onProgress: @escaping (SteamCMDInstallState) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async { onProgress(.downloading(0)) }

            let downloadURL = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!
            let tarPath = self.steamCMDDir.appending(path: "steamcmd_osx.tar.gz")

            do {
                let semaphore = DispatchSemaphore(value: 0)
                var downloadError: Error?

                let task = URLSession.shared.downloadTask(with: downloadURL) { tempURL, _, error in
                    defer { semaphore.signal() }
                    if let error {
                        downloadError = error
                        return
                    }
                    guard let tempURL else {
                        downloadError = SteamCMDError.downloadFailed("下载文件为空")
                        return
                    }
                    do {
                        if self.fm.fileExists(atPath: tarPath.path) {
                            try self.fm.removeItem(at: tarPath)
                        }
                        try self.fm.moveItem(at: tempURL, to: tarPath)
                    } catch {
                        downloadError = error
                    }
                }
                task.resume()

                DispatchQueue.main.async { onProgress(.downloading(0.5)) }
                semaphore.wait()

                if let error = downloadError {
                    DispatchQueue.main.async { onProgress(.failed(error.localizedDescription)) }
                    return
                }

                DispatchQueue.main.async { onProgress(.extracting) }

                let extractResult = try self.runShellSync("/usr/bin/tar", arguments: [
                    "-xzf", tarPath.path, "-C", self.steamCMDDir.path
                ])
                _ = extractResult

                try? self.fm.removeItem(at: tarPath)

                let execPath = self.steamCMDDir.appending(path: "steamcmd")
                guard self.fm.isExecutableFile(atPath: execPath.path) else {
                    DispatchQueue.main.async { onProgress(.failed("解压后未找到可执行文件")) }
                    return
                }

                DispatchQueue.main.async {
                    self.steamCMDPath = execPath
                    UserDefaults.standard.set(execPath.path, forKey: self.pathKey)
                    onProgress(.installed(execPath.path))
                }
            } catch {
                DispatchQueue.main.async { onProgress(.failed(error.localizedDescription)) }
            }
        }
    }

    // MARK: - PTY Runner (blocking read loop, no readabilityHandler to avoid close races)

    /// Runs steamcmd with the given arguments attached to a pseudo-terminal.
    /// `onLine` is invoked synchronously on the calling (background) thread for each output line.
    /// Returns (terminationStatus, fullOutput). Negative status indicates a setup/runtime error.
    private func runWithPTY(arguments: [String], onLine: (String) -> Void) -> (Int32, String) {
        guard let cmdPath = steamCMDPath else {
            return (-1, "")
        }

        var masterFD: Int32 = 0
        var slaveFD: Int32 = 0
        var ptyName = [CChar](repeating: 0, count: 128)

        guard openpty(&masterFD, &slaveFD, &ptyName, nil, nil) == 0 else {
            return (-2, "")
        }

        let process = Process()
        process.executableURL = cmdPath
        process.arguments = arguments
        process.currentDirectoryURL = steamCMDDir
        process.standardOutput = FileHandle(fileDescriptor: slaveFD)
        process.standardError = FileHandle(fileDescriptor: slaveFD)

        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: false)

        var outputBuffer = ""

        do {
            try process.run()
            // Parent closes its slave copy; only the child keeps it.
            close(slaveFD)

            // Blocking read loop: availableData blocks until data arrives or EOF (slave closed).
            while true {
                let data = masterHandle.availableData
                if data.isEmpty { break } // EOF
                guard let chunk = String(data: data, encoding: .utf8) else { continue }
                outputBuffer += chunk
                let lines = chunk.components(separatedBy: .newlines)
                for raw in lines {
                    let cleaned = raw.replacingOccurrences(of: "\r", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }
                    onLine(cleaned)
                }
            }

            process.waitUntilExit()
            close(masterFD)
            return (process.terminationStatus, outputBuffer)
        } catch {
            close(masterFD)
            // slaveFD may already be closed; ignore error.
            _ = Darwin.close(slaveFD)
            return (-3, "")
        }
    }

    // MARK: - Login

    func login(username: String, password: String, guardCode: String? = nil,
               onLog: @escaping (String) -> Void,
               onResult: @escaping (SteamLoginState) -> Void) {
        guard steamCMDPath != nil else {
            onResult(.failed("SteamCMD 未安装"))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async { onResult(.loggingIn) }

            var arguments = ["+login", username, password]
            if let code = guardCode, !code.isEmpty {
                arguments.append(code)
            }
            arguments.append("+quit")

            var mobileConfirmNotified = false

            let (status, output) = self.runWithPTY(arguments: arguments) { line in
                DispatchQueue.main.async { onLog(line) }
                if !mobileConfirmNotified &&
                   line.contains("Please confirm the login in the Steam Mobile app") {
                    mobileConfirmNotified = true
                    DispatchQueue.main.async {
                        onResult(.waitingForGuard(.mobileConfirm))
                    }
                }
            }

            DispatchQueue.main.async {
                if status < 0 {
                    onResult(.failed(status == -2 ? "无法创建伪终端" : "SteamCMD 运行失败"))
                    return
                }
                if output.contains("Logged in OK") || output.contains("Login Successful") ||
                   output.contains("Waiting for user info...OK") {
                    self.isLoggedIn = true
                    self.savedUsername = username
                    onResult(.success)
                } else if output.contains("Steam Guard") || output.contains("Two-factor") ||
                          output.contains("two factor") || output.contains("Two Factor") {
                    if output.contains("email") || output.contains("mail") {
                        onResult(.waitingForGuard(.email))
                    } else {
                        onResult(.waitingForGuard(.mobile))
                    }
                } else if output.contains("FAILED") || output.contains("Invalid Password") ||
                          output.contains("Login Failure") {
                    onResult(.failed("登录失败，请检查用户名和密码"))
                } else {
                    onResult(.failed("未知响应: \(output.prefix(200))"))
                }
            }
        }
    }

    // MARK: - Download Workshop Item

    func downloadItem(workshopId: String, expectedFileSize: Int64 = 0, onProgress: @escaping (DownloadState) -> Void) {
        guard steamCMDPath != nil else {
            onProgress(.failed("SteamCMD 未安装"))
            return
        }

        let username = savedUsername
        guard !username.isEmpty else {
            onProgress(.failed("未登录 Steam"))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async { onProgress(.starting) }

            let arguments = [
                "+login", username,
                "+workshop_download_item", "431960", workshopId,
                "+quit"
            ]

            var masterFD: Int32 = 0
            var slaveFD: Int32 = 0
            var ptyName = [CChar](repeating: 0, count: 128)
            guard openpty(&masterFD, &slaveFD, &ptyName, nil, nil) == 0 else {
                DispatchQueue.main.async { onProgress(.failed("无法创建伪终端")) }
                return
            }

            let process = Process()
            process.executableURL = self.steamCMDPath
            process.arguments = arguments
            process.currentDirectoryURL = self.steamCMDDir
            process.standardOutput = FileHandle(fileDescriptor: slaveFD)
            process.standardError = FileHandle(fileDescriptor: slaveFD)
            let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: false)
            self.downloadProcesses[workshopId] = process

            // Poll download directory size for real progress (SteamCMD workshop downloads
            // don't emit parseable percentage lines).
            let downloadDir = self.steamCMDDir
                .appending(path: "steamapps/workshop/content/431960/\(workshopId)")
            var polling = true
            let pollQueue = DispatchQueue.global(qos: .utility)
            pollQueue.async {
                var lastReported: Double = 0
                while polling {
                    Thread.sleep(forTimeInterval: 0.5)
                    guard polling else { break }
                    if expectedFileSize > 0,
                       let size = try? downloadDir.directoryTotalAllocatedSize(includingSubfolders: true),
                       size > 0 {
                        var pct = Double(size) / Double(expectedFileSize)
                        pct = min(pct, 0.99)
                        if pct > lastReported {
                            lastReported = pct
                            DispatchQueue.main.async { onProgress(.downloading(percent: pct)) }
                        }
                    }
                }
            }

            do {
                try process.run()
                close(slaveFD)

                while true {
                    let data = masterHandle.availableData
                    if data.isEmpty { break }
                    guard let chunk = String(data: data, encoding: .utf8) else { continue }
                    let lines = chunk.components(separatedBy: .newlines)
                    for raw in lines {
                        let trimmed = raw.replacingOccurrences(of: "\r", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { continue }

                        if trimmed.contains("Downloading item") {
                            DispatchQueue.main.async { onProgress(.downloading(percent: 0.02)) }
                        }
                        if trimmed.contains("Download item") && trimmed.contains("OK") {
                            DispatchQueue.main.async { onProgress(.downloading(percent: 0.97)) }
                        }
                        if trimmed.contains("Success") {
                            DispatchQueue.main.async { onProgress(.validating) }
                        }
                    }
                }

                process.waitUntilExit()
                polling = false
                close(masterFD)
                self.downloadProcesses.removeValue(forKey: workshopId)

                if process.terminationStatus == 0 {
                    self.moveDownloadedItem(workshopId: workshopId)
                    DispatchQueue.main.async { onProgress(.completed) }
                } else {
                    DispatchQueue.main.async {
                        onProgress(.failed("下载失败 (exit \(process.terminationStatus))"))
                    }
                }
            } catch {
                polling = false
                close(masterFD)
                _ = Darwin.close(slaveFD)
                self.downloadProcesses.removeValue(forKey: workshopId)
                DispatchQueue.main.async { onProgress(.failed(error.localizedDescription)) }
            }
        }
    }

    func cancelDownload(workshopId: String) {
        if let process = downloadProcesses[workshopId], process.isRunning {
            process.terminate()
        }
        downloadProcesses.removeValue(forKey: workshopId)
    }

    // MARK: - Sync Subscribed Wallpapers

    func syncSubscribedWallpapers(onLog: @escaping (String) -> Void, onProgress: @escaping (SyncState) -> Void) {
        guard steamCMDPath != nil else {
            onProgress(.failed("SteamCMD 未安装"))
            return
        }

        let username = savedUsername
        guard !username.isEmpty else {
            onProgress(.failed("未登录 Steam"))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async { onProgress(.syncing) }

            let arguments = [
                "+login", username,
                "+@sSteamCmdForcePlatformType", "windows",
                "+app_update", "431960", "validate",
                "+quit"
            ]

            let (status, output) = self.runWithPTY(arguments: arguments) { line in
                DispatchQueue.main.async { onLog(line) }
            }

            DispatchQueue.main.async {
                if status < 0 {
                    onProgress(.failed(status == -2 ? "无法创建伪终端" : "SteamCMD 运行失败"))
                    return
                }
                if status == 0 || output.contains("Success") ||
                   output.contains("fully installed") || output.contains("already up to date") {
                    self.moveAllSyncedItems()
                    onProgress(.completed)
                } else {
                    onProgress(.failed("同步失败 (exit \(status))"))
                }
            }
        }
    }

    private func moveAllSyncedItems() {
        let syncedDir = steamCMDDir.appending(path: "steamapps/workshop/content/431960")
        guard let contents = try? fm.contentsOfDirectory(at: syncedDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { return }

        for itemDir in contents {
            let isDir = (try? itemDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let workshopId = itemDir.lastPathComponent
            moveDownloadedItem(workshopId: workshopId)
        }
    }

    // MARK: - Move Downloaded Item

    private func moveDownloadedItem(workshopId: String) {
        let steamCMDContent = steamCMDDir
            .appending(path: "steamapps/workshop/content/431960/\(workshopId)")
        let targetDir = WallpaperLibrary.shared.steamWorkshopDirectory
            .appending(path: workshopId)

        guard fm.fileExists(atPath: steamCMDContent.path) else { return }

        if fm.fileExists(atPath: targetDir.path) { return }

        do {
            try fm.createDirectory(at: targetDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: steamCMDContent, to: targetDir)
        } catch {
            NSLog("[Mirage] 移动下载文件失败: \(error.localizedDescription)")

            do {
                try fm.createSymbolicLink(at: targetDir, withDestinationURL: steamCMDContent)
            } catch {
                NSLog("[Mirage] 创建符号链接也失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Shell Helper

    var steamCMDContentDirectory: URL {
        steamCMDDir.appending(path: "steamapps/workshop/content/431960")
    }

    private func runShellSync(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum SteamCMDError: LocalizedError {
    case downloadFailed(String)
    case installFailed(String)
    case loginRequired
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return "下载失败: \(msg)"
        case .installFailed(let msg): return "安装失败: \(msg)"
        case .loginRequired: return "需要登录 Steam"
        case .notInstalled: return "SteamCMD 未安装"
        }
    }
}
