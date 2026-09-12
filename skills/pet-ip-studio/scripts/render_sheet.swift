// ═══════════════════════════════════════════════════════════════
//  render_sheet —— 把某个维度的所有档位渲成一张并排对照图
//
//  这是「看图选一个」这个循环的物理载体：
//    你说「尾巴换换看」→ 它渲出 5 款并排 → 你看一眼 → 说「第 3 个」
//
//  为什么必须**并排成一张**：人比较差异靠的是"同屏对照"，
//  分开发 5 张图只能靠记忆比对，质量差一个档。
//
//  用法：
//    render_sheet --dim tail  --out out/tails.png
//    render_sheet --dim state --out out/faces.png
//    render_sheet --all       --outdir out/
//    render_sheet --dim eye --cols 5 --base-look 1
// ═══════════════════════════════════════════════════════════════

import Cocoa

// ── 维度表 ──
// 每个维度知道三件事：有几档、每档叫什么、怎么把这一档套到视图上。
// 加新维度 = 在这里加一行。
struct Dim {
    let key: String
    let title: String
    let unit: String
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

let DIMS: [Dim] = [
    Dim(key: "look", title: "形象", unit: "套", count: LOOKS.count,
        label: { LOOKS[$0].name },
        apply: { v, i in v.lookOverride = i }),
    Dim(key: "eye", title: "眼型", unit: "款", count: EyeStyle.allCases.count,
        label: { EyeStyle.allCases[$0].name },
        apply: { v, i in v.eyeOverride = i }),
    Dim(key: "eyeColor", title: "瞳色", unit: "款", count: EyeColor.allCases.count,
        label: { EyeColor.allCases[$0].name },
        apply: { v, i in v.eyeColorOverride = i }),
    Dim(key: "bib", title: "肚兜", unit: "款", count: BibStyle.allCases.count,
        label: { BibStyle.allCases[$0].name },
        apply: { v, i in v.bibOverride = i }),
    Dim(key: "ear", title: "耳朵", unit: "款", count: EarStyle.allCases.count,
        label: { EarStyle.allCases[$0].name },
        apply: { v, i in v.earOverride = i }),
    Dim(key: "tail", title: "尾巴", unit: "款", count: TailStyle.allCases.count,
        label: { TailStyle.allCases[$0].name },
        apply: { v, i in v.tailOverride = i }),
    Dim(key: "mouth", title: "嘴形", unit: "款", count: MouthStyle.allCases.count,
        label: { MouthStyle.allCases[$0].name },
        apply: { v, i in v.mouthOverride = i }),
    Dim(key: "state", title: "表情", unit: "种", count: CAT_STATE_NAMES.count,
        label: { STATE_CN[CAT_STATE_NAMES[$0]] ?? CAT_STATE_NAMES[$0] },
        apply: { v, i in
            v.freeze(state: catState(CAT_STATE_NAMES[i]) ?? .idle,
                     phase: STATE_PHASE, at: TIME_ANCHOR)
        }),
]

// ── 参数 ──
let baseLook = Int(argValue("--base-look") ?? "0") ?? 0
let scale: CGFloat = CGFloat(Double(argValue("--scale") ?? "2") ?? 2)
/// 表情采样相位。0 = 动作刚开始。
let STATE_PHASE: Double = Double(argValue("--phase") ?? "0") ?? 0

func makeSlot(_ dim: Dim, _ i: Int) -> CatView {
    let v = makeCat(look: baseLook)
    dim.apply(v, i)
    return v
}

// ── 出图 ──
func imageFrom(_ s: Shot) -> NSImage? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: s.w, pixelsHigh: s.h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: Double(s.w) / scale, height: Double(s.h) / scale)
    s.px.withUnsafeBytes { memcpy(rep.bitmapData!, $0.baseAddress!, s.px.count) }
    let img = NSImage(size: rep.size)
    img.addRepresentation(rep)
    return img
}

/// 渲一张对照图。返回nil = 失败。
func sheet(_ dim: Dim, cols colsArg: Int?, out: String) -> Bool {
    let n = dim.count
    let cols = max(1, min(colsArg ?? (n <= 5 ? n : (n <= 8 ? 4 : 6)), n))
    let rows = (n + cols - 1) / cols

    // 渲每一档
    var cells: [(NSImage, String)] = []
    for i in 0..<n {
        let v = makeSlot(dim, i)
        guard let s = shoot(v, scale: scale), let img = imageFrom(s) else { continue }
        cells.append((img, dim.label(i)))
    }
    guard !cells.isEmpty else { print("✗ 一档都没渲出来"); return false }

    // 排版
    let cw = CatView.canvasW, ch = CatView.canvasH
    let pad: CGFloat = 34, gap: CGFloat = 16, labelH: CGFloat = 34, titleH: CGFloat = 76
    let W = pad * 2 + CGFloat(cols) * cw + CGFloat(cols - 1) * gap
    let H = pad * 2 + titleH + CGFloat(rows) * (ch + labelH) + CGFloat(rows - 1) * gap + 34

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
    rep.size = NSSize(width: W, height: H)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let INK   = NSColor(srgbRed: 0.17, green: 0.15, blue: 0.13, alpha: 1)
    let GREY  = NSColor(srgbRed: 0.54, green: 0.51, blue: 0.47, alpha: 1)
    let ACC   = NSColor(srgbRed: 0.910, green: 0.384, blue: 0.173, alpha: 1)
    NSColor(srgbRed: 0.992, green: 0.984, blue: 0.973, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    func text(_ s: String, x: CGFloat, top: CGFloat, size: CGFloat,
              weight: NSFont.Weight = .regular, color: NSColor, width: CGFloat = 0) {
        let lines = s.components(separatedBy: "\n").count
        let h = size * 1.40 * CGFloat(lines)
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: ps])
            .draw(in: NSRect(x: x, y: top - h, width: width > 0 ? width : W - x - pad, height: h))
    }

    text("\(dim.title) · \(n) \(dim.unit)", x: pad, top: H - pad, size: 22,
         weight: .semibold, color: INK, width: W - pad * 2)
    ACC.setFill()
    NSRect(x: W / 2 - 30, y: H - pad - 40, width: 60, height: 3).fill()

    var top = H - pad - titleH
    NSGraphicsContext.current?.imageInterpolation = .high
    for (i, cell) in cells.enumerated() {
        let col = i % cols, row = i / cols
        let x = pad + CGFloat(col) * (cw + gap)
        let y = top - CGFloat(row + 1) * ch - CGFloat(row) * (labelH + gap)
        cell.0.draw(in: NSRect(x: x, y: y, width: cw, height: ch))
        text(cell.1, x: x, top: y - 10, size: 14, color: INK, width: cw)
    }

    text("同一份绘制代码 · 只差这一个参数", x: pad, top: pad + 18, size: 12,
         color: GREY, width: W - pad * 2)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("✗ PNG 编码失败")
        return false
    }
    // ⚠️ 别用 `try?` —— 它会把「目录不存在 / 没权限」这类写入失败静默吞掉，
    // 工具照样打印「已导出」，而文件根本没生成（踩过：以为出了图，去读发现没有）。
    let url = URL(fileURLWithPath: out)
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
    } catch {
        print("✗ 写不进去 \(out)：\(error.localizedDescription)")
        return false
    }
    print("已导出 \(out)  \(rep.pixelsWide)×\(rep.pixelsHigh)  （\(n) \(dim.unit)）")
    return true
}

// ── 入口 ──
let colsArg = Int(argValue("--cols") ?? "")

if hasFlag("--all") {
    let dir = argValue("--outdir") ?? "harness/out"
    do {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    } catch {
        print("✗ 建不了目录 \(dir)：\(error.localizedDescription)")
        exit(1)
    }
    var ok = 0
    for d in DIMS where sheet(d, cols: colsArg, out: "\(dir)/\(d.key).png") { ok += 1 }
    print("全部完成：\(ok)/\(DIMS.count) 张")
    exit(ok == DIMS.count ? 0 : 1)
}

guard let key = argValue("--dim") else {
    print("用法： render_sheet --dim <维度> --out <路径>")
    print("       render_sheet --all --outdir <目录>")
    print("  维度： \(DIMS.map { $0.key }.joined(separator: " · "))")
    exit(1)
}
guard let dim = DIMS.first(where: { $0.key == key }) else {
    print("✗ 不认识的维度：\(key)")
    print("  可用： \(DIMS.map { $0.key }.joined(separator: " · "))")
    exit(1)
}
guard let out = argValue("--out") else {
    print("✗ 要指定 --out <路径>")
    exit(1)
}
exit(sheet(dim, cols: colsArg, out: out) ? 0 : 1)
