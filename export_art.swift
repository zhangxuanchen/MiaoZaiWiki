// ============ 角色设计 · 版权材料导出驱动 ============
import Foundation
import Cocoa

// 输出不缓冲：万一中途崩了，也能看到崩在哪一步（缓冲模式下会全丢）
setvbuf(stdout, nil, _IONBF, 0)

_ = NSApplication.shared
print("[0] NSApplication 就绪")

// MARK: - 基本参数

let CW: CGFloat = 186, CH: CGFloat = 205      // 画布（和 App 一致）
let SCALE: CGFloat = 6                        // 位图倍率 → 最终约 900×900
let MARGIN: CGFloat = 8                       // 裁切外扩留白（pt）

// 输出目录取**当前工作目录**下的角色设计材料目录 ——
// export_art.sh 里已经 cd 到项目根目录了，所以不用（也不该）写死绝对路径。
//
// 但这个目录名被改过好几次（猫崽角色设计_版权材料 → 猫藏角色设计_版权材料 →
// 角色设计_版权材料）。**写死名字等于每改一次名就静默指向空目录**（踩过），
// 所以按「*版权材料」后缀探测：已存在就复用，一个都找不到才用默认名新建。
func resolveArtDir() -> String {
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath
    var isDir: ObjCBool = false
    for n in (try? fm.contentsOfDirectory(atPath: cwd)) ?? [] where n.hasSuffix("版权材料") {
        if fm.fileExists(atPath: cwd + "/" + n, isDirectory: &isDir), isDir.boolValue {
            return cwd + "/" + n
        }
    }
    return cwd + "/角色设计_版权材料"
}
let ROOT = resolveArtDir()
let T: TimeInterval = 1_000_000               // 钉死的"当前时间"
CatView.renderTime = T

// MARK: - 名词表

let LOOK_NAMES = ["奶白", "橘猫", "蓝猫", "樱花"]
let EYE_NAMES  = ["扁眼", "圆眼", "细长眼", "墨镜", "心形墨镜", "星星墨镜",
                  "圆框眼镜", "单片眼镜", "眼罩"]
let BIB_NAMES  = ["方形围兜", "尖角围兜", "圆形围兜", "花边围兜"]
let EAR_NAMES  = ["尖耳", "圆耳", "折耳", "大耳"]
let TAIL_NAMES = ["上翘", "卷尾", "长尾", "蓬松", "短尾"]
let MOUTH_NAMES = ["三瓣嘴", "阔嘴", "小嘴", "垂唇", "一字唇"]
let EYECOLOR_NAMES = ["跟形象", "翡翠", "橄榄", "草绿", "薄荷", "晴空蓝", "深海蓝", "紫罗兰",
                      "樱花粉", "琥珀", "砖红", "咖啡", "石墨", "翡翠·樱花粉", "紫罗兰·薄荷",
                      "草绿·紫罗兰", "白色", "淡灰色"]

struct StateInfo { let s: CatState; let name: String; let phase: TimeInterval }
let STATES: [StateInfo] = [
    .init(s: .idle,       name: "发呆",      phase: 0),
    .init(s: .curious,    name: "好奇",      phase: 0),
    .init(s: .happy,      name: "开心",      phase: 0.40),
    .init(s: .love,       name: "喜欢",      phase: 0.40),
    .init(s: .wave,       name: "打招呼",    phase: 0.40),
    .init(s: .sleepy,     name: "困了",      phase: 0),
    .init(s: .hmm,        name: "疑惑",      phase: 0),
    .init(s: .worried,    name: "担心",      phase: 0),
    .init(s: .hungry,     name: "肚子饿",    phase: 0),
    .init(s: .lowbattery, name: "电量不足",  phase: 0),
    .init(s: .error,      name: "出错",      phase: 0),
    .init(s: .eat,        name: "吃东西",    phase: 0.40),
    .init(s: .pet,        name: "被撸",      phase: 0.40),
]

// MARK: - 变体定义

struct V {
    let group: String       // 目录
    let file: String        // 文件名（不含扩展名）
    let desc: String        // 说明（进清单）
    var look = 0, eye = 0, bib = 0, ear = 0
    var tail = 0, mouth = 0, eyeColor = 0
    var state: CatState = .idle
    var phase: TimeInterval = 0
    var name: String? = "喵藏"          // 围兜印字；"" = 不印字
}

func variants() -> [V] {
    var out: [V] = []
    // 01 主形象：4 套配色
    for (i, n) in LOOK_NAMES.enumerated() {
        out.append(V(group: "01_主形象", file: String(format: "01-%02d_主形象_%@", i + 1, n),
                     desc: "角色主形象 · 配色\(n)", look: i))
    }
    // 02 主形象（围兜不印字）
    for (i, n) in LOOK_NAMES.enumerated() {
        out.append(V(group: "02_主形象_无文字版", file: String(format: "02-%02d_无文字_%@", i + 1, n),
                     desc: "角色主形象 · 配色\(n) · 围兜无文字", look: i, name: ""))
    }
    // 03 眼型 / 眼镜变体
    for (i, n) in EYE_NAMES.enumerated() {
        out.append(V(group: "03_眼型与眼镜变体", file: String(format: "03-%02d_眼型_%@", i + 1, n),
                     desc: "可替换眼型/眼镜 · \(n)", eye: i))
    }
    // 04 围兜变体
    for (i, n) in BIB_NAMES.enumerated() {
        out.append(V(group: "04_围兜变体", file: String(format: "04-%02d_围兜_%@", i + 1, n),
                     desc: "可替换围兜 · \(n)", bib: i))
    }
    // 05 耳型变体
    for (i, n) in EAR_NAMES.enumerated() {
        out.append(V(group: "05_耳型变体", file: String(format: "05-%02d_耳型_%@", i + 1, n),
                     desc: "可替换耳型 · \(n)", ear: i))
    }
    // 06 表情/状态
    for (i, si) in STATES.enumerated() {
        out.append(V(group: "06_表情状态", file: String(format: "06-%02d_表情_%@", i + 1, si.name),
                     desc: "表情状态 · \(si.name)", look: 1, eye: 1, bib: 2, ear: 1,
                     state: si.s, phase: si.phase))
    }
    // 07 尾巴变体
    for (i, n) in TAIL_NAMES.enumerated() {
        out.append(V(group: "07_尾巴变体", file: String(format: "07-%02d_尾巴_%@", i + 1, n),
                     desc: "可替换尾巴 · \(n)", tail: i))
    }
    // 08 嘴形变体
    for (i, n) in MOUTH_NAMES.enumerated() {
        out.append(V(group: "08_嘴形变体", file: String(format: "08-%02d_嘴形_%@", i + 1, n),
                     desc: "可替换嘴形 · \(n)", mouth: i))
    }
    // 09 眼睛颜色（18 档：跟形象 + 12 单色 + 3 异色瞳 + 2 无彩色）
    for (i, n) in EYECOLOR_NAMES.enumerated() {
        out.append(V(group: "09_眼睛颜色", file: String(format: "09-%02d_眼睛颜色_%@", i + 1, n),
                     desc: "可替换眼睛颜色 · \(n)", eyeColor: i))
    }
    return out
}

let ALL = variants()

// MARK: - 渲染

func makeView(_ v: V) -> CatView {
    let view = CatView(frame: NSRect(x: 0, y: 0, width: CW, height: CH))
    view.lookOverride = v.look
    view.eyeOverride = v.eye
    view.bibOverride = v.bib
    view.earOverride = v.ear
    view.tailOverride = v.tail
    view.mouthOverride = v.mouth
    view.eyeColorOverride = v.eyeColor
    view.nameOverride = v.name
    view.freeze(state: v.state, phase: v.phase, at: T)
    view.layoutSubtreeIfNeeded()
    return view
}

/// 内容包围盒（视图坐标，y 向上）
func contentBox(_ v: CatView) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    let s = Double(rep.pixelsHigh) / Double(CH)
    var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
    let w = rep.pixelsWide, h = rep.pixelsHigh
    guard let data = rep.bitmapData else { return nil }
    let spp = rep.samplesPerPixel
    let rowBytes = rep.bytesPerRow
    for y in 0..<h {
        let base = y * rowBytes
        for x in 0..<w {
            if data[base + x * spp + 3] > 13 {          // alpha > 0.05
                if x < x0 { x0 = x }; if x > x1 { x1 = x }
                if y < y0 { y0 = y }; if y > y1 { y1 = y }
            }
        }
    }
    guard x1 >= 0 else { return nil }
    let top = Double(CH) - Double(y0) / s
    let bot = Double(CH) - Double(y1 + 1) / s
    return (CGFloat(Double(x0) / s), CGFloat(bot), CGFloat(Double(x1 + 1) / s), CGFloat(top))
}

/// 把裁切好的 PDF 栅格化成位图。
/// 注意：**一律用 4 通道 RGBA**（samplesPerPixel 3 / hasAlpha false 的位图上下文会崩），
/// 需要白底就给个白底色，JPEG 编码器自己会把 alpha 压平。
func rasterize(_ pdf: Data, px: Int, whiteBG: Bool) -> NSBitmapImageRep? {
    guard let img = NSImage(data: pdf) else { return nil }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState(); return nil
    }
    NSGraphicsContext.current = gctx
    if whiteBG {
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: px, height: px).fill()
    }
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - 目录准备

let fm = FileManager.default
func mkdir(_ p: String) { try? fm.createDirectory(atPath: p, withIntermediateDirectories: true) }
for g in ["01_主形象", "02_主形象_无文字版", "03_眼型与眼镜变体", "04_围兜变体",
          "05_耳型变体", "06_表情状态", "07_尾巴变体", "08_嘴形变体", "09_眼睛颜色",
          "_总览图", "_矢量源文件PDF"] { mkdir(ROOT + "/" + g) }

// MARK: - 第一遍：算所有变体的内容并集，定出统一裁切框

print("=== 第一遍：扫描内容包围盒 ===")
var ux0 = CGFloat.greatestFiniteMagnitude, uy0 = ux0
var ux1 = -uy0, uy1 = -uy0
for v in ALL {
    guard let b = contentBox(makeView(v)) else { print("  ⚠️ 空图：\(v.file)"); continue }
    ux0 = min(ux0, b.0); uy0 = min(uy0, b.1)
    ux1 = max(ux1, b.2); uy1 = max(uy1, b.3)
}
print(String(format: "  并集  x %.1f…%.1f  y %.1f…%.1f  →  %.1f × %.1f",
             ux0, ux1, uy0, uy1, ux1 - ux0, uy1 - uy0))

let side = max(ux1 - ux0, uy1 - uy0) + MARGIN * 2          // 正方形，统一尺寸
let cx = (ux0 + ux1) / 2, cy = (uy0 + uy1) / 2
let cropX = min(max(cx - side / 2, 0), CW - side)
let cropY = min(max(cy - side / 2, 0), CH - side)
let CROP = NSRect(x: cropX, y: cropY, width: side, height: side)
print(String(format: "  统一裁切框  x %.1f…%.1f  y %.1f…%.1f  (%.0f × %.0f pt)  → %dx%d px",
             CROP.minX, CROP.maxX, CROP.minY, CROP.maxY, side, side,
             Int(side * SCALE), Int(side * SCALE)))

let PX = Int(side * SCALE)

// MARK: - 第二遍：导出 PNG / JPG / PDF + 生成清单

print("\n=== 第二遍：导出 ===")
var manifest: [[String]] = []
for (i, v) in ALL.enumerated() {
    let loud = i < 2
    if loud { print("  [\(i)] makeView") }
    let view = makeView(v)
    if loud { print("  [\(i)] dataWithPDF") }
    let pdf = view.dataWithPDF(inside: CROP)
    if loud { print("  [\(i)] pdf = \(pdf.count) 字节；写盘") }

    // 矢量 PDF 母版
    let pdfPath = "\(ROOT)/_矢量源文件PDF/\(v.file).pdf"
    try? pdf.write(to: URL(fileURLWithPath: pdfPath))
    if loud { print("  [\(i)] pdf 写盘完成") }

    // 透明 PNG
    if loud { print("  [\(i)] 栅格化 PNG") }
    if let rep = rasterize(pdf, px: PX, whiteBG: false),
       let d = rep.representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: "\(ROOT)/\(v.group)/\(v.file).png"))
        if loud { print("  [\(i)] PNG ok \(d.count) 字节") }
    } else if loud { print("  [\(i)] PNG 失败") }
    // 白底 JPG（申请书用）
    if loud { print("  [\(i)] 栅格化 JPG") }
    if let rep = rasterize(pdf, px: PX, whiteBG: true),
       let d = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
        try? d.write(to: URL(fileURLWithPath: "\(ROOT)/\(v.group)/\(v.file).jpg"))
        if loud { print("  [\(i)] JPG ok \(d.count) 字节") }
    } else if loud { print("  [\(i)] JPG 失败") }

    manifest.append([
        String(i + 1), v.group, v.file,
        LOOK_NAMES[min(v.look, 3)], EYE_NAMES[min(v.eye, 8)],
        BIB_NAMES[min(v.bib, 3)], EAR_NAMES[min(v.ear, 3)],
        TAIL_NAMES[min(v.tail, 4)], MOUTH_NAMES[min(v.mouth, 4)], EYECOLOR_NAMES[min(v.eyeColor, 17)],
        v.desc, v.name == "" ? "无" : "喵藏",
    ])
    if (i + 1) % 10 == 0 { print("  已导出 \(i + 1)/\(ALL.count)") }
}
print("  已导出 \(ALL.count)/\(ALL.count)")

// MARK: - 总览图（拼版）

func cellImage(_ v: V, px: Int) -> NSImage? {
    let view = makeView(v)
    guard let rep = rasterize(view.dataWithPDF(inside: CROP), px: px, whiteBG: false) else { return nil }
    let img = NSImage(size: NSSize(width: px, height: px))
    img.addRepresentation(rep)
    return img
}

struct SheetSpec { let out: String; let title: String; let cols: Int; let items: [V] }

var sheets: [SheetSpec] = []
sheets.append(SheetSpec(out: "_总览图/总览_01_主形象四配色", title: "猫崽 · 主形象（四套配色）",
                        cols: 4, items: Array(ALL[0..<4])))
sheets.append(SheetSpec(out: "_总览图/总览_02_眼型与眼镜九款", title: "猫崽 · 可替换眼型与眼镜（9 款）",
                        cols: 5, items: Array(ALL[8..<17])))
var acc: [V] = Array(ALL[17..<21]) + Array(ALL[21..<25])
sheets.append(SheetSpec(out: "_总览图/总览_03_围兜与耳型八款", title: "猫崽 · 可替换围兜与耳型（各 4 款）",
                        cols: 4, items: acc))
sheets.append(SheetSpec(out: "_总览图/总览_04_表情状态十三款", title: "猫崽 · 表情与状态（13 款）",
                        cols: 5, items: Array(ALL[25..<38])))
sheets.append(SheetSpec(out: "_总览图/总览_06_尾巴样式五款", title: "猫崽 · 可替换尾巴样式（5 款）",
                        cols: 5, items: Array(ALL[38..<43])))
sheets.append(SheetSpec(out: "_总览图/总览_07_嘴形五款", title: "猫崽 · 可替换嘴形（5 款）",
                        cols: 5, items: Array(ALL[43..<48])))
sheets.append(SheetSpec(out: "_总览图/总览_08_眼睛颜色十八档", title: "猫崽 · 可替换眼睛颜色（18 档）",
                        cols: 6, items: Array(ALL[48..<66])))

// 设计空间矩阵：4 配色 × 9 眼型
var matrix: [V] = []
for l in 0..<4 { for e in 0..<9 {
    matrix.append(V(group: "矩阵", file: "M\(l)-\(e)", desc: "",
                    look: l, eye: e, bib: 0, ear: 0))
} }
sheets.append(SheetSpec(out: "_总览图/总览_05_设计空间矩阵_配色x眼型36款",
                        title: "猫崽 · 设计空间矩阵（4 配色 × 9 眼型 = 36 种形象）",
                        cols: 9, items: matrix))

print("\n=== 拼总览图 ===")
for spec in sheets {
    let cellPx = spec.cols >= 9 ? 150 : (spec.cols >= 5 ? 210 : 250)
    let gap: CGFloat = 16
    let labelH: CGFloat = 30
    let cols = spec.cols
    let rows = (spec.items.count + cols - 1) / cols
    let cw = CGFloat(cellPx)
    let W2 = CGFloat(cols) * cw + CGFloat(cols + 1) * gap
    let H2 = CGFloat(rows) * (cw + labelH) + CGFloat(rows + 1) * gap + 56
    let canvas = NSImage(size: NSSize(width: W2, height: H2))
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W2, height: H2).fill()
    NSAttributedString(string: spec.title, attributes: [
        .font: NSFont.boldSystemFont(ofSize: 26),
        .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
    ]).draw(at: NSPoint(x: gap + 6, y: H2 - 46))
    for (k, v) in spec.items.enumerated() {
        let c = k % cols, r = k / cols
        let x = gap + CGFloat(c) * (cw + gap)
        let y = H2 - 56 - gap - CGFloat(r + 1) * (cw + labelH) - CGFloat(r) * gap
        // 棋盘格底，方便看出透明区域
        let cs: CGFloat = 12
        for gy in 0...Int(cw / cs) {
            for gx in 0...Int(cw / cs) {
                NSColor(calibratedWhite: (gx + gy) % 2 == 0 ? 0.92 : 0.86, alpha: 1).setFill()
                NSRect(x: x + CGFloat(gx) * cs, y: y + labelH + CGFloat(gy) * cs,
                       width: cs, height: cs).fill()
            }
        }
        cellImage(v, px: cellPx * 2)?.draw(in: NSRect(x: x, y: y + labelH, width: cw, height: cw))
        let label: String
        if spec.title.contains("矩阵") {
            label = "\(LOOK_NAMES[v.look])·\(EYE_NAMES[v.eye])"
        } else if v.group == "06_表情状态" {
            label = STATES[min(k, STATES.count - 1)].name
        } else if v.file.contains("眼型") {
            label = EYE_NAMES[min(v.eye, 8)]
        } else if v.file.contains("围兜") {
            label = BIB_NAMES[min(v.bib, 3)]
        } else if v.file.contains("耳型") {
            label = EAR_NAMES[min(v.ear, 3)]
        } else if v.file.contains("尾巴") {
            label = TAIL_NAMES[min(v.tail, 4)]
        } else if v.file.contains("嘴形") {
            label = MOUTH_NAMES[min(v.mouth, 4)]
        } else if v.file.contains("眼睛颜色") {
            label = EYECOLOR_NAMES[min(v.eyeColor, 17)]
        } else {
            label = LOOK_NAMES[min(v.look, 3)]
        }
        let ps = NSMutableParagraphStyle(); ps.alignment = .center
        NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: cellPx >= 250 ? 17 : 14, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1),
            .paragraphStyle: ps,
        ]).draw(in: NSRect(x: x, y: y + 4, width: cw, height: 22))
    }
    canvas.unlockFocus()
    if let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(ROOT)/\(spec.out).png"))
        print("  \(spec.out).png  (\(Int(W2))×\(Int(H2)))")
    }
}

// MARK: - 多页「作品图样」PDF（A4，每页一款）

print("\n=== 生成作品图样 PDF ===")

func labelOf(_ v: V) -> String {
    if v.group == "矩阵" { return "\(LOOK_NAMES[v.look])·\(EYE_NAMES[v.eye])" }
    if v.file.contains("眼型") { return EYE_NAMES[min(v.eye, 8)] }
    if v.file.contains("围兜") { return BIB_NAMES[min(v.bib, 3)] }
    if v.file.contains("耳型") { return EAR_NAMES[min(v.ear, 3)] }
    if v.file.contains("尾巴") { return TAIL_NAMES[min(v.tail, 4)] }
    if v.file.contains("嘴形") { return MOUTH_NAMES[min(v.mouth, 4)] }
    if v.file.contains("眼睛颜色") { return EYECOLOR_NAMES[min(v.eyeColor, 17)] }
    return LOOK_NAMES[min(v.look, 3)]
}

// 先摊平成「页」列表：每页一个标题 + 一批变体。每页最多 12 款，超了就分页。
struct PdfPage { let group: String; let items: [V] }
var pages: [PdfPage] = []
func addPages(_ group: String, _ items: [V], per: Int = 12) {
    var i = 0
    while i < items.count {
        let end = min(i + per, items.count)
        pages.append(PdfPage(group: group, items: Array(items[i..<end])))
        i = end
    }
}
addPages("主形象（四套配色）", Array(ALL[0..<4]), per: 4)
addPages("主形象 · 围兜无文字版", Array(ALL[4..<8]), per: 4)
addPages("可替换眼型与眼镜（9 款）", Array(ALL[8..<17]), per: 9)
addPages("可替换围兜（4 款）", Array(ALL[17..<21]), per: 4)
addPages("可替换耳型（4 款）", Array(ALL[21..<25]), per: 4)
addPages("表情与状态（13 款）", Array(ALL[25..<38]), per: 8)
addPages("可替换尾巴（5 款）", Array(ALL[38..<43]), per: 5)
addPages("可替换嘴形（5 款）", Array(ALL[43..<48]), per: 5)
addPages("可替换眼睛颜色（18 档）", Array(ALL[48..<66]), per: 9)
addPages("设计空间矩阵（4 配色 × 9 眼型）", matrix, per: 12)
print("  共 \(pages.count) 页")

let pageW: CGFloat = 595, pageH: CGFloat = 842          // A4 @72dpi
let pdfData = NSMutableData()
var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)

if let consumer = CGDataConsumer(data: pdfData),
   let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) {

    for (pi, page) in pages.enumerated() {
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pageW, height: pageH).fill()

        NSAttributedString(string: "猫崽 · 角色设计作品图样", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 20),
            .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1),
        ]).draw(at: NSPoint(x: 40, y: pageH - 58))
        NSAttributedString(string: page.group + "　·　第 \(pi + 1) / \(pages.count) 页　·　本页 \(page.items.count) 款",
                           attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
        ]).draw(at: NSPoint(x: 40, y: pageH - 80))

        NSColor(calibratedWhite: 0.86, alpha: 1).setStroke()
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: 40, y: pageH - 92))
        rule.line(to: NSPoint(x: pageW - 40, y: pageH - 92))
        rule.lineWidth = 1
        rule.stroke()

        // 格子尺寸：让整页刚好铺满可用区域
        let availW = pageW - 80, availH = pageH - 92 - 60
        let n = page.items.count
        let cols = n <= 4 ? 2 : (n <= 9 ? 3 : 4)
        let rows = (n + cols - 1) / cols
        let gGap: CGFloat = 14, lGap: CGFloat = 13
        let cell = min((availW - CGFloat(cols - 1) * gGap) / CGFloat(cols),
                       (availH - CGFloat(rows - 1) * (gGap + lGap)) / CGFloat(rows))
        let gridW = CGFloat(cols) * cell + CGFloat(cols - 1) * gGap
        let gridH = CGFloat(rows) * cell + CGFloat(rows - 1) * (gGap + lGap)
        let startX = (pageW - gridW) / 2
        let topY = pageH - 92 - max((availH - gridH) / 2, 12)

        for (k, v) in page.items.enumerated() {
            let c = k % cols, r = k / cols
            let x = startX + CGFloat(c) * (cell + gGap)
            let yTop = topY - CGFloat(r) * (cell + gGap + lGap)
            if let img = cellImage(v, px: Int(cell * 3)) {
                img.draw(in: NSRect(x: x, y: yTop - cell, width: cell, height: cell))
            }
            let ps = NSMutableParagraphStyle(); ps.alignment = .center
            NSAttributedString(string: labelOf(v), attributes: [
                .font: NSFont.systemFont(ofSize: 9.5),
                .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1),
                .paragraphStyle: ps,
            ]).draw(in: NSRect(x: x, y: yTop - cell - lGap - 1, width: cell, height: 12))
        }

        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }
    ctx.closePDF()
}
try? pdfData.write(to: URL(fileURLWithPath: "\(ROOT)/作品图样_汇总.pdf"))
print("  作品图样_汇总.pdf  (\(pdfData.length) 字节)")

// MARK: - 作品清单 CSV

var csv = "\u{FEFF}序号,分组,文件名,配色,眼型,围兜,耳型,尾巴,嘴形,眼睛颜色,说明,围兜印字\n"
for row in manifest {
    csv += row.map { f in
        f.contains(",") || f.contains("\"") ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
    }.joined(separator: ",") + "\n"
}
try? csv.write(toFile: "\(ROOT)/作品清单.csv", atomically: true, encoding: .utf8)
print("  作品清单.csv  (\(manifest.count) 行)")

print("\n✅ 导出完成：\(ROOT)")
