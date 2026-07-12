//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import AppKit
import Foundation

enum FillMode: String, CaseIterable, Codable, Identifiable {
    case cover, contain, stretch
    var id: Self { self }
    var displayName: String {
        switch self {
        case .cover: return "填充"
        case .contain: return "适应"
        case .stretch: return "拉伸"
        }
    }
}

final class RendererProcess {
    let process: Process
    let stdinPipe: Pipe
    let wallpaper: WEWallpaper
    let screenIndex: Int
    private(set) var isTerminated = false

    init(process: Process, stdinPipe: Pipe, wallpaper: WEWallpaper, screenIndex: Int) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.wallpaper = wallpaper
        self.screenIndex = screenIndex
    }

    func send(_ command: [String: Any]) {
        guard !isTerminated, process.isRunning else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: command, options: []) else { return }
        var line = data
        line.append(0x0A)
        let handle = stdinPipe.fileHandleForWriting
        do {
            try handle.write(contentsOf: line)
        } catch { }
    }

    func stop() {
        guard !isTerminated else { return }
        isTerminated = true
        send(["cmd": "quit"])
        let handle = stdinPipe.fileHandleForWriting
        try? handle.close()
        let proc = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if proc.isRunning { proc.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            }
        }
    }
}

struct RenderOptions {
    var fps: Int = 30
    var volume: Float = 1.0
    var muted: Bool = false
    var speed: Float = 1.0
    var fillMode: FillMode = .cover
    var enableSpectrum: Bool = true
    var userProperties: [String: WEProjectProperty] = [:]
}

// 子进程通过 stdin 接收 JSON 行控制指令。
final class RendererController {
    private var running: [Int: RendererProcess] = [:]
    private let queue = DispatchQueue(label: "cn.laobamac.Mirage.renderer")

    var onProcessExit: ((Int, Bool) -> Void)?

    // MARK: 二进制与资源定位

    private var resourcesDir: URL {
        Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }

    private var renderersDir: URL {
        resourcesDir.appending(path: "Renderers")
    }

    private static let devFallback: [WallpaperKind: URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appending(path: "Desktop/SimpleRenderer")
        return [
            .scene: root.appending(path: "SceneRenderer/build/macos-clang-release/Tools/SceneWallpaper/SceneWallpaper"),
            .web:   root.appending(path: "WebRenderer/build/release/Tools/WebWallpaper/WebWallpaper"),
            .video: root.appending(path: "VideoRenderer/build/release/Tools/VideoWallpaper/VideoWallpaper"),
        ]
    }()

    private func binaryURL(for kind: WallpaperKind) -> URL? {
        let name: String
        switch kind {
        case .scene: name = "SceneWallpaper"
        case .web: name = "WebWallpaper"
        case .video: name = "VideoWallpaper"
        case .unsupported: return nil
        }
        let bundled = renderersDir.appending(path: name)
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return Self.devFallback[kind]
    }

    private var sceneAssetsDir: URL {
        let bundled = resourcesDir.appending(path: "assets")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Desktop/SimpleRenderer/assets")
    }

    private var moltenVKICD: URL? {
        let bundled = renderersDir.appending(path: "vulkan/icd.d/MoltenVK_icd.json")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let brew = URL(fileURLWithPath: "/usr/local/etc/vulkan/icd.d/MoltenVK_icd.json")
        return FileManager.default.fileExists(atPath: brew.path) ? brew : nil
    }

    // MARK: 启动 / 切换 / 停止

    @discardableResult
    func render(_ wallpaper: WEWallpaper, on screenIndex: Int = 0, options: RenderOptions) -> Bool {
        guard wallpaper.isValid, wallpaper.kind != .unsupported else { return false }
        guard let binary = binaryURL(for: wallpaper.kind) else {
            NSLog("[Mirage] 找不到 \(wallpaper.kind) 渲染器二进制")
            return false
        }
        NSLog("[Mirage] 启动渲染器: \(binary.path) 屏幕=\(screenIndex)")

        stop(on: screenIndex)

        let proc = Process()
        proc.executableURL = binary

        var args: [String] = []
        var env = ProcessInfo.processInfo.environment

        switch wallpaper.kind {
        case .scene:
            let pkg = wallpaper.wallpaperDirectory.appending(path: "scene.pkg")
            let entry = FileManager.default.fileExists(atPath: pkg.path) ? pkg : wallpaper.entryURL
            args += [sceneAssetsDir.path, entry.path]
            args += ["--fps", String(options.fps)]
            args += ["--screen", String(screenIndex)]
            args += ["--control-stdin"]
            if options.muted { args += ["--muted"] }
            if let propsFile = writeUserPropertiesFile(options.userProperties, for: wallpaper) {
                args += ["--user-properties", propsFile.path]
            }
            if let icd = moltenVKICD {
                env["VK_ICD_FILENAMES"] = icd.path
                env["VK_DRIVER_FILES"] = icd.path
            }
            let fw = Bundle.main.bundleURL.appending(path: "Contents/Frameworks")
            if FileManager.default.fileExists(atPath: fw.path) {
                let existing = env["DYLD_FALLBACK_LIBRARY_PATH"]
                env["DYLD_FALLBACK_LIBRARY_PATH"] = existing.map { "\(fw.path):\($0)" } ?? fw.path
            }

        case .web:
            args += [wallpaper.wallpaperDirectory.path]
            args += ["--fps", String(options.fps)]
            args += ["--volume", String(format: "%.3f", options.muted ? 0 : options.volume)]
            args += ["--screen", String(screenIndex)]
            if !options.enableSpectrum { args += ["--no-spectrum"] }
            args += ["--control-stdin"]

        case .video:
            args += [wallpaper.wallpaperDirectory.path]
            args += ["--screen", String(screenIndex)]
            args += ["--volume", String(format: "%.3f", options.volume)]
            args += ["--fill", options.fillMode.rawValue]
            if options.muted { args += ["--muted"] }
            args += ["--control-stdin"]

        case .unsupported:
            return false
        }

        proc.arguments = args
        proc.environment = env

        let stdinPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = FileHandle.standardOutput
        proc.standardError = FileHandle.standardError

        let handle = RendererProcess(process: proc, stdinPipe: stdinPipe, wallpaper: wallpaper, screenIndex: screenIndex)

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            self.queue.async {
                if let current = self.running[screenIndex], current === handle {
                    let abnormal = p.terminationStatus != 0 && !handle.isTerminated
                    self.running[screenIndex] = nil
                    DispatchQueue.main.async { self.onProcessExit?(screenIndex, abnormal) }
                }
            }
        }

        do {
            try proc.run()
        } catch {
            NSLog("[Mirage] 启动渲染器失败: \(error)")
            return false
        }

        queue.sync { running[screenIndex] = handle }

        applyInitialProperties(options.userProperties, to: handle)
        return true
    }

    func stop(on screenIndex: Int) {
        queue.sync {
            if let proc = running[screenIndex] {
                proc.stop()
                running[screenIndex] = nil
            }
        }
    }

    func stopAll() {
        queue.sync {
            for (_, proc) in running { proc.stop() }
            running.removeAll()
        }
    }

    func isRendering(on screenIndex: Int) -> Bool {
        queue.sync { running[screenIndex]?.process.isRunning ?? false }
    }

    func currentWallpaper(on screenIndex: Int) -> WEWallpaper? {
        queue.sync { running[screenIndex]?.wallpaper }
    }

    var activeScreens: [Int] {
        queue.sync { Array(running.keys).sorted() }
    }

    // MARK: 实时控制（广播到所有屏，或指定屏）

    private func forEach(_ screenIndex: Int?, _ body: (RendererProcess) -> Void) {
        queue.sync {
            if let s = screenIndex {
                if let p = running[s] { body(p) }
            } else {
                for (_, p) in running { body(p) }
            }
        }
    }

    func setVolume(_ volume: Float, on screenIndex: Int? = nil) {
        forEach(screenIndex) { $0.send(["cmd": "volume", "value": volume]) }
    }

    func setMuted(_ muted: Bool, on screenIndex: Int? = nil) {
        forEach(screenIndex) { $0.send(["cmd": "muted", "value": muted]) }
    }

    func pause(on screenIndex: Int? = nil) {
        forEach(screenIndex) { $0.send(["cmd": "pause"]) }
    }

    func resume(on screenIndex: Int? = nil) {
        forEach(screenIndex) { $0.send(["cmd": "resume"]) }
    }

    func setFps(_ fps: Int, on screenIndex: Int? = nil) {
        forEach(screenIndex) { $0.send(["cmd": "fps", "value": fps]) }
    }

    func setSpeed(_ speed: Float, on screenIndex: Int? = nil) {
        forEach(screenIndex) { $0.send(["cmd": "speed", "value": speed]) }
    }

    func setFillMode(_ mode: FillMode, on screenIndex: Int? = nil) {
        forEach(screenIndex) { $0.send(["cmd": "fillmode", "value": mode.rawValue]) }
    }

    func setProperty(key: String, property: WEProjectProperty, on screenIndex: Int? = nil) {
        forEach(screenIndex) { proc in
            proc.send(Self.propertyCommand(key: key, property: property))
        }
    }

    // MARK: 属性 → 指令 / 文件

    private static func propertyCommand(key: String, property: WEProjectProperty) -> [String: Any] {
        var cmd: [String: Any] = ["cmd": "setProperty", "key": key]
        switch property.propertyType {
        case .color:
            cmd["type"] = "color"
            cmd["value"] = property.value.stringValue
        case .bool:
            cmd["value"] = property.value.boolValue
        case .slider:
            cmd["value"] = property.value.doubleValue
        case .scenetexture, .file:
            // 贴图 / 文件替换类：渲染器按 scenetexture 语义实时换图。
            cmd["type"] = "scenetexture"
            cmd["value"] = property.value.stringValue
        case .combo, .textinput, .text, .group, .directory, .usershortcut, .unknown:
            cmd["value"] = property.value.stringValue
        }
        return cmd
    }

    private func writeUserPropertiesFile(_ props: [String: WEProjectProperty], for wallpaper: WEWallpaper) -> URL? {
        guard !props.isEmpty else { return nil }
        var obj: [String: Any] = [:]
        for (key, prop) in props {
            switch prop.propertyType {
            case .color:
                obj[key] = ["type": "color", "value": prop.value.stringValue]
            case .bool:
                obj[key] = prop.value.boolValue
            case .slider:
                obj[key] = prop.value.doubleValue
            case .scenetexture, .file:
                obj[key] = ["type": "scenetexture", "value": prop.value.stringValue]
            default:
                obj[key] = prop.value.stringValue
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "mirage_props_\(abs(wallpaper.id.hashValue)).json")
        do {
            try data.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            return nil
        }
    }

    private func applyInitialProperties(_ props: [String: WEProjectProperty], to handle: RendererProcess) {
        guard handle.wallpaper.kind == .web else { return }
        let cmds = props.map { Self.propertyCommand(key: $0.key, property: $0.value) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            for c in cmds { handle.send(c) }
        }
    }
}
