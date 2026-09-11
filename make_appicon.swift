// make_appicon.swift —— 把 appicon_source.png 合成一张 1024×1024 的 macOS 应用图标母版
//
//   swiftc -O -o /tmp/mkicon make_appicon.swift && /tmp/mkicon
//
// 为什么不直接把原图塞进 .icns：那张图是 254×268、**纯白底、满幅不透明**，
// 直接当图标会是"一个硬边白方块"，跟系统里其它图标完全不是一个长相。macOS 的图标规范是：
//
//   画布 1024×1024（四周 100px 是透明的）
//   圆角底板（squircle）824×824 居中，圆角半径 ≈ 824 × 0.2237 ≈ 184
//
// 所以这里做三件事：抠掉原图四周的纯白 → 等比放大 → 居中摆进白底圆角板里。
// 底板用**白底 + 一圈极淡的描边**：白底图标（像"预览""文本编辑"那样）在浅色窗口上
// 会跟背景糊在一起，Apple 自己的白底图标都带这道边。

import Foundation
import Cocoa
setvbuf(stdout, nil, _IONBF, 0)
_ = NSApplication.shared

// 源码里不要用 argv[0] 推目录 —— 那是**可执行文件**的路径（编译到 /tmp 就跑偏了）。
// 默认用当前工作目录，也可以显式传：/tmp/mkicon /path/to/catcollector
let here = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
let src = "\(here)/appicon_source.png"
let dst = "\(here)/appicon.png"

let CANVAS: CGFloat = 1024
let PLATE: CGFloat = 824            // 圆角底板边长（Apple 的 1024 图标网格）
let RADIUS: CGFloat = 184           // 824 × 0.2237
let INSET: CGFloat = 100            // (1024 - 824) / 2
let ART_BOX: CGFloat = 660          // 猫最多占多大（留出透气的边距）

guard let img = NSImage(contentsOfFile: src),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("读不到 \(src)"); exit(1)
}
let w = rep.pixelsWide, h = rep.pixelsHigh

/// 抠出**不是纯白**的那块（原图四周是白底，猫没有顶到边）
var bx0 = w, bx1 = -1, by0 = h, by1 = -1
for y in 0..<h {
    for x in 0..<w {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let white = c.redComponent > 0.94 && c.greenComponent > 0.94 && c.blueComponent > 0.94
        if !white {
            bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y)
        }
    }
}
guard bx1 > bx0, by1 > by0 else { print("整张图都是白的？"); exit(1) }
let cw = bx1 - bx0 + 1, ch = by1 - by0 + 1
print("原图 \(w)×\(h)；抠掉白边后 \(cw)×\(ch)  左\(bx0) 上\(by0)")

// 等比缩放到 ART_BOX 里
let k = min(ART_BOX / CGFloat(cw), ART_BOX / CGFloat(ch))
let aw = CGFloat(cw) * k, ah = CGFloat(ch) * k
print(String(format: "放进 %0.0fpt 的内容区 → 缩放 %.2f×，实际 %.0f×%.0f", ART_BOX, k, aw, ah))

guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CANVAS),
                                 pixelsHigh: Int(CANVAS), bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                 bitsPerPixel: 0) else { exit(1) }
out.size = NSSize(width: CANVAS, height: CANVAS)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSGraphicsContext.current?.imageInterpolation = .high

// 1) 圆角底板：白底 + 极淡描边
let plate = NSBezierPath(roundedRect: NSRect(x: INSET, y: INSET, width: PLATE, height: PLATE),
                         xRadius: RADIUS, yRadius: RADIUS)
NSColor.white.setFill(); plate.fill()
NSColor(calibratedRed: 0.882, green: 0.871, blue: 0.847, alpha: 1).setStroke()
plate.lineWidth = 2; plate.stroke()

// 2) 猫：居中（按抠出来的那块居中，而不是按原画布 —— 原画布四周留白不均）
let art = NSImage(data: tiff)!
let artSize = NSSize(width: CGFloat(w), height: CGFloat(h))
let from = NSRect(x: CGFloat(bx0), y: CGFloat(h - 1 - by1),   // NSImage 的 y 从下往上
                  width: CGFloat(cw), height: CGFloat(ch))
art.draw(in: NSRect(x: (CANVAS - aw) / 2, y: (CANVAS - ah) / 2, width: aw, height: ah),
         from: from, operation: .sourceOver, fraction: 1)
_ = artSize
NSGraphicsContext.restoreGraphicsState()

guard let png = out.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: dst))
print("已写出 \(dst)  \(Int(CANVAS))×\(Int(CANVAS))  \(png.count) 字节")
