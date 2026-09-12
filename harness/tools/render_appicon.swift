// ═══════════════════════════════════════════════════════════════
//  render_appicon —— 用项目自己的绘制代码渲「应用图标」候选
//
//  用法：  ./harness/build/render_appicon --out harness/out
//
//  为什么不再用 appicon_source.png（那张外部插画）：
//    ① 它只有 254×268，放进 1024 母版是 **2.5× 放大插值** —— 512/1024 那档发虚；
//    ② 它是**外部素材**（AI 生成），随包分发等于把一件说不清来历的东西一起发出去；
//    ③ 围兜上原本有字，抹掉之后按列插值会留下可见的痕迹（就是"花了"）。
//
//  自绘矢量猫一次解决三条：100% 自主、任意分辨率都锐利、围兜本来就能不印字。
//
//  ⚠️ 名字必须传空字符串：`makeCat(name:)` 的默认值是「测试」，
//     不显式传空的话，围兜上会印出"测试"两个字 —— 那正是头版图标的老问题。
// ═══════════════════════════════════════════════════════════════

import Cocoa

let CANVAS: CGFloat = 1024
let PLATE: CGFloat = 824          // Apple 的 1024 图标网格：圆角底板 824×824
let RADIUS: CGFloat = 184         // 824 × 0.2237
let INSET: CGFloat = 100          // (1024 - 824) / 2
let ART_BOX: CGFloat = 660        // 猫最多占多大（留出透气的边距）
let LOOK_NAMES = ["奶白", "橘猫", "蓝猫", "樱花"]

/// 渲一只猫（透明底、**不印名字**）
func renderCat(look: Int, scale: CGFloat) -> NSImage? {
    let v = makeCat(look: look, name: "")      // ← 空名字：围兜不印字
    guard let s = shoot(v, scale: scale) else { return nil }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: s.w, pixelsHigh: s.h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: Double(s.w) / scale, height: Double(s.h) / scale)
    s.px.withUnsafeBytes { memcpy(rep.bitmapData!, $0.baseAddress!, s.px.count) }
    let im = NSImage(size: rep.size)
    im.addRepresentation(rep)
    return im
}

/// 非透明像素的包围盒（y 从**顶部**算，跟 bitmapData 的行序一致）
func alphaBounds(_ rep: NSBitmapImageRep) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
    guard let bd = rep.bitmapData else { return nil }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    let bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
    var x0 = w, x1 = -1, y0 = h, y1 = -1
    for y in 0..<h {
        for x in 0..<w {
            if bd[y * bpr + x * spp + 3] > 8 {          // alpha 门槛
                if x < x0 { x0 = x }; if x > x1 { x1 = x }
                if y < y0 { y0 = y }; if y > y1 { y1 = y }
            }
        }
    }
    guard x1 > x0, y1 > y0 else { return nil }
    return (x0, y0, x1, y1)
}

/// 把某套配色渲成一张 1024 图标
func buildIcon(look: Int) -> NSBitmapImageRep? {
    guard let img = renderCat(look: look, scale: 4),
          let rep = img.representations.first as? NSBitmapImageRep,
          let b = alphaBounds(rep) else { return nil }

    let cw = b.x1 - b.x0 + 1, ch = b.y1 - b.y0 + 1
    let k = min(ART_BOX / CGFloat(cw), ART_BOX / CGFloat(ch))
    let aw = CGFloat(cw) * k, ah = CGFloat(ch) * k

    guard let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(CANVAS), pixelsHigh: Int(CANVAS),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    out.size = NSSize(width: CANVAS, height: CANVAS)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current?.imageInterpolation = .high

    // 1) 圆角底板：白底 + 极淡描边（正式白底图标都带这道边，否则在浅色窗口上会糊成一片）
    let plate = NSBezierPath(roundedRect: NSRect(x: INSET, y: INSET, width: PLATE, height: PLATE),
                            xRadius: RADIUS, yRadius: RADIUS)
    NSColor.white.setFill(); plate.fill()
    NSColor(calibratedRed: 0.882, green: 0.871, blue: 0.847, alpha: 1).setStroke()
    plate.lineWidth = 2; plate.stroke()

    // 2) 猫居中（按**抠出来的包围盒**居中，不是按渲染画布 —— 画布四周留白不均）
    // ⚠️ `from:` 用的是**图像坐标**（这里是 186×205），不是像素坐标（744×820）。
    //    第一版直接传了像素值，裁剪框整个落在图像外面 → 四张候选全是空板子，
    //    而且因为没画出任何东西，四张的字节数还完全一样（这反而成了线索）。
    let pxScale = CGFloat(rep.pixelsWide) / max(rep.size.width, 1)   // 像素 / 点，通常 = 4
    let from = NSRect(x: CGFloat(b.x0) / pxScale,
                      y: CGFloat(rep.pixelsHigh - 1 - b.y1) / pxScale,
                      width: CGFloat(cw) / pxScale,
                      height: CGFloat(ch) / pxScale)
    img.draw(in: NSRect(x: (CANVAS - aw) / 2, y: (CANVAS - ah) / 2, width: aw, height: ah),
             from: from, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    print(String(format: "  look %d %@：猫 %d×%d → 缩放 %.2f× 至 %.0f×%.0f",
                 look, LOOK_NAMES[look], cw, ch, k, aw, ah))
    return out
}

// ── 入口 ──
let outDir = argValue("--out") ?? argValue("--outdir") ?? "harness/out"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

print("用项目自己的绘制代码渲图标候选…")
var icons: [NSBitmapImageRep] = []
for look in 0..<LOOK_NAMES.count {
    guard let icon = buildIcon(look: look) else {
        print("✗ look \(look) 渲染失败"); exit(1)
    }
    icons.append(icon)
    guard let png = icon.representation(using: .png, properties: [:]) else {
        print("✗ PNG 编码失败"); exit(1)
    }
    let dst = "\(outDir)/appicon_look\(look)_\(LOOK_NAMES[look]).png"
    do { try png.write(to: URL(fileURLWithPath: dst)) }
    catch { print("✗ 写不进去 \(dst)：\(error.localizedDescription)"); exit(1) }
}

// ── 再拼一张 2×2 对照图，方便一眼挑 ──
let CELL: CGFloat = 440, GAP: CGFloat = 16
let boardW = CELL * 2 + GAP * 3
guard let board = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(boardW), pixelsHigh: Int(boardW),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
board.size = NSSize(width: boardW, height: boardW)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: board)
NSColor(calibratedRed: 0.965, green: 0.953, blue: 0.933, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: boardW, height: boardW).fill()
for (i, icon) in icons.enumerated() {
    let col = CGFloat(i % 2), row = CGFloat(i / 2)
    let x = GAP + col * (CELL + GAP)
    let y = boardW - GAP - (row + 1) * CELL - row * GAP      // 位图原点在左下
    let im = NSImage(size: NSSize(width: CANVAS, height: CANVAS))
    im.addRepresentation(icon)
    im.draw(in: NSRect(x: x, y: y, width: CELL, height: CELL))
}
NSGraphicsContext.restoreGraphicsState()
if let bp = board.representation(using: .png, properties: [:]) {
    let dst = "\(outDir)/appicon_候选对照.png"
    do { try bp.write(to: URL(fileURLWithPath: dst)); print("✓ \(dst)") }
    catch { print("✗ 写不进去 \(dst)：\(error.localizedDescription)"); exit(1) }
}
print("完成 → \(outDir)/")
