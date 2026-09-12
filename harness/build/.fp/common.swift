// ═══════════════════════════════════════════════════════════════
//  common —— 工具共用的渲染与哈希
//
//  跟 head.swift 一起编译。它提供三件事：
//    1. 把 CatView 渲染成像素（离屏，不截屏）
//    2. FNV-1a 64 哈希（指纹）
//    3. 按名字造一个"确定状态"的视图
//
//  ⚠️ 可复现的两个开关，缺一个指纹就不稳定：
//    · CatView.renderTime = 固定值   → 否则 drawCat 用 CACurrentMediaTime()
//    · freeze(state:phase:at:)       → 关掉眨眼 / 耳抖 / 自动换表情 / hover 摇晃
// ═══════════════════════════════════════════════════════════════

import Cocoa

// MARK: - 参数解析

func argValue(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

func hasFlag(_ name: String) -> Bool {
    CommandLine.arguments.contains(name)
}

// MARK: - 表情状态

/// 13 个表情状态，按名字取。名字就是 `CatState` 的 case 名。
let CAT_STATE_NAMES = [
    "idle", "eat", "happy", "error", "hmm", "hungry", "love",
    "wave", "sleepy", "curious", "worried", "lowbattery", "pet",
]

func catState(_ name: String) -> CatState? {
    switch name {
    case "idle":       return .idle
    case "eat":        return .eat
    case "happy":      return .happy
    case "error":      return .error
    case "hmm":        return .hmm
    case "hungry":     return .hungry
    case "love":       return .love
    case "wave":       return .wave
    case "sleepy":     return .sleepy
    case "curious":    return .curious
    case "worried":    return .worried
    case "lowbattery": return .lowbattery
    case "pet":        return .pet
    default:           return nil
    }
}

// MARK: - 造视图

/// 造一只"确定状态"的猫。所有参数显式给定 —— **不读用户配置**，
/// 否则同一份代码在不同机器上渲出来的图会不一样，指纹就没意义了。
func makeCat(look: Int = 0, eye: Int = 0, eyeColor: Int = 0,
             bib: Int = 0, ear: Int = 0, tail: Int = 0, mouth: Int = 0,
             state: String = "idle", phase: Double = 0,
             name: String = "测试") -> CatView {
    let v = CatView(frame: NSRect(x: 0, y: 0,
                                  width: CatView.canvasW, height: CatView.canvasH))
    v.lookOverride = look
    v.eyeOverride = eye
    v.eyeColorOverride = eyeColor
    v.bibOverride = bib
    v.earOverride = ear
    v.tailOverride = tail
    v.mouthOverride = mouth
    v.nameOverride = name          // 围兜上会印名字，固定住才可复现
    v.freeze(state: catState(state) ?? .idle, phase: phase, at: TIME_ANCHOR)
    return v
}

/// 冻结时间用的锚点。取一个固定值 —— 用真实时间的话每次跑都不一样。
let TIME_ANCHOR: TimeInterval = 100_000

/// 在固定时间下渲染。渲染完把 renderTime 还回去（**必须还**：
/// 不还的话，同进程里后面渲出来的东西会全被钉死在这一帧）。
func withFrozenTime<T>(_ body: () -> T) -> T {
    let saved = CatView.renderTime
    CatView.renderTime = TIME_ANCHOR
    defer { CatView.renderTime = saved }
    return body()
}

// MARK: - 渲染

struct Shot {
    let px: [UInt8]
    let w: Int, h: Int, bpr: Int

    var pixelCount: Int { w * h }
}

/// 渲染成像素。**不截屏** —— 直接让视图画到一块位图上，
/// 所以不依赖屏幕、不受窗口遮挡影响、尺寸完全可控。
func shoot(_ v: NSView, scale: CGFloat = 2) -> Shot? {
    let bounds = v.bounds
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = bounds.size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    bounds.fill()
    withFrozenTime { v.draw(bounds) }
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.bitmapData else { return nil }
    let n = rep.bytesPerRow * rep.pixelsHigh
    return Shot(px: Array(UnsafeBufferPointer(start: data, count: n)),
                w: rep.pixelsWide, h: rep.pixelsHigh, bpr: rep.bytesPerRow)
}

/// 渲染并写成 PNG。跟 `shoot` 是同一次绘制 —— 不要渲染两次再对比，
/// 两次渲染之间只要有任何一处状态没冻住，结果就会不一样。
@discardableResult
func shootToPNG(_ v: NSView, path: String, scale: CGFloat = 2) -> Shot? {
    guard let s = shoot(v, scale: scale) else { return nil }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: s.w, pixelsHigh: s.h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: Double(s.w) / scale, height: Double(s.h) / scale)
    s.px.withUnsafeBytes { src in
        memcpy(rep.bitmapData!, src.baseAddress!, s.px.count)
    }
    guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
    try? png.write(to: URL(fileURLWithPath: path))
    return s
}

// MARK: - 指纹

/// FNV-1a 64。用它是因为：一行代码、无依赖、结果稳定、够短能一眼比对。
/// 不是加密哈希 —— 这里只需要"变没变"，不需要抗碰撞。
func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in bytes {
        h ^= UInt64(b)
        h = h &* 0x0000_0100_0000_01b3
    }
    return h
}

func fingerprint(_ s: Shot) -> String {
    String(format: "%016llX", fnv1a64(s.px))
}

/// 基线文件的位置。
///
/// 用**可执行文件的位置**推项目根，而不是 `#filePath` ——
/// `#filePath` 会把构建时的绝对路径烤进二进制，项目一挪地方就失效，
/// 而且那个路径本身也是不该外泄的东西。
func baselineFile() -> String {
    // 可执行在 harness/build/<tool> → 上三级是项目根
    var u = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    u.deleteLastPathComponent()     // → harness/build
    u.deleteLastPathComponent()     // → harness
    u.deleteLastPathComponent()     // → 项目根
    return u.appendingPathComponent("harness/baseline.txt").path
}
