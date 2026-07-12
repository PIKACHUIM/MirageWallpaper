//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - 属性面板

// 忠实还原 Wallpaper Engine 的自定义侧栏：全部属性类型、条件显隐（JS 表达式）、
// 官方本地化、真 HTML 标签（内联图片 / 可点链接 / 居中 / 大字 / 颜色）。
struct PropertyEditor: View {
    @EnvironmentObject var wallpaperViewModel: WallpaperViewModel
    let wallpaper: WEWallpaper

    // condition 求值器：每个面板一份，随取值刷新上下文。
    @StateObject private var conditions = ConditionStore()

    private var allProperties: [String: WEProjectProperty] {
        wallpaper.project.general?.properties?.items ?? [:]
    }

    private var sortedProperties: [(key: String, property: WEProjectProperty)] {
        wallpaper.project.general?.properties?.sorted ?? []
    }

    // 经 condition 过滤后的可见属性。
    private var visibleProperties: [(key: String, property: WEProjectProperty)] {
        sortedProperties.filter { conditions.isVisible($0.property.condition) }
    }

    var body: some View {
        Group {
            if sortedProperties.isEmpty {
                HStack {
                    Text("此壁纸没有可调节的属性。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleProperties, id: \.key) { entry in
                        PropertyRow(wallpaper: wallpaper, key: entry.key,
                                    property: entry.property, conditions: conditions)
                            .environmentObject(wallpaperViewModel)
                    }
                }
            }
        }
        .onAppear { refreshConditions() }
        .onChange(of: wallpaperViewModel.runtime.propertyOverrides) { _, _ in refreshConditions() }
        .onChange(of: wallpaper.id) { _, _ in refreshConditions() }
    }

    private func refreshConditions() {
        conditions.update(properties: allProperties,
                          overrides: wallpaperViewModel.runtime.propertyOverrides)
    }
}

// 把 condition 求值器包成 ObservableObject，取值变化时触发面板重算可见性。
final class ConditionStore: ObservableObject {
    private let evaluator = WEConditionEvaluator()
    // 变化计数，用来在取值更新后驱动依赖它的视图刷新。
    @Published private(set) var generation = 0

    func update(properties: [String: WEProjectProperty], overrides: [String: WEPropertyValue]) {
        evaluator.updateContext(properties: properties, overrides: overrides)
        generation &+= 1
    }

    func isVisible(_ condition: String?) -> Bool {
        _ = generation // 建立依赖
        return evaluator.evaluate(condition)
    }
}

// MARK: - 单条属性

struct PropertyRow: View {
    @EnvironmentObject var wallpaperViewModel: WallpaperViewModel
    let wallpaper: WEWallpaper
    let key: String
    let property: WEProjectProperty
    @ObservedObject var conditions: ConditionStore

    private var currentValue: WEPropertyValue {
        wallpaperViewModel.runtime.propertyOverrides[key] ?? property.value
    }

    private var rawText: String { property.displayText(fallbackKey: key) }

    // 标签：含真 HTML（图片 / 链接 / 居中 / 大字 / 颜色）时用 WKWebView 忠实渲染；
    // 纯文本 / 轻量格式则用原生 Text，避免为每一行都背上 WebKit。
    @ViewBuilder
    private func labelView(lineLimit: Int? = nil, expand: Bool = true) -> some View {
        if WEHTML.isRich(rawText) {
            RichHTMLText(html: rawText)
                .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
        } else {
            Text(WEHTML.plain(rawText))
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
        }
    }

    var body: some View {
        switch property.propertyType {
        case .bool:
            Toggle(isOn: Binding(
                get: { currentValue.boolValue },
                set: { wallpaperViewModel.setProperty(key: key, value: .bool($0)) })) {
                labelView()
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
                labelView(lineLimit: 2)
            }

        case .combo:
            HStack(alignment: .firstTextBaseline) {
                labelView(lineLimit: 2, expand: false)
                Spacer()
                Picker("", selection: Binding(
                    get: { currentValue.stringValue },
                    set: { wallpaperViewModel.setProperty(key: key, value: .string($0)) })) {
                    ForEach(visibleOptions, id: \.value) { opt in
                        Text(WELocalization.resolve(opt.label)).tag(opt.value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
            }

        case .textinput:
            VStack(alignment: .leading, spacing: 4) {
                labelView(lineLimit: 2)
                TextField("", text: Binding(
                    get: { currentValue.stringValue },
                    set: { wallpaperViewModel.setProperty(key: key, value: .string($0)) }))
                    .textFieldStyle(.roundedBorder)
            }

        case .text:
            labelView()

        case .group:
            VStack(alignment: .leading, spacing: 4) {
                if WEHTML.isRich(rawText) {
                    RichHTMLText(html: rawText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(WEHTML.plain(rawText))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().overlay(Color.accentColor.opacity(0.5))
            }
            .padding(.top, 10)

        case .file, .scenetexture:
            filePickerRow(kind: .file)

        case .directory:
            filePickerRow(kind: .directory)

        case .usershortcut:
            HStack(alignment: .firstTextBaseline) {
                labelView(lineLimit: 2, expand: false)
                Spacer()
                TextField("快捷方式", text: Binding(
                    get: { currentValue.stringValue },
                    set: { wallpaperViewModel.setProperty(key: key, value: .string($0)) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 170)
            }

        case .unknown:
            EmptyView()
        }
    }

    // 只显示满足自身 condition 的下拉选项（WE 每个 option 也可带 condition）。
    private var visibleOptions: [WEProjectPropertyOption] {
        (property.options ?? []).filter { conditions.isVisible($0.condition) }
    }

    // MARK: 文件 / 目录 / 贴图选择

    private enum PickKind { case file, directory }

    @ViewBuilder
    private func filePickerRow(kind: PickKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            labelView(lineLimit: 2)
            HStack {
                Text(displayPath.isEmpty ? "未选择" : displayPath)
                    .font(.caption)
                    .foregroundStyle(displayPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !displayPath.isEmpty {
                    Button {
                        wallpaperViewModel.setProperty(key: key, value: .string(""))
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button("选择…") { pick(kind: kind) }
            }
        }
    }

    private var displayPath: String {
        let p = currentValue.stringValue
        guard !p.isEmpty else { return "" }
        return (p as NSString).lastPathComponent
    }

    private func pick(kind: PickKind) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = kind == .file
        panel.canChooseDirectories = kind == .directory
        panel.allowsMultipleSelection = false
        if kind == .file, property.propertyType != .file {
            panel.allowedContentTypes = [.image] // scenetexture：限图片
        }
        if panel.runModal() == .OK, let url = panel.url {
            wallpaperViewModel.setProperty(key: key, value: .string(url.path))
        }
    }

    private var sliderRange: ClosedRange<Double> {
        let lo = property.min ?? 0
        let hi = property.max ?? 100
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
