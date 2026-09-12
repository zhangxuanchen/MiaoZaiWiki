// ═══════════════════════════════════════════════════════════════
//  export_spec —— 把代码里的形象参数导出成 JSON
//
//  用法：  export_spec > harness/ip-spec.json
//
//  它有什么用：
//    · 让「换个 IP」这件事有据可依 —— 改哪些字段一目了然，不用翻 4800 行源码
//    · 给别的工具/语言读（渲染归 Swift，调度可以归任何东西）
//    · 当基线：导一份存着，以后参数被改了，diff 一下就看得出来
//
//  ⚠️ 现在它是**单向**的：Swift 是真相，JSON 是快照。
//     要做到「改 JSON 就换形象」，需要把绘制改成读这份数据 —— 那是下一步。
// ═══════════════════════════════════════════════════════════════

import Cocoa

func rgba(_ c: NSColor) -> [Double] {
    let s = c.usingColorSpace(.sRGB) ?? c
    func r(_ v: CGFloat) -> Double { (Double(v) * 1000).rounded() / 1000 }
    return [r(s.redComponent), r(s.greenComponent), r(s.blueComponent), r(s.alphaComponent)]
}

func lookDict(_ l: Look) -> [String: Any] {
    [
        "name": l.name,
        "fur": rgba(l.fur), "furLight": rgba(l.furLight),
        "furShadow": rgba(l.furShadow), "furDark": rgba(l.furDark),
        "furLit": rgba(l.furLit), "furDeep": rgba(l.furDeep),
        "patch": rgba(l.patch), "patchLit": rgba(l.patchLit), "patchDk": rgba(l.patchDk),
        "bandana": rgba(l.bandana), "bandanaDk": rgba(l.bandanaDk),
        "eyeL": rgba(l.eyeL), "eyeR": rgba(l.eyeR),
        "pink": rgba(l.pink), "pinkDeep": rgba(l.pinkDeep), "pinkLit": rgba(l.pinkLit),
        "blush": rgba(l.blush), "tongue": rgba(l.tongue),
        "outline": rgba(l.outline), "outlineDk": rgba(l.outlineDk), "dark": rgba(l.dark),
    ]
}

// ── 各维度 ──

let palette: [[String: Any]] = LOOKS.map(lookDict)

let eyeShapes: [[String: Any]] = [EyeStyle.flat, .round, .narrow].map { e in
    ["case": e.name, "squashY": Double(e.squashY), "stretchX": Double(e.stretchX)]
}
let eyeAccessories: [[String: Any]] = [EyeStyle.shades, .heartShades, .starShades,
                                       .glasses, .monocle, .patch].map { ["case": $0.name] }

let eyeColors: [[String: Any]] = EyeColor.allCases.map { c in
    var d: [String: Any] = ["case": c.name]
    if c == .auto { d["note"] = "跟形象走 —— 用 palette 里那套的 eyeL / eyeR" }
    return d
}

let bibs: [[String: Any]] = BibStyle.allCases.map { ["case": $0.name] }

let ears: [[String: Any]] = EarStyle.allCases.map { e in
    ["case": e.name, "scaleW": Double(e.scaleW), "scaleH": Double(e.scaleH),
     "spread": Double(e.spread), "tipKX": Double(e.tipKX), "tipKY": Double(e.tipKY)]
}

let tails: [[String: Any]] = TailStyle.allCases.map { t in
    ["case": t.name,
     "spine": t.spine.map { [Double($0.0), Double($0.1)] },
     "halfWidth": ["base": Double(t.halfWidth.base),
                   "extra": Double(t.halfWidth.extra),
                   "power": Double(t.halfWidth.power)]]
}

let mouths: [[String: Any]] = MouthStyle.allCases.map { m in
    let g = m.geo
    return ["case": m.name,
            "philTop": Double(g.philTop), "lipY": Double(g.lipY), "philW": Double(g.philW),
            "spread": Double(g.spread), "drop": Double(g.drop),
            "c1x": Double(g.c1x), "c1y": Double(g.c1y),
            "c2x": Double(g.c2x), "c2y": Double(g.c2y), "lobeW": Double(g.lobeW),
            "hasLower": g.hasLower,
            "lowHalf": Double(g.lowHalf), "lowY": Double(g.lowY),
            "lowCx": Double(g.lowCx), "lowCy": Double(g.lowCy), "lowW": Double(g.lowW),
            "openWide": Double(g.openWide), "openDeep": Double(g.openDeep)]
}

// 表情：分两类。**外观状态**会改脸，**行为状态**只触发互动反馈。
// 这个区分是从验证里发现的（见 harness/tools/verify.swift 的 KNOWN_SAME）。
let appearanceStates = ["idle", "eat", "happy", "error", "hmm", "hungry",
                        "love", "wave", "sleepy", "curious", "worried", "lowbattery"]
let behaviorStates   = ["pet"]

let totalSlots = LOOKS.count + EyeStyle.allCases.count + EyeColor.allCases.count
    + BibStyle.allCases.count + EarStyle.allCases.count
    + TailStyle.allCases.count + MouthStyle.allCases.count + CAT_STATE_NAMES.count

let readmeDict: [String: Any] = [
    "what": "喵藏的形象参数快照，由 harness/tools/export_spec 从 main.swift 导出。",
    "direction": "单向：Swift 是真相，本文件是快照。改这里不会改变形象（那是下一步的改造）。",
    "rebuild": "./harness/tools/export_spec > harness/ip-spec.json",
    "verify": "./harness/tools/verify",
]

let canvasDict: [String: Any] = ["w": Double(CatView.canvasW), "h": Double(CatView.canvasH)]
let metaDict: [String: Any] = [
    "ip": "喵藏",
    "specVersion": 1,
    "totalSlots": totalSlots,
    "canvas": canvasDict,
]

let stateDict: [String: Any] = [
    "appearance": appearanceStates,
    "behavior": behaviorStates,
    "_note": "behavior 类不改变静态外观（只触发飘心/耳抖那类反馈），所以渲染上与待机相同。",
]

// ⚠️ 写成「先建空字典、再逐项塞」的形式，而不是一个巨大的嵌套字面量。
// 后者会让 Swift 的类型推断超时，报 "unable to type-check this expression in
// reasonable time" —— 字典里混了 [String: Any] 和各具体类型时特别容易踩。
var spec: [String: Any] = [:]
spec["_readme"] = readmeDict
spec["meta"] = metaDict
spec["palette"] = palette
spec["eyeShape"] = ["shapes": eyeShapes, "accessories": eyeAccessories] as [String: Any]
spec["eyeColor"] = eyeColors
spec["bib"] = bibs
spec["ear"] = ears
spec["tail"] = tails
spec["mouth"] = mouths
spec["state"] = stateDict

let opts: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
guard let data = try? JSONSerialization.data(withJSONObject: spec, options: opts),
      let text = String(data: data, encoding: .utf8) else {
    FileHandle.standardError.write("✗ 导出失败\n".data(using: .utf8)!)
    exit(1)
}
print(text)
FileHandle.standardError.write(
    "已导出 \(palette.count) 套配色 / \(eyeShapes.count + eyeAccessories.count) 种眼型 / \(eyeColors.count) 种瞳色 / \(tails.count) 款尾巴 / \(mouths.count) 款嘴形 / \(CAT_STATE_NAMES.count) 个表情\n"
        .data(using: .utf8)!)
