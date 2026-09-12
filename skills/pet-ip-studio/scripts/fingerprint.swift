// ═══════════════════════════════════════════════════════════════
//  fingerprint —— 一行回答「渲染结果有没有变」
//
//  用法：
//    fingerprint                       # 默认档的指纹
//    fingerprint --state happy         # 某个表情
//    fingerprint --scale 1             # 换渲染倍率
//    fingerprint --save out.png        # 顺手存一张
//    fingerprint --baseline            # 与 harness/baseline.txt 比对
//
//  它为什么值钱：改完绘制代码，你不必"看一眼觉得没问题"——
//  哈希一样就是逐位相同，一个字都不用怀疑。
// ═══════════════════════════════════════════════════════════════

import Cocoa

let scale = CGFloat(Double(argValue("--scale") ?? "2") ?? 2)
let stateName = argValue("--state") ?? "idle"
let phase = Double(argValue("--phase") ?? "0") ?? 0
let savePath = argValue("--save")

guard catState(stateName) != nil else {
    print("✗ 不认识的表情：\(stateName)")
    print("  可用：\(CAT_STATE_NAMES.joined(separator: " "))")
    exit(1)
}

let v = makeCat(state: stateName, phase: phase)
guard let s = shoot(v, scale: scale) else {
    print("✗ 渲染失败")
    exit(1)
}

if let p = savePath {
    shootToPNG(v, path: p, scale: scale)
}

let fp = fingerprint(s)

if hasFlag("--baseline") {
    let path = baselineFile()
    guard let saved = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("✗ 没有基线文件：\(path)")
        print("  建基线：fingerprint > harness/baseline.txt")
        exit(2)
    }
    // 按**行**取，跳过注释和空行 —— 别按空格切全文：
    // 注释里的中文只要行尾没空格，就会跟下一行的哈希粘成一段（踩过，
    // 症状是 --baseline 永远报「指纹变了」，一旦变成假阳性就没人再看它了）。
    let want = saved.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        .last
        .map { line -> String in
            let parts = line.split(separator: " ")
            return parts.isEmpty ? line : String(parts[parts.count - 1])
        } ?? ""
    if want == fp {
        print("✓ 指纹与基线一致  \(fp)")
        exit(0)
    } else {
        print("✗ 指纹变了！")
        print("   基线 \(want)")
        print("   现在 \(fp)")
        print("   → 如果你没打算改动渲染，这就是「碰到了不该碰的地方」。")
        exit(1)
    }
}

print(fp)
