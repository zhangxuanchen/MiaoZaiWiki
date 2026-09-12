import Foundation
import Cocoa
setvbuf(stdout, nil, _IONBF, 0)
_ = NSApplication.shared
let dir = (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/check.iconset") + "/"
func load(_ f: String) -> NSImage { NSImage(contentsOfFile: dir + f)! }

let pad: CGFloat = 22
let hero: CGFloat = 256
let stripSizes: [CGFloat] = [16, 32, 64, 128]
let cellW: CGFloat = 92, cellGap: CGFloat = 8
let stripH = stripSizes.max()! + 34
let stripsW = cellW * CGFloat(stripSizes.count) + cellGap * CGFloat(stripSizes.count - 1)
// ⚠️ 右边文字区的宽度 = W - (pad + hero + 24) - pad，这里必须留够 ——
//    原值 hero + 260 只够 19 个中文字，说明文字一长就被**静默裁掉**（尾巴看不见）。
let W = pad * 2 + max(hero + 460, stripsW)
let H = pad * 2 + 54 + (hero + 34) + 46 + (stripH + 30) * 2

let canvas = NSImage(size: NSSize(width: W, height: H))
canvas.lockFocus()
NSColor(calibratedWhite: 0.22, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ sz: CGFloat, bold: Bool = false,
          grey: CGFloat = 1, anchor: NSTextAlignment = .left, wide: CGFloat = 0) {
    let ps = NSMutableParagraphStyle(); ps.alignment = anchor
    let a: [NSAttributedString.Key: Any] = [
        .font: bold ? NSFont.boldSystemFont(ofSize: sz) : NSFont.systemFont(ofSize: sz),
        .foregroundColor: NSColor(calibratedWhite: grey, alpha: 1), .paragraphStyle: ps]
    NSAttributedString(string: s, attributes: a)
        .draw(in: NSRect(x: x, y: y, width: wide > 0 ? wide : W - x - pad, height: sz + 6))
}
var top = H - pad
text("应用图标 · 各尺寸实际渲染", pad, top - 20, 16, bold: true)
text("左上：1024 母版缩到 256。下面两条是 16/32/64/128 的 1:1 实拍，浅色/深色背景各一条。",
     pad, top - 42, 11.5, grey: 0.78)
top -= 54
load("icon_256x256@2x.png").draw(in: NSRect(x: pad, y: top - hero, width: hero, height: hero))
text("256pt", pad, top - hero - 20, 11, grey: 0.7)
text("母版是 1024×1024：透明画布 + 824 的白色圆角底板（圆角 184）+ 极淡的一圈描边。",
     pad + hero + 24, top - 26, 12, grey: 0.88)
text("猫由项目自己的绘制代码渲出（矢量），摆在底板正中间。", pad + hero + 24, top - 48, 12, grey: 0.88)
text("好处是任意尺寸都锐利 —— 不再有「外部小图放大插值」带来的柔边，", pad + hero + 24, top - 70, 12, grey: 0.88)
text("而且整个图标 100% 自主，不含任何外来源素材。", pad + hero + 24, top - 92, 12, grey: 0.88)
top -= hero + 34 + 30
for (name, bg, fg) in [("浅色背景（Finder 白底窗口）", NSColor(calibratedWhite: 0.97, alpha: 1), NSColor.darkGray),
                       ("深色背景（深色模式 / 深色壁纸）", NSColor(calibratedWhite: 0.13, alpha: 1), NSColor.lightGray)] {
    text(name, pad, top + 6, 11.5, bold: true, grey: 0.9)
    bg.setFill(); NSRect(x: pad, y: top - stripH, width: W - pad * 2, height: stripH).fill()
    let b = NSBezierPath(rect: NSRect(x: pad, y: top - stripH, width: W - pad * 2, height: stripH))
    NSColor(calibratedWhite: 0.45, alpha: 1).setStroke(); b.lineWidth = 1; b.stroke()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.imageInterpolation = .high
    for (i, sz) in stripSizes.enumerated() {
        let cellX = pad + CGFloat(i) * (cellW + cellGap)
        let file = sz == 16 ? "icon_16x16.png" : sz == 32 ? "icon_32x32.png"
                 : sz == 64 ? "icon_32x32@2x.png" : "icon_128x128.png"
        load(file).draw(in: NSRect(x: cellX + (cellW - sz) / 2,
                                   y: top - stripH + 26 + (stripH - 34 - sz) / 2,
                                   width: sz, height: sz))
        text("\(Int(sz))pt", cellX, top - stripH + 6, 10.5, grey: fg == .darkGray ? 0.35 : 0.62,
             anchor: .center, wide: cellW)
    }
    NSGraphicsContext.restoreGraphicsState()
    top -= stripH + 30
}
canvas.unlockFocus()
if let t = canvas.tiffRepresentation, let r = NSBitmapImageRep(data: t),
   let p = r.representation(using: .png, properties: [:]) {
    // 输出到**当前工作目录**，不写死绝对路径 —— 项目随时可能挪窝。
    // 跑的时候从项目根目录执行即可。
    let out = FileManager.default.currentDirectoryPath + "/应用图标_各尺寸.png"
    try? p.write(to: URL(fileURLWithPath: out)); print("已导出 \(out)  \(Int(W))×\(Int(H))")
}
