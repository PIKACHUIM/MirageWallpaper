//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import Foundation
import JavaScriptCore

// Wallpaper Engine 的属性 / 选项 `condition` 是 JavaScript 表达式，形如：
//   "clock.value == true"
//   "wallpapermode.value == 2"
//   "appdock.value == true && [10,11,12].includes(newproperty.value)"
// WE 用它实时控制某个属性 / 下拉选项是否显示。这里用 JavaScriptCore 忠实求值：
// 把当前所有属性的取值注入成 `key.value`，再 eval 表达式取布尔结果。
//
// 出于健壮性：空表达式视为「显示」；求值异常 / 非布尔结果一律回退成「显示」，
// 绝不因为一条写得古怪的 condition 把属性藏没了。
final class WEConditionEvaluator {
    private let context = JSContext()

    init() {
        // 静默异常，避免污染控制台；失败时按「显示」处理（见 evaluate）。
        context?.exceptionHandler = { _, _ in }
    }

    // 用当前属性取值刷新 JS 上下文：为每个属性建立 `<key> = { value: <v> }`。
    // 取值类型按 WE 语义映射：bool→boolean，slider/数字→number，其余→string。
    func updateContext(properties: [String: WEProjectProperty],
                       overrides: [String: WEPropertyValue]) {
        guard let context else { return }
        var obj: [String: [String: Any]] = [:]
        obj.reserveCapacity(properties.count)
        for (key, prop) in properties {
            let raw = overrides[key] ?? prop.value
            obj[key] = ["value": jsValue(for: raw, type: prop.propertyType)]
        }
        for (key, entry) in obj {
            // 直接把每个属性作为全局对象注入，`key.value` 即可访问。
            context.setObject(entry, forKeyedSubscript: key as NSString)
        }
    }

    // 求值一条 condition。nil / 空 → true（显示）。
    func evaluate(_ condition: String?) -> Bool {
        guard let condition, !condition.trimmingCharacters(in: .whitespaces).isEmpty else {
            return true
        }
        guard let context else { return true }
        guard let result = context.evaluateScript(condition) else { return true }
        // 布尔直接用；数字非 0 视真；其它（undefined/异常）回退显示。
        if result.isBoolean { return result.toBool() }
        if result.isNumber { return result.toDouble() != 0 }
        if result.isNull || result.isUndefined { return true }
        return result.toBool()
    }

    private func jsValue(for value: WEPropertyValue, type: WEPropertyType) -> Any {
        switch value {
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s):
            // 布尔型属性偶尔以字符串存布尔；数值型下拉的 value 可能是字符串数字。
            if type == .bool { return (s as NSString).boolValue }
            if let i = Int(s) { return i }
            if let d = Double(s) { return d }
            if s == "true" { return true }
            if s == "false" { return false }
            return s
        }
    }
}
