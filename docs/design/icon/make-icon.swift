// 앱 아이콘 — **확정본: 1번 타임라인** (2026-09-28, 방향 셋 중 사용자가 골랐다).
//
//   swiftc -O -o /tmp/make-icon docs/design/icon/make-icon.swift && /tmp/make-icon
//
// 쓰는 곳:
//   Madi/UI/Assets.xcassets/AppIcon.appiconset/  — macOS 칸 10장 (16 · 32 · 128 · 256 · 512, 각 1x · 2x)
//   docs/design/icon/app-icon-1024.png           — 검토용 큰 그림
//
// 뜻: 길이가 다른 클립 블록이 **컷(틈)** 으로 나뉘어 한 줄로 있고 재생 헤드가 가로지른다.
// 한눈에 영상 편집 툴이고, 컷으로 나뉜 조각이 곧 "마디" 다. 가로 트랙이라 세로 숏폼에 묶이지 않는다
// — 롱폼(7단계)이 와도 그대로 쓴다.
//
// 그리기는 `make-icon-directions.swift` 의 `drawTimeline` 과 **같은 코드**다. 그 파일은 셋을 견주던
// 시트용이고 여기가 확정본이다. 모양을 고치면 이쪽을 고친다.
//
// 작은 칸은 1024 를 줄인 그림이 아니라 **그 픽셀 크기로 다시 그린** 것이다 — 16px 에서도 선이 뭉개지지 않는다.

import AppKit

let canvas: CGFloat = 1024
let body: CGFloat = 824
let inset = (canvas - body) / 2
let radius: CGFloat = 186

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// macOS 아이콘 몸통 — 둥근 네모 + 그림자 + 위가 밝은 바탕. 안쪽 그리기는 몸통에 잘린다.
func iconBody(_ ctx: CGContext, top: UInt32, bottom: UInt32, inside: (CGRect) -> Void) {
    let rect = CGRect(x: inset, y: inset + 10, width: body, height: body)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.28))
    ctx.addPath(path); ctx.setFillColor(rgb(bottom)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    inside(rect)
    ctx.restoreGState()
}

func roundRect(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil))
    ctx.setFillColor(color); ctx.fillPath()
}

/// 길이가 다른 클립 블록이 **컷(틈)** 으로 나뉘어 한 줄로 있고, 재생 헤드 하나가 가로지른다.
/// 편집 툴의 타임라인 그대로다 — 가로 트랙이라 세로 숏폼에 묶이지 않는다. 블록은 영상 조각이라 위에 옅은 "화면" 줄을 판다.
func drawTimeline(_ ctx: CGContext) {
    iconBody(ctx, top: 0x2E3558, bottom: 0x171B31) { r in
        let trackY = r.midY - 80
        let trackH: CGFloat = 170
        let widths: [CGFloat] = [160, 96, 206, 118]
        let colors: [(UInt32, UInt32)] = [(0xFF7A5C, 0xE8553A), (0xFFC14D, 0xF09E1B), (0x5CB8FF, 0x2F8EE8), (0xA88BFF, 0x7E5CF0)]
        let gap: CGFloat = 20
        let total = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
        var x = r.midX - total / 2
        for (w, c) in zip(widths, colors) {
            let block = CGRect(x: x, y: trackY, width: w, height: trackH)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: block, cornerWidth: 26, cornerHeight: 26, transform: nil))
            ctx.clip()
            let g = CGGradient(colorsSpace: space, colors: [rgb(c.0), rgb(c.1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: block.maxY), end: CGPoint(x: 0, y: block.minY), options: [])
            // 클립 안의 "화면" — 위쪽에 옅은 띠 (영상 조각으로 읽히게, 막대 나열이 아니게)
            roundRect(ctx, CGRect(x: block.minX + 14, y: block.maxY - 14 - 56, width: block.width - 28, height: 56), 12, rgb(0xFFFFFF, 0.28))
            ctx.restoreGState()
            x += w + gap
        }
        // 아래 오디오 트랙 — 얇은 한 줄 (편집 툴로 읽히게)
        roundRect(ctx, CGRect(x: r.midX - total / 2, y: trackY - 30 - 50, width: total, height: 50), 16, rgb(0xFFFFFF, 0.14))
        // 재생 헤드 — 흰 세로선 + 위 머리
        let headX = r.midX - total / 2 + 160 + gap + 96 + gap + 80
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fill(CGRect(x: headX - 8, y: trackY - 30 - 50 - 26, width: 16, height: trackH + 30 + 50 + 26 + 60))
        let top = trackY + trackH + 60
        ctx.move(to: CGPoint(x: headX - 46, y: top + 56))
        ctx.addLine(to: CGPoint(x: headX + 46, y: top + 56))
        ctx.addLine(to: CGPoint(x: headX + 46, y: top + 14))
        ctx.addLine(to: CGPoint(x: headX, y: top - 20))
        ctx.addLine(to: CGPoint(x: headX - 46, y: top + 14))
        ctx.closePath(); ctx.fillPath()
    }
}

/// 그 픽셀 크기로 다시 그린다 (줄이지 않는다).
func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawTimeline(ctx)
    NSGraphicsContext.restoreGraphicsState()
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

let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var images: [[String: String]] = []
for slot in slots {
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    try render(slot.points * slot.scale).write(to: set.appending(path: name))
    images.append([
        "filename": name, "idiom": "mac",
        "scale": "\(slot.scale)x", "size": "\(slot.points)x\(slot.points)",
    ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appending(path: "Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted])
    .write(to: repo.appending(path: "Madi/UI/Assets.xcassets/Contents.json"))

try render(1024).write(to: repo.appending(path: "docs/design/icon/app-icon-1024.png"))
print("아이콘 \(slots.count)장 → \(set.path)")
