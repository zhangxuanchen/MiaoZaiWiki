// ═══════════════════════════════════════════════════════════════
//  make_cats —— 生成「猫猫天团」4 张竖版吸粉卡
//
//  用法：  ./harness/build/make_cats --out 发布/吸粉卡
//
//  为什么用这个工具渲、而不是拿现成的图来拼：
//    跟 make_promo 同一条理由 —— 卡上的猫**必须**是这套绘制代码真渲出来的。
//    用 AI 图或者概念稿拼，别人拿到项目一跑就对不上，等于骗人。
//
//  每张卡：逻辑 540×720，2x → 1080×1440（小红书标准竖版）
//
//  ⚠️ 这个文件跟 head.swift 一起编译，而 head.swift 里已经有 PINK / WHITE /
//     BLUE 这些全局常量 —— 本文件所有全局名一律加 MC_ 前缀，否则报
//     「invalid redeclaration」，而且报错位置会指向 head.swift，
//     看着像猫的绘制代码坏了（make_promo 踩过同一个坑）。
//
//  ⚠️ 围兜上印名字靠的是 `makeCat(name:)`，而 drawNameTag 只取 **前两个字**
//     （`String(name.prefix(2))`）—— 所以 4 只猫的名字都必须是 2 个字，
//     三个字会被悄悄截断（不报错，只是印出来少了字）。
// ═══════════════════════════════════════════════════════════════

import Cocoa

let MC_W: CGFloat = 540
let MC_H: CGFloat = 720
let MC_SCALE: CGFloat = 2                       // → 1080×1440

// ── 通用色 ──
let MC_INK   = NSColor(srgbRed: 0.180, green: 0.153, blue: 0.133, alpha: 1)   // 主文字
let MC_SOFT  = NSColor(srgbRed: 0.565, green: 0.514, blue: 0.455, alpha: 1)   // 次级文字
let MC_PAPER = NSColor.white

// ═══════════════════════════════════════════════════════════════
//  4 只猫的档案
//
//  look 索引对应 LOOKS（0 奶白 / 1 橘猫 / 2 蓝猫 / 3 樱花），
//  其余绘制参数一律留默认档 —— 用户要的是"用现成 4 套"，
//  所以除了围兜上的名字，形象一个像素都不动。
//
//  accent = 那只猫毛色的加深版，用来给卡片定调（徽章/分隔线/标签）。
//  4 张卡并排看时，主色调正好是 暖金 → 橘 → 蓝灰 → 藕粉，一眼分得开。
// ═══════════════════════════════════════════════════════════════
struct McCat {
    let no: Int
    let look: Int
    let name: String
    let traits: [String]
    let quote: String
    let state: String
    let bg: NSColor
    let accent: NSColor
}

let MC_CATS: [McCat] = [
    McCat(no: 1, look: 0, name: "奶盖",
          traits: ["温柔", "慢热", "爱睡觉"],
          quote: "天塌下来，\n也是先睡够再说。",
          state: "idle",
          bg:     NSColor(srgbRed: 0.984, green: 0.957, blue: 0.914, alpha: 1),
          accent: NSColor(srgbRed: 0.753, green: 0.541, blue: 0.243, alpha: 1)),

    McCat(no: 2, look: 1, name: "大橘",
          traits: ["干饭王", "社牛", "心很大"],
          quote: "你吃什么呢？\n分我一口好不好。",
          state: "eat",
          bg:     NSColor(srgbRed: 0.992, green: 0.945, blue: 0.890, alpha: 1),
          accent: NSColor(srgbRed: 0.824, green: 0.463, blue: 0.180, alpha: 1)),

    McCat(no: 3, look: 2, name: "蓝莓",
          traits: ["高冷", "傲娇", "话很少"],
          quote: "不是不理你，\n是懒得理你。",
          state: "hmm",
          bg:     NSColor(srgbRed: 0.933, green: 0.949, blue: 0.976, alpha: 1),
          accent: NSColor(srgbRed: 0.431, green: 0.510, blue: 0.659, alpha: 1)),

    // ⚠️ 这里**不能**用 "love"。CatState.love 渲出来是 XX 眼 + 吐舌（"被萌晕"的画法），
    //    缩略图里看着像爱心眼，放大到卡片尺寸就是一双叉、像眼睛坏了 ——
    //    配"爱撒娇·小公主"完全不对味。改用 "happy"：眯眼笑 + 飘心，才是甜的那一挂。
    McCat(no: 4, look: 3, name: "桃桃",
          traits: ["爱撒娇", "爱干净", "小公主"],
          quote: "今天也很可爱，\n明天也是。",
          state: "happy",
          bg:     NSColor(srgbRed: 0.988, green: 0.937, blue: 0.957, alpha: 1),
          accent: NSColor(srgbRed: 0.831, green: 0.475, blue: 0.561, alpha: 1)),
]

// MARK: - 量文字

func mcTextWidth(_ s: String, size: CGFloat, weight: NSFont.Weight = .semibold) -> CGFloat {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return (s as NSString).size(withAttributes: [.font: f]).width
}

// MARK: - 卡片画布

final class McCard {
    let rep: NSBitmapImageRep
    let ctx: NSGraphicsContext
    let file: String

    init(_ file: String, bg: NSColor) {
        self.file = file
        rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(MC_W * MC_SCALE),
            pixelsHigh: Int(MC_H * MC_SCALE),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: MC_W, height: MC_H)
        ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        bg.setFill()
        NSRect(x: 0, y: 0, width: MC_W, height: MC_H).fill()
    }

    /// 画文字。`top` = 距**卡片顶边**的距离（跟 mcCatRect 一个口径）。
    /// 位图上下文原点在左下，所以这里翻一下：y = H - top - h。
    /// ⚠️ 高度必须按**行数**算 —— 只给一行的高度会把多行文字裁掉（make_promo 踩过）。
    func text(_ s: String, x: CGFloat, top: CGFloat, size: CGFloat,
              bold: Bool = false, color: NSColor = MC_INK,
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
            .draw(in: NSRect(x: x, y: MC_H - top - h,
                             width: width > 0 ? width : MC_W - x * 2, height: h))
    }

    /// 圆。⚠️ 这里收的是**位图坐标**（原点左下），不是 top 口径。
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }

    /// 胶囊。`top` 口径同 text。
    func pill(_ s: String, x: CGFloat, top: CGFloat, h: CGFloat, w: CGFloat,
              fill: NSColor, stroke: NSColor? = nil, textColor: NSColor,
              size: CGFloat) {
        let r = NSRect(x: x, y: MC_H - top - h, width: w, height: h)
        let p = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
        fill.setFill(); p.fill()
        if let st = stroke { st.setStroke(); p.lineWidth = 1.2; p.stroke() }
        let ps = NSMutableParagraphStyle(); ps.alignment = .center
        let a: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: textColor, .paragraphStyle: ps]
        let th = size * 1.35
        NSAttributedString(string: s, attributes: a)
            .draw(in: NSRect(x: x, y: MC_H - top - h + (h - th) / 2, width: w, height: th))
    }

    func cat(_ img: NSImage, _ rect: NSRect) { img.draw(in: rect) }

    /// 渲一只猫（照抄 make_promo 的做法：shoot 出来再塞进 NSImage）
    func catImage(look: Int, state: String, name: String) -> NSImage {
        let v = makeCat(look: look, state: state, name: name)
        guard let s = shoot(v, scale: MC_SCALE) else { return NSImage(size: .zero) }
        let r = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: s.w, pixelsHigh: s.h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        r.size = NSSize(width: Double(s.w) / MC_SCALE, height: Double(s.h) / MC_SCALE)
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
        let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            // ⚠️ 不能吞掉错误 —— make_promo 早期用 `try?` 写过，结果打印"已导出"
            //    但文件根本不在。写入失败必须炸出来。
            print("✗ 写不进去 \(url.path)：\(error.localizedDescription)")
            return false
        }
        print("  ✓ \(url.lastPathComponent)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
        return true
    }
}

/// 猫在卡上的等比矩形（原生画布 186×205）。`top` 口径同 text。
func mcCatRect(_ x: CGFloat, top: CGFloat, w: CGFloat) -> NSRect {
    let h = w * CatView.canvasH / CatView.canvasW
    return NSRect(x: x, y: MC_H - top - h, width: w, height: h)
}

// ═══════════════════════════════════════════════════════════════
//  画一张卡
//
//  版式（4 张完全一致，只换色和内容 —— 成套的关键在"版式不动"）：
//
//      ┌──────────────────────┐
//      │            ╭───╮     │  ← 右上淡色大圆
//      │  [01/04]             │  ← 徽章
//      │                      │
//      │        [猫]          │  ← 围兜上印着自己的名字
//      │                      │
//      │        奶 盖          │  ← 名字
//      │       ─────          │  ← 分隔线
//      │   (温柔)(慢热)(爱睡觉) │  ← 性格标签
//      │                      │
//      │   「天塌下来，         │  ← 一句话人设
//      │     也是先睡够再说。」  │
//      │                      │
//      │   · 喵藏 · 桌面宠物 ·  │  ← 署名
//      └──────────────────────┘
// ═══════════════════════════════════════════════════════════════
@discardableResult
func drawCard(_ c: McCat, outdir: String) -> Bool {
    let card = McCard(String(format: "%02d_%@.png", c.no, c.name), bg: c.bg)

    // 1 · 背景装饰圆（先画，免得盖住猫）
    card.circle(MC_W + 6, MC_H - 78, 122, c.accent.withAlphaComponent(0.10))
    card.circle(34, 54, 84, c.accent.withAlphaComponent(0.07))

    // 2 · 顶部徽章：01 / 04
    let badge = String(format: "%02d / 04", c.no)
    let bw = mcTextWidth(badge, size: 13.5) + 30
    card.pill(badge, x: (MC_W - bw) / 2, top: 40, h: 30, w: bw,
              fill: c.accent, textColor: MC_PAPER, size: 13.5)

    // 3 · 猫（宽 318 → 高约 350）
    //     top 压在 72：猫的 canvas 顶部本身有一圈透明留白（约 15%），
    //     按 canvas 顶边对齐会显得上半张卡空荡荡。往下挪到猫头离徽章四五十像素
    //     的位置，视觉重量才落得住。
    let catW: CGFloat = 318
    let img = card.catImage(look: c.look, state: c.state, name: c.name)
    card.cat(img, mcCatRect((MC_W - catW) / 2, top: 72, w: catW))

    // 4 · 名字
    card.text(c.name, x: 40, top: 432, size: 44, bold: true, width: MC_W - 80)

    // 5 · 分隔线
    c.accent.setFill()
    NSRect(x: (MC_W - 56) / 2, y: MC_H - 512, width: 56, height: 2.5).fill()

    // 6 · 性格标签（白底 + accent 描边 + accent 字，居中排一行）
    let tagSize: CGFloat = 15, tagH: CGFloat = 31, tagGap: CGFloat = 9
    let tagW = c.traits.map { mcTextWidth($0, size: tagSize) + 30 }
    let totalTag = tagW.reduce(0, +) + tagGap * CGFloat(c.traits.count - 1)
    var tx = (MC_W - totalTag) / 2
    for (i, t) in c.traits.enumerated() {
        card.pill(t, x: tx, top: 528, h: tagH, w: tagW[i],
                  fill: MC_PAPER, stroke: c.accent.withAlphaComponent(0.55),
                  textColor: c.accent, size: tagSize)
        tx += tagW[i] + tagGap
    }

    // 7 · 一句话人设
    card.text(c.quote, x: 70, top: 598, size: 18, color: MC_INK,
              width: MC_W - 140, lineGap: 1.62)

    // 8 · 署名
    card.text("· 喵藏 · 桌面宠物 ·", x: 40, top: 680, size: 12.5,
              color: MC_SOFT, width: MC_W - 80)

    return card.save(outdir)
}

// ── 入口 ──
let mcOut = argValue("--out") ?? argValue("--outdir") ?? "发布/吸粉卡"

print("生成猫猫吸粉卡（用项目自己的绘制代码渲）…")
var mcOK = 0
for c in MC_CATS {
    // ⚠️ 逐张判返回值。save 失败时**不能**默默继续 —— 最后会打印
    //    "全部完成"，而实际少了几张（这种"看起来成功"的失败最难查）。
    if drawCard(c, outdir: mcOut) { mcOK += 1 }
}
if mcOK != MC_CATS.count {
    print("✗ 只成功 \(mcOK)/\(MC_CATS.count) 张 —— 别当成功")
    exit(1)
}
print("全部完成 → \(mcOut)/  （\(MC_CATS.count) 张 · 1080×1440）")
