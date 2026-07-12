//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI
import ImageIO

// MARK: - 属性值

enum WEPropertyValue: Codable, Equatable, Hashable {
    case bool(Bool)
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b); return
        }
        if let d = try? container.decode(Double.self) {
            self = .number(d); return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s); return
        }
        self = .string("")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try container.encode(b)
        case .number(let d):
            if d == d.rounded() && abs(d) < 1e15 {
                try container.encode(Int(d))
            } else {
                try container.encode(d)
            }
        case .string(let s): try container.encode(s)
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let d): return d != 0
        case .string(let s): return (s as NSString).boolValue
        }
    }

    var doubleValue: Double {
        switch self {
        case .bool(let b): return b ? 1 : 0
        case .number(let d): return d
        case .string(let s): return Double(s) ?? 0
        }
    }

    var stringValue: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .number(let d):
            if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
            return String(d)
        case .string(let s): return s
        }
    }
}

// MARK: - 属性选项

struct WEProjectPropertyOption: Codable, Equatable, Hashable {
    var label: String
    var value: String
    var condition: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.label = (try? c.decode(String.self, forKey: .label)) ?? ""
        self.condition = try? c.decode(String.self, forKey: .condition)
        if let s = try? c.decode(String.self, forKey: .value) {
            self.value = s
        } else if let i = try? c.decode(Int.self, forKey: .value) {
            self.value = String(i)
        } else if let d = try? c.decode(Double.self, forKey: .value) {
            self.value = String(d)
        } else {
            self.value = ""
        }
    }

    init(label: String, value: String, condition: String? = nil) {
        self.label = label
        self.value = value
        self.condition = condition
    }

    enum CodingKeys: String, CodingKey {
        case label, value, condition
    }
}

// MARK: - 单条属性

enum WEPropertyType: String {
    case bool
    case slider
    case color
    case combo
    case textinput
    case text
    case group
    case file
    case directory
    case scenetexture
    case usershortcut
    case unknown

    init(raw: String) {
        self = WEPropertyType(rawValue: raw.lowercased()) ?? .unknown
    }
}

struct WEProjectProperty: Codable, Equatable, Hashable {
    var condition: String?
    var index: Int?
    var options: [WEProjectPropertyOption]?
    var order: Int?
    var min: Double?
    var max: Double?
    var step: Double?
    var fraction: Bool?
    var mode: String?

    var text: String?
    var type: String
    var value: WEPropertyValue

    var propertyType: WEPropertyType { WEPropertyType(raw: type) }

    func displayText(fallbackKey key: String) -> String {
        if let t = text, !t.isEmpty {
            return WELocalization.resolve(t)
        }
        return WELocalization.resolve(key)
    }

    enum CodingKeys: String, CodingKey {
        case condition, index, options, order, min, max, step, fraction, mode, text, type, value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.condition = try? c.decode(String.self, forKey: .condition)
        self.index = try? c.decode(Int.self, forKey: .index)
        self.options = try? c.decode([WEProjectPropertyOption].self, forKey: .options)
        self.order = try? c.decode(Int.self, forKey: .order)
        self.min = try? c.decode(Double.self, forKey: .min)
        self.max = try? c.decode(Double.self, forKey: .max)
        self.step = try? c.decode(Double.self, forKey: .step)
        self.fraction = try? c.decode(Bool.self, forKey: .fraction)
        self.mode = try? c.decode(String.self, forKey: .mode)
        self.text = try? c.decode(String.self, forKey: .text)
        self.type = (try? c.decode(String.self, forKey: .type)) ?? "text"
        self.value = (try? c.decode(WEPropertyValue.self, forKey: .value)) ?? .string("")
    }

    init(type: String, value: WEPropertyValue, text: String? = nil, order: Int? = nil) {
        self.type = type
        self.value = value
        self.text = text
        self.order = order
    }
}

// MARK: - Wallpaper Engine 文案本地化

// Wallpaper Engine 的内置属性 / 分组标签常写成本地化 key（如
// `ui_editor_properties_opacity`），词表在 WE 主程序内部，工坊资源里没有。
// 这里内置一份常用 key → 中文 的映射；未命中时不再原样显示 `ui_` 乱码，
// 而是剥掉已知前缀、下划线转空格、单词首字母大写，回退成可读英文标签。
// MARK: - Wallpaper Engine 文案本地化

// Wallpaper Engine 的属性 / 分组 / 选项标签常写成本地化 key（如
// `ui_editor_properties_opacity`）。这里加载官方词表 `ui_zh-chs.json`（随 app 打包，
// 3000+ 条），把 key 解析成简体中文；命中不了的 `ui_` key 回退成可读文本，其余
// （作者自定义文本 / HTML）原样返回。
enum WELocalization {
    // 官方词表，懒加载一次。
    private static let table: [String: String] = {
        guard let url = Bundle.main.url(forResource: "ui_zh-chs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: String] = [:]
        out.reserveCapacity(obj.count)
        for (k, v) in obj {
            if let s = v as? String { out[k] = s }
        }
        return out
    }()

    static func resolve(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return raw }
        // 非本地化 key（作者自定义文本、HTML 等）原样返回。
        guard key.hasPrefix("ui_") else { return raw }
        if let mapped = table[key] { return mapped }
        return humanize(key)
    }

    // 已知前缀，命中不了词表时剥离并转成可读文本。
    private static let prefixes: [String] = [
        "ui_editor_script_snippet_",
        "ui_editor_properties_",
        "ui_browse_properties_",
        "ui_editor_general_",
        "ui_editor_effect_",
        "ui_editor_preset_",
        "ui_editor_",
        "ui_browse_",
        "ui_",
    ]

    private static func humanize(_ key: String) -> String {
        var s = key
        for p in prefixes where s.hasPrefix(p) {
            s = String(s.dropFirst(p.count))
            break
        }
        s = s.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return key }
        return s.split(separator: " ").map { w -> String in
            guard let f = w.first else { return String(w) }
            return f.uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }
}

// MARK: - 属性容器
struct WEProjectProperties: Codable, Equatable, Hashable {
    var items: [String: WEProjectProperty]

    init(items: [String: WEProjectProperty] = [:]) {
        self.items = items
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.intValue = intValue; self.stringValue = String(intValue) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        var result: [String: WEProjectProperty] = [:]
        for key in c.allKeys {
            if let prop = try? c.decode(WEProjectProperty.self, forKey: key) {
                result[key.stringValue] = prop
            }
        }
        self.items = result
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for (key, prop) in items {
            if let dynamicKey = DynamicKey(stringValue: key) {
                try c.encode(prop, forKey: dynamicKey)
            }
        }
    }

    var sorted: [(key: String, property: WEProjectProperty)] {
        items.map { ($0.key, $0.value) }.sorted { a, b in
            let oa = a.property.order ?? a.property.index ?? Int.max
            let ob = b.property.order ?? b.property.index ?? Int.max
            if oa != ob { return oa < ob }
            return a.key < b.key
        }
    }
}

struct WEProjectGeneral: Codable, Equatable, Hashable {
    var properties: WEProjectProperties?
}

// MARK: - Workshop ID

enum WorkshopId: Codable, Equatable, Hashable, RawRepresentable {
    case int(Int)
    case string(String)

    var rawValue: String {
        switch self {
        case .int(let x): return String(x)
        case .string(let x): return x
        }
    }

    init?(rawValue: String) {
        guard rawValue.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self = .string(rawValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) { self = .int(x); return }
        if let x = try? container.decode(String.self) { self = .string(x); return }
        throw DecodingError.typeMismatch(Self.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Workshop ID 类型错误"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let x): try container.encode(x)
        case .string(let x): try container.encode(x)
        }
    }
}

// MARK: - WEProject

struct WEProject: Codable, Equatable, Hashable {
    var approved: Bool?
    var author: String?
    var contentrating: String?
    var description: String?
    var file: String
    var general: WEProjectGeneral?
    var preview: String
    var tags: [String]?
    var title: String
    var visibility: String?
    var workshopid: WorkshopId?
    var workshopurl: String?
    var type: String
    var version: Int?

    var normalizedType: WallpaperKind { WallpaperKind(rawType: type) }

    // 作者信息：WE 本地 project.json 通常没有 author 字段，作者名常写进标题
    // （形如 `[作者名]…`）或简介（`作者：X` / `by X`）。这里尽力提取，取不到
    // 时返回 nil，由 UI 决定回退文案（而不是一律显示“未知作者”）。
    var resolvedAuthor: String? {
        if let a = author?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            return a
        }
        if let fromTitle = Self.extractBracketAuthor(title) { return fromTitle }
        if let desc = description, let fromDesc = Self.extractLabeledAuthor(desc) {
            return fromDesc
        }
        return nil
    }

    private static func extractBracketAuthor(_ s: String) -> String? {
        // 匹配开头的 [作者] 或 【作者】。
        let pattern = "^\\s*[\\[【]([^\\]】]{1,40})[\\]】]"
        guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
        let inside = s[r].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return inside.isEmpty ? nil : String(inside)
    }

    private static func extractLabeledAuthor(_ s: String) -> String? {
        let patterns = ["作者[:：]\\s*([^\\n\\r，,。;；]{1,40})",
                        "(?i)\\bby\\s+([^\\n\\r,;]{1,40})",
                        "(?i)author[:：]\\s*([^\\n\\r,;]{1,40})"]
        for p in patterns {
            guard let r = s.range(of: p, options: .regularExpression) else { continue }
            let match = String(s[r])
            if let sep = match.range(of: "[:：]|(?i)\\bby\\b", options: .regularExpression) {
                let name = match[sep.upperBound...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    static let invalid = Self(file: "",
                              preview: "",
                              title: "未知",
                              type: "video")

    init(approved: Bool? = nil, author: String? = nil, contentrating: String? = nil, description: String? = nil,
         file: String, general: WEProjectGeneral? = nil, preview: String,
         tags: [String]? = nil, title: String, visibility: String? = nil,
         workshopid: WorkshopId? = nil, workshopurl: String? = nil, type: String, version: Int? = nil) {
        self.approved = approved
        self.author = author
        self.contentrating = contentrating
        self.description = description
        self.file = file
        self.general = general
        self.preview = preview
        self.tags = tags
        self.title = title
        self.visibility = visibility
        self.workshopid = workshopid
        self.workshopurl = workshopurl
        self.type = type
        self.version = version
    }
}

enum WallpaperKind: String {
    case scene, web, video, unsupported

    init(rawType: String) {
        switch rawType.lowercased() {
        case "scene": self = .scene
        case "web": self = .web
        case "video": self = .video
        default: self = .unsupported
        }
    }

    var displayName: String {
        switch self {
        case .scene: return "场景"
        case .web: return "网页"
        case .video: return "视频"
        case .unsupported: return "不支持"
        }
    }
}

// MARK: - WEWallpaper

struct WEWallpaper: Codable, RawRepresentable, Identifiable, Equatable, Hashable {

    var wallpaperDirectory: URL
    var project: WEProject

    var id: String { wallpaperDirectory.path(percentEncoded: false) }

    var entryURL: URL { wallpaperDirectory.appending(path: project.file) }
    var previewURL: URL { wallpaperDirectory.appending(path: project.preview) }
    var kind: WallpaperKind { project.normalizedType }
    var isValid: Bool { project != .invalid && !project.file.isEmpty }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    var wallpaperSize: Int {
        let path = wallpaperDirectory.path(percentEncoded: false)
        if let cached = Self.sizeCache[path] { return cached }
        let size = (try? wallpaperDirectory.directoryTotalAllocatedSize(includingSubfolders: true)) ?? 0
        Self.sizeCache[path] = size
        return size
    }

    init(using project: WEProject, where url: URL) {
        self.wallpaperDirectory = url
        self.project = project
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let wallpaper = try? JSONDecoder().decode(WEWallpaper.self, from: data) else {
            return nil
        }
        self = wallpaper
    }

    enum CodingKeys: CodingKey { case wallpaperDirectory, project }

    nonisolated(unsafe) static var sizeCache: [String: Int] = [:]

    static func invalidateSizeCache() { sizeCache.removeAll() }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.wallpaperDirectory = try c.decode(URL.self, forKey: .wallpaperDirectory)
        self.project = try c.decode(WEProject.self, forKey: .project)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wallpaperDirectory, forKey: .wallpaperDirectory)
        try c.encode(project, forKey: .project)
    }

    static func == (lhs: WEWallpaper, rhs: WEWallpaper) -> Bool {
        lhs.wallpaperDirectory == rhs.wallpaperDirectory && lhs.project == rhs.project
    }

    func hash(into hasher: inout Hasher) { hasher.combine(wallpaperDirectory) }

    static func load(from url: URL) -> WEWallpaper {
        if let data = try? Data(contentsOf: url.appending(path: "project.json")),
           let project = try? JSONDecoder().decode(WEProject.self, from: data) {
            return WEWallpaper(using: project, where: url)
        }
        return WEWallpaper(using: .invalid, where: url)
    }
}

// MARK: - 排序

enum WEWallpaperSortingMethod: String, CaseIterable, Identifiable {
    var id: Self { self }
    case name = "名称"
    case rating = "评分"
    case fileSize = "文件大小"
}

enum WEWallpaperSortingSequence: Int, Codable {
    case decrease = 0, increase = 1
}

// MARK: - URL 目录大小工具

extension URL {
    func isDirectoryAndReachable() throws -> Bool {
        guard try resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { return false }
        return try checkResourceIsReachable()
    }

    func directoryTotalAllocatedSize(includingSubfolders: Bool = false) throws -> Int? {
        guard try isDirectoryAndReachable() else { return nil }
        if includingSubfolders {
            guard let urls = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)?.allObjects as? [URL] else { return nil }
            return try urls.lazy.reduce(0) {
                (try $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) + $0
            }
        }
        return try FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil).lazy.reduce(0) {
            (try $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) + $0
        }
    }
}
