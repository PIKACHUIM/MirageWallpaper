//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI
import WebKit

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

    private var isHTML: Bool {
        rawText.range(of: "<[a-zA-Z!/][^>]*>", options: .regularExpression) != nil
    }

    private var label: String { rawText }

    @ViewBuilder
    private func labelView(lineLimit: Int? = nil) -> some View {
        if isHTML {
            HTMLLabel(html: rawText)
        } else {
            Text(label).lineLimit(lineLimit)
        }
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
                    labelView(lineLimit: 1)
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
                    in: (property.min ?? 0)...(max(property.max ?? 100, property.min ?? 100)))
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
                labelView(lineLimit: 1)
                Spacer()
                Picker("", selection: Binding(
                    get: { currentValue.stringValue },
                    set: { wallpaperViewModel.setProperty(key: key, value: .string($0)) })) {
                    ForEach(property.options ?? [], id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
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

        case .text:
            labelView(lineLimit: nil)

        case .file, .unknown:
            EmptyView()
        }
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

// Wallpaper Engine 属性标签可能包含 HTML。
struct HTMLLabel: View {
    let html: String
    @State private var height: CGFloat = 20

    var body: some View {
        HTMLWebView(html: html, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HTMLWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedHTML == html { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(Self.wrap(html), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func wrap(_ body: String) -> String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width">
        <style>
        :root { color-scheme: light dark; }
        body { margin:0; padding:0; font: -apple-system-body, system-ui;
               font-size: 12px; color: -apple-system-label;
               word-break: break-word; overflow-wrap: anywhere; background: transparent; }
        a { color: -apple-system-blue; }
        img { max-width: 100%; height: auto; }
        p { margin: 2px 0; }
        </style></head><body>\(body)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLWebView
        var loadedHTML: String?
        init(_ parent: HTMLWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = "Math.ceil(document.body.scrollHeight)"
            webView.evaluateJavaScript(js) { result, _ in
                if let h = result as? CGFloat, h > 0 {
                    DispatchQueue.main.async { self.parent.height = h }
                } else if let n = result as? NSNumber {
                    DispatchQueue.main.async { self.parent.height = CGFloat(truncating: n) }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
