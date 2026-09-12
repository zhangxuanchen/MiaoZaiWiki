// ═══════════════════════════════════════════════════════════════
//  PetStarter —— 最小可运行的 macOS 桌面宠物
//
//  编译：  swiftc -O -o PetStarter PetStarter.swift
//  运行：  ./PetStarter
//  自检：  ./PetStarter --render out.png     # 离屏渲染一张图，不用截屏
//
//  这份骨架只做四件事：出现在桌面上、画出一只宠物、能拖能退出、能自检。
//  它是起点，不是成品 —— 后面所有东西都从这里长出去。
// ═══════════════════════════════════════════════════════════════

import Cocoa

// ═══════════════════════════════════════════════════════════════
//  第 1 部分 · 形象参数
//
//  「这只宠物长什么样」全部收在这里。
//  换一只宠物 = 换这一部分，下面的绘制代码一行都不用动。
//  这就是「参数化」的第一步 —— 也是最关键的一步。
// ═══════════════════════════════════════════════════════════════

struct Palette {
    var fur: NSColor          // 主体毛色
    var furShadow: NSColor    // 耳朵、阴影（比毛色深一档）
    var earInner: NSColor     // 耳内
    var outline: NSColor      // 描边
    var eye: NSColor          // 瞳色
    var nose: NSColor         // 鼻子
    var blush: NSColor        // 腮红
}

/// 奶白：奶油底 + 暖棕耳 + 橄榄绿眼
let creamPalette = Palette(
    fur:       NSColor(srgbRed: 0.985, green: 0.960, blue: 0.915, alpha: 1),
    furShadow: NSColor(srgbRed: 0.860, green: 0.825, blue: 0.775, alpha: 1),
    earInner:  NSColor(srgbRed: 0.955, green: 0.745, blue: 0.745, alpha: 1),
    outline:   NSColor(srgbRed: 0.290, green: 0.175, blue: 0.110, alpha: 1),
    eye:       NSColor(srgbRed: 0.555, green: 0.605, blue: 0.205, alpha: 1),
    nose:      NSColor(srgbRed: 0.945, green: 0.575, blue: 0.590, alpha: 1),
    blush:     NSColor(srgbRed: 0.970, green: 0.660, blue: 0.690, alpha: 0.85)
)

/// 骨架：把「形状」也变成数字。
/// 想让眼睛更扁只改 eyeRY；想让脸更大只改 headR。
/// 不要再去 draw() 里找那些数字 —— 这是这份骨架跟「随手画的代码」最大的区别。
struct Geometry {
    var headR: CGFloat = 52          // 头半径
    var headSquashY: CGFloat = 0.94  // 头高 / 头宽
    var earSpread: CGFloat = 0.66    // 耳朵离中线多远（× headR）
    var earHeight: CGFloat = 1.06    // 耳尖高度（× headR）
    var eyeDX: CGFloat = 21          // 眼睛离中线多远
    var eyeDY: CGFloat = 7           // 眼睛比头心高多少
    var eyeRX: CGFloat = 11.5        // 眼睛半宽
    var eyeRY: CGFloat = 6.5         // 眼睛半高 —— 改小 = 扁眼
    var bodyR: CGFloat = 50          // 身体半宽
    var strokeW: CGFloat = 3.5       // 描边粗细
}

let standardGeometry = Geometry()

// ── 画图的两个小工具（省得每次写三行 setFill / fill）──
func paintFill(_ path: NSBezierPath, _ color: NSColor) {
    color.setFill()
    path.fill()
}

func paintStroke(_ path: NSBezierPath, _ color: NSColor, width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

// ═══════════════════════════════════════════════════════════════
//  第 2 部分 · 绘制
//
//  一只宠物 = 若干个 NSBezierPath。没有图片、没有贴图。
//  好处：任意分辨率都锐利、能渲到任意大小、能精确断言。
//
//  顺序很重要：后画的压在前面的上面。
//  身体 → 耳 → 头 → 五官 → 腮红
// ═══════════════════════════════════════════════════════════════

final class PetView: NSView {
    var palette = creamPalette
    var geo = standardGeometry

    override var isFlipped: Bool { false }   // 用数学坐标系（原点左下、y 向上）

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY + 46)   // 头心

        drawBody(around: c)
        drawEars(around: c)
        drawHead(around: c)
        drawFace(around: c)
        drawBlush(around: c)
    }

    private func drawBody(around c: NSPoint) {
        let r = geo.bodyR
        let cy = c.y - geo.headR * 0.94 - r * 0.42
        let body = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: cy - r * 0.94,
                                              width: r * 2, height: r * 1.88))
        paintFill(body, palette.fur)
        paintStroke(body, palette.outline, width: geo.strokeW)

        // 一对前爪：露在身体前面，比身体浅一点点
        for side in [CGFloat(-1), CGFloat(1)] {
            let px = c.x + side * r * 0.52
            let paw = NSBezierPath(ovalIn: NSRect(x: px - 13, y: cy - r * 0.72 - 10,
                                                  width: 26, height: 21))
            paintFill(paw, palette.fur)
            paintStroke(paw, palette.outline, width: geo.strokeW * 0.85)
        }
    }

    private func drawEars(around c: NSPoint) {
        for side in [CGFloat(-1), CGFloat(1)] {
            let ex = c.x + side * geo.headR * geo.earSpread

            // 外耳
            let tip = NSPoint(x: ex + side * geo.headR * 0.06, y: c.y + geo.headR * geo.earHeight)
            let ear = NSBezierPath()
            ear.move(to: NSPoint(x: ex - side * geo.headR * 0.36, y: c.y + geo.headR * 0.30))
            ear.line(to: NSPoint(x: ex + side * geo.headR * 0.34, y: c.y + geo.headR * 0.18))
            ear.line(to: tip)
            ear.close()
            paintFill(ear, palette.furShadow)
            paintStroke(ear, palette.outline, width: geo.strokeW)

            // 内耳：往外耳中心缩一圈
            let inner = NSBezierPath()
            inner.move(to: NSPoint(x: ex - side * geo.headR * 0.14, y: c.y + geo.headR * 0.30))
            inner.line(to: NSPoint(x: ex + side * geo.headR * 0.18, y: c.y + geo.headR * 0.25))
            inner.line(to: NSPoint(x: ex + side * geo.headR * 0.02, y: c.y + geo.headR * 0.80))
            inner.close()
            paintFill(inner, palette.earInner)
        }
    }

    private func drawHead(around c: NSPoint) {
        let r = geo.headR
        let rect = NSRect(x: c.x - r, y: c.y - r * geo.headSquashY,
                          width: r * 2, height: r * 2 * geo.headSquashY)
        let head = NSBezierPath(ovalIn: rect)
        paintFill(head, palette.fur)
        paintStroke(head, palette.outline, width: geo.strokeW)
    }

    private func drawFace(around c: NSPoint) {
        // 眼睛
        for side in [CGFloat(-1), CGFloat(1)] {
            let ex = c.x + side * geo.eyeDX
            let eye = NSBezierPath(ovalIn: NSRect(x: ex - geo.eyeRX, y: c.y + geo.eyeDY - geo.eyeRY,
                                                  width: geo.eyeRX * 2, height: geo.eyeRY * 2))
            paintFill(eye, palette.eye)
        }

        // 鼻子：一个倒三角
        let noseW: CGFloat = 11, noseH: CGFloat = 8
        let noseTop = c.y - geo.headR * 0.26
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: c.x - noseW / 2, y: noseTop))
        nose.line(to: NSPoint(x: c.x + noseW / 2, y: noseTop))
        nose.line(to: NSPoint(x: c.x, y: noseTop - noseH))
        nose.close()
        paintFill(nose, palette.nose)

        // 嘴：人中 + 两片唇叶（猫的三瓣嘴）
        let lipY = noseTop - noseH - 5
        let philtrum = NSBezierPath()
        philtrum.move(to: NSPoint(x: c.x, y: noseTop - noseH))
        philtrum.line(to: NSPoint(x: c.x, y: lipY))
        paintStroke(philtrum, palette.outline, width: 2.2)

        for side in [CGFloat(-1), CGFloat(1)] {
            let lobe = NSBezierPath()
            lobe.move(to: NSPoint(x: c.x, y: lipY))
            lobe.curve(to: NSPoint(x: c.x + side * 12, y: lipY - 2),
                       controlPoint1: NSPoint(x: c.x + side * 5, y: lipY - 0.5),
                       controlPoint2: NSPoint(x: c.x + side * 9, y: lipY - 2))
            paintStroke(lobe, palette.outline, width: 2.6)
        }
    }

    private func drawBlush(around c: NSPoint) {
        for side in [CGFloat(-1), CGFloat(1)] {
            let bx = c.x + side * geo.headR * 0.60
            let by = c.y - geo.headR * 0.10
            // 三个点，不是一条斜线 —— 斜线容易跟别人的画法撞
            for off in [CGFloat(-4.5), 0, 4.5] {
                let dot = NSBezierPath(ovalIn: NSRect(x: bx + off - 2, y: by - side * 1.5 - 2,
                                                      width: 4, height: 4))
                paintFill(dot, palette.blush)
            }
        }
    }

    // ── 交互：拖动 + 右键菜单 ──
    private var dragStart: NSPoint?
    private var frameStart: NSPoint?

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        frameStart = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = dragStart, let f = frameStart else { return }
        let now = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: f.x + (now.x - s.x), y: f.y + (now.y - s.y)))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        frameStart = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }
}

// ═══════════════════════════════════════════════════════════════
//  第 3 部分 · 离屏渲染（这一块别跳过）
//
//  它让你**不截屏**就能拿到「现在画出来是什么样」。
//  有了它，后面才可能写出「改完之后默认档一个像素没动」这种断言。
//  没有这一步，AI 改绘制代码就是盲改。
// ═══════════════════════════════════════════════════════════════

func renderOffscreen(_ view: NSView, to path: String, scale: CGFloat = 2) {
    let bounds = view.bounds
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = bounds.size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    bounds.fill()
    view.draw(bounds)
    NSGraphicsContext.restoreGraphicsState()

    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
        print("已导出 \(path)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
    }
}

// ═══════════════════════════════════════════════════════════════
//  第 4 部分 · 让它出现在桌面上
// ═══════════════════════════════════════════════════════════════

let PET_SIZE = NSSize(width: 176, height: 214)

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // 不出现在 Dock 里 —— 它是挂件，不是常规 app

// ── 自检模式：渲一张图就退出 ──
if let i = CommandLine.arguments.firstIndex(of: "--render") {
    let out = CommandLine.arguments.count > i + 1
        ? CommandLine.arguments[i + 1] : "pet-preview.png"
    let v = PetView(frame: NSRect(origin: .zero, size: PET_SIZE))
    renderOffscreen(v, to: out)
    exit(0)
}

let panel = PetPanel(contentRect: NSRect(origin: .zero, size: PET_SIZE),
                     styleMask: [.borderless, .nonactivatingPanel],
                     backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear           // 只有宠物本身可见，窗口本身看不见
panel.hasShadow = false
panel.level = .floating                  // 浮在普通窗口之上
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isMovableByWindowBackground = true

let petView = PetView(frame: NSRect(origin: .zero, size: PET_SIZE))
panel.contentView = petView
panel.setFrameOrigin(NSPoint(x: 880, y: 320))
panel.orderFrontRegardless()             // 出现但不抢焦点

print("宠物已出现在桌面上。拖动它试试，右键点它可以退出。")
app.run()
