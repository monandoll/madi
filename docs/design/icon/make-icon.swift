// 앱 아이콘을 그린다.
//
//   swiftc -O -o /tmp/make-icon docs/design/icon/make-icon.swift && /tmp/make-icon
//
// 뜻: "마디" 는 대나무 마디 · 몸의 관절이고, 이 앱에서는 **장면**이다.
// 세로(9:16) 영상 한 편이 길이가 다른 마디 셋으로 나뉜 모양 — 이 앱이 하는 일 그대로다
// (촬영본을 장면으로 나눠 숏폼을 만든다). 마디 사이 틈을 좁게 둬서 **한 편의 세로 영상**으로 읽히게 한다.
//
// 재생 표시(▶)는 넣지 않았다. 흰 둥근 네모 안의 ▶ 는 유튜브 로고와 너무 닮았다.
//
// 색은 앱 강조색(`Tokens.Palette.accent` #2D6A55)을 바탕으로 쓴다 — 앱 안의 `만들기` 버튼과 같은 초록.
// 모양은 macOS 아이콘 격자를 따른다: 1024 캔버스 안에 824 몸통, 둥근 모서리, 옅은 그림자.

import AppKit

let canvas: CGFloat = 1024
let body: CGFloat = 824
let inset = (canvas - body) / 2
let radius: CGFloat = 186

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func draw(into ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bodyRect = CGRect(x: inset, y: inset + 10, width: body, height: body)  // 그림자 자리만큼 살짝 위
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 그림자
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.28))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x2D6A55))
    ctx.fillPath()
    ctx.restoreGState()

    // 바탕 — 위가 조금 밝은 초록
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [rgb(0x3D8A6F), rgb(0x2D6A55), rgb(0x22523F)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: bodyRect.maxY),
        end: CGPoint(x: 0, y: bodyRect.minY),
        options: []
    )
    ctx.restoreGState()

    // 9:16 영상 — 마디 셋. 길이를 일부러 다르게 둔다 (장면마다 길이가 다르다).
    let columnHeight: CGFloat = 560
    let columnWidth = columnHeight * 9 / 16
    let column = CGRect(
        x: bodyRect.midX - columnWidth / 2,
        y: bodyRect.midY - columnHeight / 2,
        width: columnWidth,
        height: columnHeight
    )
    let gap: CGFloat = 16
    let weights: [CGFloat] = [2.2, 1.25, 1.75]   // 위에서부터
    let usable = columnHeight - gap * CGFloat(weights.count - 1)
    let total = weights.reduce(0, +)
    let segRadius: CGFloat = 34

    var top = column.maxY
    for (index, weight) in weights.enumerated() {
        let h = usable * weight / total
        let rect = CGRect(x: column.minX, y: top - h, width: columnWidth, height: h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: segRadius, cornerHeight: segRadius, transform: nil))
        // 마디마다 옅기를 다르게 했더니 배터리 눈금처럼 읽혔다 — 전부 흰색으로 둔다.
        _ = index
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fillPath()

        top -= h + gap
    }
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    ctx.interpolationQuality = .high
    draw(into: ctx)
    return rep.representation(using: .png, properties: [:])!
}

// 스크립트 위치 기준으로 레포 루트를 찾는다.
let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // icon
    .deletingLastPathComponent()  // design
    .deletingLastPathComponent()  // docs
    .deletingLastPathComponent()  // repo
let set = repo.appending(path: "Madi/UI/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

// macOS 아이콘 칸: 16 · 32 · 128 · 256 · 512 포인트, 각각 1x · 2x
let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var images: [[String: String]] = []
for slot in slots {
    let pixels = slot.points * slot.scale
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    try render(size: pixels).write(to: set.appending(path: name))
    images.append([
        "filename": name, "idiom": "mac",
        "scale": "\(slot.scale)x", "size": "\(slot.points)x\(slot.points)",
    ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appending(path: "Contents.json"))
let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted])
    .write(to: repo.appending(path: "Madi/UI/Assets.xcassets/Contents.json"))

// 검토용 큰 그림 한 장
try render(size: 1024).write(to: repo.appending(path: "docs/design/icon/app-icon-1024.png"))
print("아이콘 \(slots.count)장 → \(set.path)")
