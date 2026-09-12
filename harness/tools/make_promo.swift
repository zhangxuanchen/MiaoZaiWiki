// ═══════════════════════════════════════════════════════════════
//  make_promo —— 生成「小红书宣传图」
//
//  用法：  ./harness/build/make_promo --outdir 发布/配图
//
//  为什么用这个工具渲、而不是拿现成的图来拼：
//    宣传语是「装了这个 skill，你也能做出这样的猫」。所以图里的猫**必须**
//    真的是这套代码渲出来的 —— 用别的图（AI 生成的、概念稿）就是骗人，
//    而且用户拿到 skill 一跑会对不上，反而砸掉信任。
//
//  每张卡：逻辑 540×720，2x 输出 → 1080×1440（小红书标准竖版）
// ═══════════════════════════════════════════════════════════════

import Cocoa

let LW: CGFloat = 540, LH: CGFloat = 720      // 逻辑尺寸
let SCALE: CGFloat = 2                        // → 1080×1440

// ── 配色（跟项目里那份视觉语言保持一致）──
let PAPER = NSColor(srgbRed: 0.996, green: 0.976, blue: 0.957, alpha: 1)   // 暖米白
let CARD  = NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1)
let INK   = NSColor(srgbRed: 0.180, green: 0.153, blue: 0.133, alpha: 1)
let SOFT  = NSColor(srgbRed: 0.545, green: 0.494, blue: 0.435, alpha: 1)
let ACC   = NSColor(srgbRed: 0.937, green: 0.400, blue: 0.180, alpha: 1)   // 暖橙
let PINK  = NSColor(srgbRed: 0.988, green: 0.882, blue: 0.886, alpha: 1)

let STATE_CN: [String: String] = [
    "idle": "待机", "eat": "吃东西", "happy": "开心", "error": "出错",
    "hmm": "疑惑", "hungry": "饿了", "love": "爱心", "wave": "招手",
    "sleepy": "困了", "curious": "好奇", "worried": "担心",
    "lowbattery": "没电了", "pet": "被撸",
]

// MARK: - 画布

final class Card {
    let W: CGFloat, H: CGFloat
    let rep: NSBitmapImageRep
    let ctx: NSGraphicsContext
    let name: String

    init(name: String) {
        self.name = name
        W = LW; H = LH
        rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(LW * SCALE), pixelsHigh: Int(LH * SCALE),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: LW, height: LH)
        ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        PAPER.setFill()
        NSRect(x: 0, y: 0, width: LW, height: LH).fill()
    }

    /// 文字。`top` 是这一段文字的**顶边** y —— 高度按行数算，
    /// 只给一行的高度会把多行文字裁掉（踩过）。
    func text(_ s: String, _ x: CGFloat, top: CGFloat, size: CGFloat,
              bold: Bool = false, color: NSColor = INK,
              align: NSTextAlignment = .center, width: CGFloat = 0,
              lineGap: CGFloat = 1.42) {
        let lines = s.components(separatedBy: "\n").count
        let h = size * lineGap * CGFloat(lines) + 4
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        ps.lineSpacing = size * (lineGap - 1.0)
        let a: [NSAttributedString.Key: Any] = [
            .font: bold ? NSFont.systemFont(ofSize: size, weight: .heavy)
                        : NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color, .paragraphStyle: ps]
        NSAttributedString(string: s, attributes: a)
            .draw(in: NSRect(x: x, y: top - h, width: width > 0 ? width : W - x * 2, height: h))
    }

    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }

    /// 圆角白卡
    func panel(_ rect: NSRect, radius: CGFloat = 18, fill: NSColor = CARD) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// 把一只猫画进 rect
    func cat(_ img: NSImage, _ rect: NSRect) { img.draw(in: rect) }

    /// 渲一只猫
    func catImage(look: Int = 0, eye: Int = 0, eyeColor: Int = 0, bib: Int = 0,
                  ear: Int = 0, tail: Int = 0, mouth: Int = 0,
                  state: String = "idle") -> NSImage {
        let v = makeCat(look: look, eye: eye, eyeColor: eyeColor, bib: bib,
                        ear: ear, tail: tail, mouth: mouth, state: state, name: "")
        guard let s = shoot(v, scale: SCALE) else { return NSImage(size: .zero) }
        let r = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: s.w, pixelsHigh: s.h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        r.size = NSSize(width: Double(s.w) / SCALE, height: Double(s.h) / SCALE)
        s.px.withUnsafeBytes { memcpy(r.bitmapData!, $0.baseAddress!, s.px.count) }
        let im = NSImage(size: r.size)
        im.addRepresentation(r)
        return im
    }

    func save(_ dir: String) -> Bool {
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("✗ PNG 编码失败"); return false
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: dir),
                                                    withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            print("✗ 写不进去 \(url.path)：\(error.localizedDescription)"); return false
        }
        print("  ✓ \(url.lastPathComponent)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
        return true
    }
}

/// 猫在卡上的等比矩形（原生 186×205）
func catRect(_ x: CGFloat, top: CGFloat, w: CGFloat) -> NSRect {
    let h = w * CatView.canvasH / CatView.canvasW
    return NSRect(x: x, y: LH - top - h, width: w, height: h)
}

// ═══════════════════════════════════════════════════════════════
//  卡 1 · 封面
// ═══════════════════════════════════════════════════════════════
func cardCover() {
    let c = Card(name: "01_封面.png")
    c.circle(LW - 60, LH - 42, 92, PINK)
    c.circle(46, 96, 70, NSColor(srgbRed: 0.996, green: 0.937, blue: 0.890, alpha: 1))

    c.text("在 Mac 桌面上", LW / 2 - 200, top: 96, size: 30, color: SOFT, width: 400)
    c.text("养了只猫", LW / 2 - 200, top: 152, size: 60, bold: true, width: 400)
    c.text("而且是你自己做出来的", LW / 2 - 200, top: 206, size: 19, color: ACC, width: 400)

    // 四套配色并排
    let looks = [0, 1, 2, 3]
    let sheet = looks.map { c.catImage(look: $0, tail: 0) }
    let cw: CGFloat = 118, gap: CGFloat = 12
    let total = cw * 4 + gap * 3
    var x = (LW - total) / 2
    let top: CGFloat = 268
    for img in sheet {
        c.cat(img, catRect(x, top: top, w: cw))
        x += cw + gap
    }

    c.text("4 套配色 · 9 种眼型 · 18 种瞳色", LW / 2 - 210, top: 528,
           size: 16, color: SOFT, width: 420)
    c.text("5 款尾巴 · 5 款嘴形 · 13 个表情", LW / 2 - 210, top: 556,
           size: 16, color: SOFT, width: 420)

    c.text("一个 skill，一句话，一只猫", LW / 2 - 220, top: 618,
           size: 22, bold: true, color: INK, width: 440)
    c.text("macOS · 纯本地 · 开源可改", LW / 2 - 220, top: 650,
           size: 14, color: SOFT, width: 440)
    _ = c.save(outdir)
}

// ═══════════════════════════════════════════════════════════════
//  卡 2 · 表情墙（13 个）
// ═══════════════════════════════════════════════════════════════
func cardStates() {
    let c = Card(name: "02_表情.png")
    c.circle(58, LH - 52, 84, PINK)
    c.text("它会换 13 种表情", LW / 2 - 230, top: 80, size: 34, bold: true, width: 460)
    c.text("撸它、喂它、不理它，长得都不一样", LW / 2 - 230, top: 122,
           size: 15, color: SOFT, width: 460)

    let names = CAT_STATE_NAMES
    let cols = 4, cw: CGFloat = 122, gap: CGFloat = 8
    let total = CGFloat(cols) * cw + CGFloat(cols - 1) * gap
    let x0 = (LW - total) / 2
    let top0: CGFloat = 186
    let rowH: CGFloat = 168

    for (i, n) in names.enumerated() {
        let col = i % cols, row = i / cols
        let x = x0 + CGFloat(col) * (cw + gap)
        let yTop = top0 + CGFloat(row) * rowH
        // 白底圆角卡（最后一格留空就不画）
        c.panel(NSRect(x: x, y: LH - yTop - rowH + 22, width: cw, height: rowH - 26),
                radius: 16)
        let img = c.catImage(state: n)
        c.cat(img, catRect(x + 4, top: yTop + 2, w: cw - 8))
        c.text(STATE_CN[n] ?? n, x, top: yTop + rowH - 26, size: 14,
               bold: false, color: SOFT, width: cw)
    }
    _ = c.save(outdir)
}

// ═══════════════════════════════════════════════════════════════
//  卡 3 · 能换的东西
// ═══════════════════════════════════════════════════════════════
func cardParts() {
    let c = Card(name: "03_可换.png")
    c.circle(LW - 52, 108, 78, PINK)
    c.text("眼睛、尾巴、嘴都能换", LW / 2 - 240, top: 76, size: 30, bold: true, width: 480)
    c.text("跟 AI 说「尾巴换换看」，它出图，你挑一个", LW / 2 - 240, top: 116,
           size: 14, color: SOFT, width: 480)

    let rows: [(String, Int, [Int], String)] = [
        ("瞳色", 18, [0, 3, 7, 10, 13, 16], "eyeColor"),
        ("尾巴", TailStyle.allCases.count, Array(0..<TailStyle.allCases.count), "tail"),
        ("嘴形", MouthStyle.allCases.count, Array(0..<MouthStyle.allCases.count), "mouth"),
    ]
    var top: CGFloat = 176
    for (title, _, idxs, key) in rows {
        let cw: CGFloat = 74, gap: CGFloat = 6
        let rowW = CGFloat(idxs.count) * cw + CGFloat(idxs.count - 1) * gap
        let x0 = (LW + 96 - rowW) / 2
        c.text(title, 20, top: top - 6, size: 17, bold: true, align: .left, width: 70)
        for (i, v) in idxs.enumerated() {
            let img: NSImage
            switch key {
            case "eyeColor": img = c.catImage(eyeColor: v)
            case "tail":     img = c.catImage(tail: v)
            default:         img = c.catImage(mouth: v)
            }
            c.cat(img, catRect(x0 + CGFloat(i) * (cw + gap), top: top, w: cw))
        }
        top += 156
    }

    let ears = EarStyle.allCases.count
    c.text("还有 4 款耳朵 · 4 款肚兜 · 9 种眼型（含墨镜/单片镜/眼罩）", LW / 2 - 240,
           top: 668, size: 13, color: SOFT, width: 480)
    _ = c.save(outdir)
}

// ═══════════════════════════════════════════════════════════════
//  卡 4 · 三步
// ═══════════════════════════════════════════════════════════════
func cardSteps() {
    let c = Card(name: "04_三步.png")
    c.circle(52, LH - 44, 76, PINK)
    c.text("三步做出你自己的", LW / 2 - 240, top: 72, size: 30, bold: true, width: 480)

    let steps: [(String, String, String)] = [
        ("①", "装 skill", "把 pet-ip-studio 解压到\nAI 助手的技能目录"),
        ("②", "说一句话", "「做一只橘猫的\n桌面宠物」"),
        ("③", "看图挑一个", "它出对照图，\n你只负责选"),
    ]
    var top: CGFloat = 150
    for (num, title, desc) in steps {
        c.panel(NSRect(x: 40, y: LH - top - 142, width: LW - 80, height: 130), radius: 18)
        c.text(num, 60, top: top + 14, size: 40, bold: true, color: ACC,
               align: .left, width: 60)
        c.text(title, 122, top: top + 8, size: 22, bold: true, align: .left, width: 200)
        c.text(desc, 122, top: top + 66, size: 14, color: SOFT,
               align: .left, width: 340)
        top += 152
    }
    let img = c.catImage(look: 1)
    c.cat(img, catRect(LW / 2 - 62, top: top - 18, w: 124))
    _ = c.save(outdir)
}

// ═══════════════════════════════════════════════════════════════
//  卡 5 · 收尾
// ═══════════════════════════════════════════════════════════════
func cardEnd() {
    let c = Card(name: "05_收尾.png")
    c.circle(72, 132, 96, PINK)
    c.circle(LW - 66, LH - 66, 80, NSColor(srgbRed: 0.996, green: 0.937, blue: 0.890, alpha: 1))

    let imgs = [c.catImage(look: 0, ear: 1), c.catImage(look: 2, eye: 1),
                c.catImage(look: 3, tail: 4)]
    let cw: CGFloat = 128, gap: CGFloat = 10
    let total = cw * 3 + gap * 2
    var x = (LW - total) / 2
    for img in imgs {
        c.cat(img, catRect(x, top: 196, w: cw))
        x += cw + gap
    }

    c.text("做出来就是你自己的", LW / 2 - 230, top: 452,
           size: 30, bold: true, width: 460)
    c.text("改配色、改名字、改表情\n编译成 .app，双击就在桌面上养着", LW / 2 - 230, top: 500,
           size: 16, color: SOFT, width: 460, lineGap: 1.6)
    c.text("需要 macOS + 一行命令装编译工具\n其余什么都不用装", LW / 2 - 230, top: 586,
           size: 15, color: SOFT, width: 460, lineGap: 1.6)
    c.text("评论区聊 · 想要就说一声", LW / 2 - 230, top: 662,
           size: 18, bold: true, color: ACC, width: 460)
    _ = c.save(outdir)
}

// ── 入口 ──
let outdir = argValue("--out") ?? argValue("--outdir") ?? "发布/配图"

print("生成小红书宣传图（用项目自己的绘制代码渲）…")
cardCover()
cardStates()
cardParts()
cardSteps()
cardEnd()
print("全部完成 → \(outdir)/")
