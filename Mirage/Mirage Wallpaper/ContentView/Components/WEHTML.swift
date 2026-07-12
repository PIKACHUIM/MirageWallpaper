//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI
import WebKit

// MARK: - WE 标签 HTML

// Wallpaper Engine 的属性 / 分组 / 文本标签用 HTML 描述。分两类处理：
//   · 富内容（含 <img> 图片 / <a> 链接 / <table> 等）→ 用 WKWebView 忠实渲染，
//     支持远程图片异步加载、点击链接跳浏览器、居中 / 大字 / 颜色。
//   · 轻量内容（纯文本，或仅 <b>/<br>/<font> 之类）→ 归一成纯文本用原生 Text，
//     不为此背上 WebKit，避免几十行都塞 webview 造成卡顿。
enum WEHTML {
    // 判定是否需要「真 HTML」渲染：出现图片 / 链接 / 表格 / 居中等结构化标签。
    static func isRich(_ raw: String) -> Bool {
        let s = raw.replacingOccurrences(of: "＜", with: "<").replacingOccurrences(of: "＞", with: ">")
        return s.range(of: "<\\s*(img|a|table|center|iframe|video)\\b",
                       options: [.regularExpression, .caseInsensitive]) != nil
    }

    // 把标签清洗成纯文本（供非富内容用）。
    static func plain(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "＜", with: "<")
            .replacingOccurrences(of: "＞", with: ">")
        func rx(_ pattern: String, _ rep: String) {
            s = s.replacingOccurrences(of: pattern, with: rep,
                                       options: [.regularExpression, .caseInsensitive])
        }
        rx("<\\s*br\\s*/?>", "\n")
        rx("<\\s*/?\\s*(p|div|center)\\s*>", "\n")
        rx("<[^>]*>", "")
        rx("<\\s*/?\\s*[a-zA-Z][^<]*$", "")
        rx("(?m)^[ \\t]*/?(?:center|big|small|strong|font|span|div|sub|sup|b|i|u|p|a)[ \\t]*>[ \\t]*$", "")
        s = decodeEntities(s)
        rx("[ \\t]+", " ")
        rx("\\n{3,}", "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
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

// MARK: - 富 HTML 渲染（WKWebView）

// 用一个 WKWebView 忠实渲染 WE 富文本标签：透明背景、跟随系统配色与字体、图片
// 自适应宽度并异步加载、点击链接跳系统浏览器。禁用 webview 自身滚动，靠 JS 测高
// 自适应，把滚轮转发给外层 SwiftUI ScrollView，避免吞滚动。
struct RichHTMLText: View {
    let html: String
    @State private var height: CGFloat = 24

    var body: some View {
        RichHTMLWebView(html: html, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private final class PassThroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

private struct RichHTMLWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let webView = PassThroughWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(Self.wrap(html), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func wrap(_ body: String) -> String {
        // 归一全角尖括号，套上跟随系统配色 / 字体的样式。
        let normalized = body
            .replacingOccurrences(of: "＜", with: "<")
            .replacingOccurrences(of: "＞", with: ">")
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin:0; padding:0; background:transparent; }
        body {
            font: -apple-system-body, system-ui;
            font-size: 13px; line-height: 1.45;
            color: -apple-system-label;
            word-break: break-word; overflow-wrap: anywhere;
            overflow: hidden;
        }
        a { color: -apple-system-blue; text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; height: auto; border-radius: 6px; display: block; margin: 4px 0; }
        big { font-size: 1.2em; }
        center { text-align: center; }
        p { margin: 4px 0; }
        table { max-width: 100%; }
        </style></head><body>\(normalized)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: RichHTMLWebView
        var loadedHTML: String?
        init(_ parent: RichHTMLWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure(webView)
            // 远程图片解码后高度会变，二次测量补一次。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak webView] in
                guard let webView else { return }
                self.measure(webView)
            }
        }

        private func measure(_ webView: WKWebView) {
            let js = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
            webView.evaluateJavaScript(js) { result, _ in
                let h: CGFloat?
                if let v = result as? CGFloat { h = v }
                else if let n = result as? NSNumber { h = CGFloat(truncating: n) }
                else { h = nil }
                if let h, h > 0, abs(h - self.parent.height) > 0.5 {
                    DispatchQueue.main.async { self.parent.height = h }
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
