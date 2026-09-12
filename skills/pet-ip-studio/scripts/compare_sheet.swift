// ═══════════════════════════════════════════════════════════════
//  compare_sheet —— 把 N 张图拼成一张对照图
//
//  这是「看图选一个」这个循环的物理载体：
//  AI 出候选 → 拼成一张图 → 人一眼看完 → 选一个。
//  出成一张图（而不是发 N 张）很重要 —— 人比较差异靠的是"并排"，
//  分开看只能靠记忆，质量差一个档。
//
//  编译： swiftc -O -o compare_sheet compare_sheet.swift
//  用法： ./compare_sheet <主标题> <输出路径> <图:说明> [<图:说明> ...]
//
//  例：   ./compare_sheet "五款尾巴" out.png \
//             a.png:"上翘（默认）" b.png:"卷尾" c.png:"长尾"
// ═══════════════════════════════════════════════════════════════

import Cocoa

setvbuf(stdout, nil, _IONBF, 0)
_ = NSApplication.shared

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else {
    print("用法： compare_sheet <主标题> <输出路径> <图:说明> [<图:说明> ...]")
    exit(1)
}

let mainTitle = args[0]
let outPath   = args[1]
let cells: [(path: String, label: String)] = args.dropFirst(2).map { spec in
    let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
}

// 载入图片，拿不到就跳过（宁缺勿崩）
let images: [(img: NSImage, label: String)] = cells.compactMap { c in
    guard let img = NSImage(contentsOfFile: c.path) else {
        print("  ! 读不到 \(c.path)，跳过")
        return nil
    }
    return (img, c.label)
}
guard !images.isEmpty else { print("没有可用图片"); exit(1) }

// ── 排版 ──
let cols      = images.count <= 3 ? images.count : 2
let pad: CGFloat     = 36
let gapX: CGFloat    = 26
let gapY: CGFloat    = 22
let labelH: CGFloat  = 70
let titleH: CGFloat  = 92
let footerH: CGFloat = 54

let cellW = images.map { $0.img.size.width }.max()!
let cellH = images.map { $0.img.size.height }.max()!
let rows  = Int(ceil(Double(images.count) / Double(cols)))

let W = pad * 2 + CGFloat(cols) * cellW + CGFloat(cols - 1) * gapX
let H = pad * 2 + titleH + CGFloat(rows) * (cellH + labelH) + CGFloat(rows - 1) * gapY + footerH

// 2x 输出。源图的像素尺寸通常是逻辑尺寸的两倍（Retina 渲出来的），
// 按 1x 画等于把分辨率砍掉一半 —— 发出去一眼就能看出糊。
let SCALE: CGFloat = 2
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W * SCALE), pixelsHigh: Int(H * SCALE),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 浅色底 —— 跟宿主主题一致，也方便直接发出去
NSColor(srgbRed: 0.992, green: 0.984, blue: 0.973, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

/// `top` = 这一段文字**顶边**的 y。
/// 高度按行数算 —— 给一行的高度，多行文字只会画出一行、其余被裁掉（踩过）。
func draw(_ s: String, x: CGFloat, top: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor, width: CGFloat = 0) {
    let lines = s.components(separatedBy: "\n").count
    let h = size * 1.40 * CGFloat(lines)
    NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color])
        .draw(in: NSRect(x: x, y: top - h, width: width > 0 ? width : W - x - pad, height: h))
}

let INK   = NSColor(srgbRed: 0.17, green: 0.15, blue: 0.13, alpha: 1)
let GREY  = NSColor(srgbRed: 0.54, green: 0.51, blue: 0.47, alpha: 1)
let ACC   = NSColor(srgbRed: 0.910, green: 0.384, blue: 0.173, alpha: 1)

// ── 标题 ──
draw(mainTitle, x: pad, top: H - pad + 4, size: 26, weight: .semibold, color: INK)
ACC.setFill()
NSRect(x: pad, y: H - pad - 54, width: 64, height: 4).fill()

// ── 网格 ──
var top = H - pad - titleH
for (i, item) in images.enumerated() {
    let col = i % cols
    let row = i / cols
    let x = pad + CGFloat(col) * (cellW + gapX)
    let y = top - CGFloat(row + 1) * cellH - CGFloat(row) * (labelH + gapY)

    // 图片按格子居中（尺寸不一时不至于歪）
    let iw = item.img.size.width, ih = item.img.size.height
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.imageInterpolation = .high
    item.img.draw(in: NSRect(x: x + (cellW - iw) / 2, y: y + (cellH - ih) / 2,
                             width: iw, height: ih))
    NSGraphicsContext.restoreGraphicsState()

    // 说明条
    let labelY = y - labelH
    if !item.label.isEmpty {
        let isDefault = item.label.contains("默认")
        draw(item.label, x: x + 4, top: labelY + 48,
             size: 17, weight: isDefault ? .semibold : .regular,
             color: isDefault ? ACC : INK, width: cellW)
    }
}

// ── 页脚 ──
let footerTop = pad + footerH - 18
NSColor(srgbRed: 0.878, green: 0.855, blue: 0.820, alpha: 1).setFill()
NSRect(x: pad, y: footerTop + 6, width: W - pad * 2, height: 1).fill()
draw("同一份绘制代码，只改了四个数字", x: pad, top: footerTop - 4, size: 15, color: GREY)

NSGraphicsContext.restoreGraphicsState()

// ── 输出 ──
guard let png = rep.representation(using: .png, properties: [:]) else {
    print("导出失败"); exit(1)
}
try? png.write(to: URL(fileURLWithPath: outPath))
print("已导出 \(outPath)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
