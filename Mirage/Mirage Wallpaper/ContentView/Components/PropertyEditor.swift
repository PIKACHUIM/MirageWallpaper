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


// MARK: - WE 标签清洗

// Wallpaper Engine 的属性 / 分组标签里常夹带 HTML，而且经常是残缺的：<big>、
// <center>、<font color>、<a href>、跨行的 <img>、全角尖括号 ＜＞、以及被复制
// 截断的未闭合标签。侧栏只需要「干净可读的文本」，不需要富文本渲染，也不该为此
// 背上 WebKit（WKWebView / NSAttributedString HTML 导入器都要走主线程且开销大）。
//
// 因此这里不做富文本解析，而是用正则把标签整体剥离成纯文本：归一化全角尖括号、
// 把换行类标签转成换行、去掉所有完整标签与未闭合的截断标签、解码实体、折叠空白。
// 相比手写状态机，这种做法没有无穷无尽的边角情况，也不会把标签本身漏成文本。
enum WERichText {
    static func attributed(from raw: String) -> AttributedString {
        AttributedString(clean(raw))
    }

    static func clean(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "＜", with: "<")
            .replacingOccurrences(of: "＞", with: ">")
        func regexReplace(_ pattern: String, _ replacement: String) {
            s = s.replacingOccurrences(of: pattern, with: replacement,
                                       options: [.regularExpression, .caseInsensitive])
        }
        // 换行类标签 → 换行，保留原有分行。
        regexReplace("<\\s*br\\s*/?>", "\n")
        regexReplace("<\\s*/?\\s*(p|div|center)\\s*>", "\n")
        // 去掉所有其余完整标签（[^>] 会跨行匹配，覆盖跨行 <img …>）。
        regexReplace("<[^>]*>", "")
        // 去掉未闭合的截断标签：'<'（可含 '/'/空格）后跟字母、直到串尾。
        // 数字/符号开头的 '<'（如 `价格<3元`、`a < b`）不动，避免误伤正文。
        regexReplace("<\\s*/?\\s*[a-zA-Z][^<]*$", "")
        // 整行只剩一个残缺的闭合标签（作者漏了 '<'，如单独一行 `center>`）时删掉整行。
        // 仅当整行就是「标签名 + '>'」才匹配，绝不误伤 `so big > small` 这类正文。
        regexReplace("(?m)^[ \\t]*/?(?:center|big|small|strong|font|span|div|sub|sup|b|i|u|p|a)[ \\t]*>[ \\t]*$", "")
        s = decodeEntities(s)
        // 折叠多余空白与空行。
        regexReplace("[ \\t]+", " ")
        regexReplace("\\n{3,}", "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
