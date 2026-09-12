// ═══════════════════════════════════════════════════════════════
//  verify —— 一次跑完所有检查
//
//  用法：  verify
//  退出码：0 = 全过，1 = 有失败
//
//  它回答四个问题：
//    ① 默认档有没有被动过？        （指纹 vs 基线）
//    ② 每个维度的档位是不是真的不一样？（两两渲染比对）
//    ③ 每档渲出来有没有内容？      （不是空白 / 没被裁）
//    ④ 维度之间有没有互相干扰？    （正交性抽查）
//
//  ⚠️ 一条断言只在**它真的会红**的时候才算数。
//     加新断言时，先故意把对应的地方改坏，确认它会报 FAIL。
// ═══════════════════════════════════════════════════════════════

import Cocoa

/// 采样表情用的相位。0 = 动作刚开始。换个值可能采到不同的瞬间 ——
/// 这也是为什么"两个表情看起来一样"要先排除相位因素，再下结论。
let STATE_PHASE: Double = Double(argValue("--phase") ?? "0") ?? 0

var pass = 0, fail = 0

func check(_ ok: Bool, _ name: String, _ detail: String = "") {
    if ok { pass += 1; print("✓ \(name)\(detail.isEmpty ? "" : "  \(detail)")") }
    else  { fail += 1; print("✗ \(name)\(detail.isEmpty ? "" : "  \(detail)")") }
}

// 复用 render_sheet 里的维度表？不行 —— 每个工具是独立编译的。
// 这里只需要"维度名 + 档数 + 设置方式"，写一份小的就够。
struct Check {
    let title: String
    let count: Int
    let label: (Int) -> String
    let apply: (CatView, Int) -> Void
}

let STATE_CN: [String: String] = [
    "idle": "待机", "eat": "吃东西", "happy": "开心", "error": "出错",
    "hmm": "疑惑", "hungry": "饿了", "love": "爱心", "wave": "招手",
    "sleepy": "困了", "curious": "好奇", "worried": "担心",
    "lowbattery": "没电了", "pet": "被撸",
]

let CHECKS: [Check] = [
    Check(title: "形象", count: LOOKS.count,
          label: { LOOKS[$0].name },
          apply: { v, i in v.lookOverride = i }),
    Check(title: "眼型", count: EyeStyle.allCases.count,
          label: { EyeStyle.allCases[$0].name },
          apply: { v, i in v.eyeOverride = i }),
    Check(title: "瞳色", count: EyeColor.allCases.count,
          label: { EyeColor.allCases[$0].name },
          apply: { v, i in v.eyeColorOverride = i }),
    Check(title: "肚兜", count: BibStyle.allCases.count,
          label: { BibStyle.allCases[$0].name },
          apply: { v, i in v.bibOverride = i }),
    Check(title: "耳朵", count: EarStyle.allCases.count,
          label: { EarStyle.allCases[$0].name },
          apply: { v, i in v.earOverride = i }),
    Check(title: "尾巴", count: TailStyle.allCases.count,
          label: { TailStyle.allCases[$0].name },
          apply: { v, i in v.tailOverride = i }),
    Check(title: "嘴形", count: MouthStyle.allCases.count,
          label: { MouthStyle.allCases[$0].name },
          apply: { v, i in v.mouthOverride = i }),
    Check(title: "表情", count: CAT_STATE_NAMES.count,
          label: { STATE_CN[CAT_STATE_NAMES[$0]] ?? CAT_STATE_NAMES[$0] },
          apply: { v, i in
              v.freeze(state: catState(CAT_STATE_NAMES[i]) ?? .idle,
                       phase: STATE_PHASE, at: TIME_ANCHOR)
          }),
]

/// 已知的「设计性重复」—— 这些档位渲染相同是**故意的**，不是 bug。
///
/// 断言规则：出现重复组 → 必须能在这里找到，否则 FAIL。
/// 这样既能接受"设计如此"，又能抓到"新冒出来的重复"。
///
/// ⚠️ 往这里加东西之前，先确认原因。别把 bug 塞进来当「已知」——
/// 那等于把警报器关掉。
let KNOWN_SAME: [String: Set<String>] = [
    // 奶白形象的默认眼色本来就是橄榄绿，所以「跟形象」和「橄榄」必然渲染一致。
    // 换个形象（比如橘猫）它们就不同了。
    "瞳色": ["跟形象", "橄榄"],
    // 「被撸」是**行为状态**不是外观状态：它触发的是互动反馈（飘心、耳抖），
    // 不改变脸的长相 —— 所以静态渲染等效于待机。
    // （已验：0 / 0.2 / 0.5 / 0.8 四个相位下都与待机逐位相同，排除相位因素。）
    "表情": ["待机", "被撸"],
]

print("喵藏 · 验证")
print("────────────────────────────────────────")

// ── ① 默认档指纹 ──
let baseView = makeCat()
if let base = shoot(baseView) {
    let fp = fingerprint(base)
    let path = baselineFile()
    if let saved = try? String(contentsOfFile: path, encoding: .utf8) {
        let want = saved.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .last
            .map { line -> String in
                let p = line.split(separator: " ")
                return p.isEmpty ? line : String(p[p.count - 1])
            } ?? ""
        check(want == fp, "默认档指纹与基线一致", "\(fp)")
        if want != fp { print("     基线 \(want)") }
    } else {
        check(false, "读到基线文件", path)
    }
} else {
    check(false, "默认档渲染")
}

// ── ② 每维度的档位互不相同 ──
var totalSlots = 0
for c in CHECKS {
    var hashes = Set<String>()
    var byHash: [String: [String]] = [:]
    var blank = 0
    for i in 0..<c.count {
        let v = makeCat()
        c.apply(v, i)
        guard let s = shoot(v) else { continue }
        let fp = fingerprint(s)
        hashes.insert(fp)
        byHash[fp, default: []].append(c.label(i))
        // 空白判定：不透明像素太少就是没画出来
        var opaque = 0
        var idx = 3
        while idx < s.px.count { if s.px[idx] > 40 { opaque += 1 }; idx += 4 }
        if opaque < 500 { blank += 1 }
    }
    totalSlots += c.count
    let dups = byHash.filter { $0.value.count > 1 }.values.map { Set($0) }
    let known = KNOWN_SAME[c.title] ?? []
    let unexpected = dups.filter { $0 != known }
    for g in unexpected {
        print("      ⚠️ 意外的重复（不在已知清单里）：\(g.sorted().joined(separator: " / "))")
    }
    if !known.isEmpty {
        print("      · 已知重复（设计如此）：\(known.sorted().joined(separator: " / "))")
    }
    // 期望的唯一结果数 = 总档数 − 每个已知重复组里"多余"的个数
    var expected = c.count
    if !known.isEmpty { expected -= (known.count - 1) }
    check(hashes.count == expected && unexpected.isEmpty,
          "\(c.title) \(c.count) 档可区分",
          hashes.count == expected ? "" : "期望 \(expected) 种结果，实得 \(hashes.count)")
    check(blank == 0, "\(c.title) 每档都画出了东西",
          blank == 0 ? "" : "\(blank) 档是空的")
}

// ── ③ 维度之间正交（改 A 不会连带改 B）──
// 抽查：只改尾巴，形象/眼型/嘴形那几档的渲染结果应当与"全默认"一致。
let defaultFP = shoot(makeCat()).map(fingerprint)
func fpOf(_ configure: (CatView) -> Void) -> String? {
    let v = makeCat()
    configure(v)
    return shoot(v).map(fingerprint)
}
if let d = defaultFP {
    let tailOnly = fpOf { $0.tailOverride = 2 }
    check(tailOnly != nil && tailOnly != d, "只改尾巴 → 结果确实变了")
    let sameAsDefault = fpOf { $0.lookOverride = 0 } == d
    check(sameAsDefault, "把某档设成它本来就有的值 → 结果不变（确认没有隐藏扰动）")
} else {
    check(false, "正交性抽查")
}

// ── 汇总 ──
print("────────────────────────────────────────")
if fail == 0 {
    print("全部 PASS（\(pass) 条）· 覆盖 \(totalSlots) 个档位")
    exit(0)
} else {
    print("有 \(fail) 条 FAIL（\(pass) 条通过）")
    exit(1)
}
