//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct PropertyEditor: View {
    @EnvironmentObject var wallpaperViewModel: WallpaperViewModel
    let wallpaper: WEWallpaper

    private var properties: [(key: String, property: WEProjectProperty)] {
        wallpaper.project.general?.properties?.sorted ?? []
    }

    var body: some View {
        if properties.isEmpty {
            HStack {
                Text("此壁纸没有可调节的属性。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(properties, id: \.key) { entry in
                    PropertyRow(wallpaper: wallpaper, key: entry.key, property: entry.property)
                        .environmentObject(wallpaperViewModel)
                }
            }
        }
    }
}

struct PropertyRow: View {
    @EnvironmentObject var wallpaperViewModel: WallpaperViewModel
    let wallpaper: WEWallpaper
    let key: String
    let property: WEProjectProperty

    private var currentValue: WEPropertyValue {
        wallpaperViewModel.runtime.propertyOverrides[key] ?? property.value
    }

    private var rawText: String { property.displayText(fallbackKey: key) }

    // 属性标签可能带 Wallpaper Engine 的 HTML（粗体 / 颜色 / 链接 / 图片）。
    // 用原生 AttributedString 渲染，彻底摆脱 WKWebView 带来的卡顿、坏图、
    // 横向滚动条、滚轮失灵、异步测高错位等问题。图片直接丢弃。
    @ViewBuilder
    private func labelView(lineLimit: Int? = nil, expand: Bool = true) -> some View {
        Text(WERichText.attributed(from: rawText))
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
    }

    var body: some View {
        switch property.propertyType {
        case .bool:
            Toggle(isOn: Binding(
                get: { currentValue.boolValue },
                set: { wallpaperViewModel.setProperty(key: key, value: .bool($0)) })) {
                labelView(lineLimit: nil)
            }

        case .slider:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    labelView(lineLimit: 1, expand: false)
                    Spacer()
                    Text(sliderValueText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { currentValue.doubleValue },
                        set: { newVal in
                            let v = (property.fraction == true) ? newVal : newVal.rounded()
                            wallpaperViewModel.setProperty(key: key, value: .number(v))
                        }),
                    in: sliderRange)
            }

        case .color:
            ColorPicker(selection: Binding(
                get: { Self.parseColor(currentValue.stringValue) },
                set: { wallpaperViewModel.setProperty(key: key, value: .string(Self.encodeColor($0))) }),
                supportsOpacity: false) {
                labelView(lineLimit: 1)
            }

        case .combo:
            HStack {
                labelView(lineLimit: 1, expand: false)
                Spacer()
                Picker("", selection: Binding(
                    get: { currentValue.stringValue },
                    set: { wallpaperViewModel.setProperty(key: key, value: .string($0)) })) {
                    ForEach(property.options ?? [], id: \.value) { opt in
                        Text(WELocalization.resolve(opt.label)).tag(opt.value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }

        case .textinput:
            VStack(alignment: .leading, spacing: 4) {
                labelView(lineLimit: 1)
                TextField("", text: Binding(
                    get: { currentValue.stringValue },
                    set: { wallpaperViewModel.setProperty(key: key, value: .string($0)) }))
                    .textFieldStyle(.roundedBorder)
            }

        case .group:
            // 分组标题：作为分节标题渲染，恢复侧栏层次。
            VStack(alignment: .leading, spacing: 4) {
                Text(WERichText.attributed(from: rawText))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider().overlay(Color.accentColor.opacity(0.5))
            }
            .padding(.top, 10)

        case .text:
            labelView(lineLimit: nil)

        case .file, .unknown:
            EmptyView()
        }
    }

    private var sliderRange: ClosedRange<Double> {
        let lo = property.min ?? 0
        let hi = property.max ?? 100
        // 防御非法区间（max <= min 会让 Slider 崩溃）。
        return lo < hi ? lo...hi : lo...(lo + 1)
    }

    private var sliderValueText: String {
        let v = currentValue.doubleValue
        return property.fraction == true ? String(format: "%.2f", v) : String(Int(v.rounded()))
    }

    static func parseColor(_ s: String) -> Color {
        let comps = s.split(separator: " ").compactMap { Double($0) }
        guard comps.count >= 3 else { return .white }
        return Color(.sRGB, red: comps[0], green: comps[1], blue: comps[2], opacity: 1)
    }

    static func encodeColor(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "%.5f %.5f %.5f", ns.redComponent, ns.greenComponent, ns.blueComponent)
    }
}

// MARK: - WE 标签 HTML → AttributedString

// Wallpaper Engine 的属性/分组标签偶尔带一小撮 HTML：<b>/<i>/<br>/<font color>/
// <a href>/<p>，以及会指向工坊路径的 <img>（在侧栏里根本加载不了）。这里做一个
// 轻量、健壮的解析器：支持粗体 / 斜体 / 颜色 / 链接 / 换行，丢弃图片和未知标签，
// 解码常见 HTML 实体。不依赖 WebKit，主线程零阻塞。
enum WERichText {
    private struct Style {
        var bold = false
        var italic = false
        var color: Color?
        var link: URL?
    }

    static func attributed(from raw: String) -> AttributedString {
        guard looksLikeHTML(raw) else { return AttributedString(decodeEntities(raw)) }

        var result = AttributedString()
        var style = Style()
        var stack: [(tag: String, style: Style)] = []

        let chars = Array(raw)
        var i = 0
        var textBuffer = ""

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            var piece = AttributedString(decodeEntities(textBuffer))
            if style.bold || style.italic {
                var font = Font.body
                if style.bold { font = font.bold() }
                if style.italic { font = font.italic() }
                piece.font = font
            }
            if let c = style.color { piece.foregroundColor = c }
            if let l = style.link { piece.link = l }
            result += piece
            textBuffer = ""
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "<" {
                // 找到闭合 '>'
                guard let close = chars[i...].firstIndex(of: ">") else {
                    // 没有闭合 '>' 的截断标签（如 `<a hef="...`）。若紧跟字母或
                    // '/'，判定为一个被截断的 HTML 标签片段并整段丢弃，避免把
                    // `<a href=...` 这种残留原样显示；否则当作普通的 '<' 字符。
                    let next = i + 1 < chars.count ? chars[i + 1] : " "
                    if next.isLetter || next == "/" {
                        flushText()
                        i = chars.count // 丢弃到结尾
                    } else {
                        textBuffer.append(ch); i += 1
                    }
                    continue
                }
                let tagContent = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespaces)
                i = close + 1
                if tagContent.isEmpty { continue }

                flushText()
                let isClosing = tagContent.hasPrefix("/")
                let body = isClosing ? String(tagContent.dropFirst()) : tagContent
                let name = tagName(body).lowercased()

                // 仅识别已知标签；把非标签的 '<...>'（如数学式 `<3>`、占位符）
                // 当普通文本，避免误吞正文。
                if !isClosing, !Self.knownTags.contains(name) {
                    textBuffer.append("<")
                    textBuffer.append(contentsOf: tagContent)
                    textBuffer.append(">")
                    continue
                }

                if isClosing {
                    // 弹栈直到匹配的开标签，恢复样式。
                    if let idx = stack.lastIndex(where: { $0.tag == name }) {
                        style = stack[idx].style
                        stack.removeSubrange(idx...)
                    }
                    if name == "p" || name == "div" { result += AttributedString("\n") }
                    continue
                }

                switch name {
                case "br":
                    result += AttributedString("\n")
                case "img":
                    break // 丢弃图片
                case "b", "strong":
                    stack.append((name, style)); style.bold = true
                case "i", "em":
                    stack.append((name, style)); style.italic = true
                case "u", "span":
                    stack.append((name, style))
                case "p", "div":
                    stack.append((name, style))
                case "font":
                    stack.append((name, style))
                    if let c = colorAttr(body) { style.color = c }
                case "a":
                    stack.append((name, style))
                    if let href = hrefAttr(body), let url = URL(string: href) { style.link = url }
                default:
                    stack.append((name, style)) // 未知标签仅作用域占位
                }
            } else {
                textBuffer.append(ch)
                i += 1
            }
        }
        flushText()
        if result.runs.isEmpty { return AttributedString(decodeEntities(raw)) }
        return result
    }

    // 已识别的 HTML 标签集合；其余 `<...>` 视作普通文本。
    static let knownTags: Set<String> = [
        "b", "strong", "i", "em", "u", "span", "p", "div", "font", "a", "br", "img",
    ]

    static func looksLikeHTML(_ s: String) -> Bool {
        // 完整标签 `<tag ...>`；或被截断的开/闭标签 `<a href=...`（无闭合 '>'），
        // 后者正是残留 `<a hef=...` 的来源，必须一并识别并交给解析器清理。
        if s.range(of: "<[a-zA-Z!/][^>]*>", options: .regularExpression) != nil { return true }
        if s.range(of: "<[a-zA-Z/][a-zA-Z0-9]*[ =/]", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func tagName(_ body: String) -> String {
        var name = ""
        for c in body {
            if c == " " || c == "\t" || c == "/" || c == ">" { break }
            name.append(c)
        }
        return name
    }

    private static func attribute(_ body: String, _ attr: String) -> String? {
        // 匹配 attr="..." / attr='...' / attr=xxx
        let patterns = [
            "\(attr)\\s*=\\s*\"([^\"]*)\"",
            "\(attr)\\s*=\\s*'([^']*)'",
            "\(attr)\\s*=\\s*([^\\s>]+)",
        ]
        for p in patterns {
            if let r = body.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                let match = String(body[r])
                if let eq = match.firstIndex(of: "=") {
                    var val = String(match[match.index(after: eq)...])
                        .trimmingCharacters(in: .whitespaces)
                    val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    return val
                }
            }
        }
        return nil
    }

    private static func hrefAttr(_ body: String) -> String? { attribute(body, "href") }

    private static func colorAttr(_ body: String) -> Color? {
        guard let raw = attribute(body, "color") else { return nil }
        return parseCSSColor(raw)
    }

    private static let namedColors: [String: Color] = [
        "black": .black, "white": .white, "red": .red, "green": .green,
        "blue": .blue, "yellow": .yellow, "orange": .orange, "purple": .purple,
        "gray": .gray, "grey": .gray, "cyan": .cyan, "pink": .pink,
    ]

    private static func parseCSSColor(_ raw: String) -> Color? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let named = namedColors[s] { return named }
        var hex = s
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let semi = s[i...].firstIndex(of: ";") {
                let entity = String(s[s.index(after: i)..<semi])
                if let decoded = decodeEntity(entity) {
                    out.append(decoded)
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    private static func decodeEntity(_ e: String) -> Character? {
        switch e.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        case "nbsp": return "\u{00A0}"
        default: break
        }
        if e.hasPrefix("#x") || e.hasPrefix("#X") {
            if let v = UInt32(e.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(v) {
                return Character(scalar)
            }
        } else if e.hasPrefix("#") {
            if let v = UInt32(e.dropFirst()), let scalar = Unicode.Scalar(v) {
                return Character(scalar)
            }
        }
        return nil
    }
}
