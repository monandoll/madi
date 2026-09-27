// 앱 아이콘 방향 셋을 그린다 — 고르기 전 비교용 (2026-09-28 사용자 기준).
//
//   swiftc -O -o /tmp/make-icon-directions docs/design/icon/make-icon-directions.swift && /tmp/make-icon-directions
//
// 기준 (decisions.md 6단계 "물어본 것과 답" 1):
// - 한눈에 **영상 편집 툴** 로 보이고, **마디**(컷으로 나뉜 조각) 컨셉이 얹혀야 한다
// - 나중에 롱폼도 한다 — **9:16 세로 숏폼 전용으로 보이면 안 된다**
// - 재생 ▶ 금지 · 막대 나열만 있는 것 금지 · **16px 에서도 알아보게** · 색은 초록에 묶이지 않고 각자 어울리게
//
// 나오는 것 (docs/design/icon/):
//   direction-1-timeline.png · direction-2-filmstrip.png · direction-3-cut.png  (1024)
//   directions-sheet.png  — 셋을 나란히, 크기별(256 · 64 · 32 · 16) 로. 작은 크기는 줄인 그림이 아니라 그 크기로 다시 그린 것이다

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

// MARK: - 1. 타임라인

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

// MARK: - 2. 필름 스트립

/// 구멍 줄 있는 필름이 **길이가 다른 조각**으로 잘려 틈이 벌어져 있다. 비스듬히 놓아 가로 · 세로 어느 비율에도 묶이지 않는다.
func drawFilmStrip(_ ctx: CGContext) {
    iconBody(ctx, top: 0xFFF3E2, bottom: 0xF3D9B8) { r in
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY)
        ctx.rotate(by: -.pi / 7)
        let h: CGFloat = 250
        let lengths: [CGFloat] = [250, 160, 205]
        let gap: CGFloat = 40
        let total = lengths.reduce(0, +) + gap * 2
        var x = -total / 2
        let frameColors: [UInt32] = [0xFF8A4C, 0x3FA7D6, 0xE0457B]
        for (i, len) in lengths.enumerated() {
            let piece = CGRect(x: x, y: -h / 2, width: len, height: h)
            // 조각마다 살짝 어긋나게 — 잘려서 벌어진 느낌
            let dy: CGFloat = [0, 14, -10][i]
            let p = piece.offsetBy(dx: 0, dy: dy)
            roundRect(ctx, p, 14, rgb(0x23202A))
            // 구멍 줄 (위 · 아래)
            let hole = CGSize(width: 26, height: 26)
            var hx = p.minX + 20
            while hx + hole.width < p.maxX - 10 {
                roundRect(ctx, CGRect(x: hx, y: p.maxY - 18 - hole.height, width: hole.width, height: hole.height), 6, rgb(0xFFF3E2))
                roundRect(ctx, CGRect(x: hx, y: p.minY + 18, width: hole.width, height: hole.height), 6, rgb(0xFFF3E2))
                hx += 48
            }
            // 칸 (영상 한 컷)
            let frame = CGRect(x: p.minX + 20, y: p.minY + 60, width: p.width - 40, height: p.height - 120)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.clip()
            let g = CGGradient(colorsSpace: space, colors: [rgb(frameColors[i]), rgb(frameColors[i], 0.72)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: frame.minX, y: frame.maxY), end: CGPoint(x: frame.maxX, y: frame.minY), options: [])
            ctx.restoreGState()
            x += len + gap
        }
        ctx.restoreGState()
    }
}

// MARK: - 3. 컷

/// 영상 화면 틀(비율 중립 — 거의 네모)을 **컷 선** 두 줄이 비스듬히 가르고, 조각이 살짝 어긋나 있다.
func drawCut(_ ctx: CGContext) {
    iconBody(ctx, top: 0x4C7DFF, bottom: 0x2140B8) { r in
        let screen = CGRect(x: r.midX - 270, y: r.midY - 230, width: 540, height: 460)
        let screenPath = CGPath(roundedRect: screen, cornerWidth: 64, cornerHeight: 64, transform: nil)
        // 컷 선 — 비스듬히 두 줄. 조각 셋을 다각형으로 잘라 어긋나게 옮긴다
        let slant: CGFloat = 70
        let cuts: [CGFloat] = [screen.minX + 190, screen.minX + 360]
        let cutGap: CGFloat = 26
        let offsets: [CGPoint] = [CGPoint(x: -26, y: 22), CGPoint(x: 0, y: -18), CGPoint(x: 26, y: 24)]
        let edges: [(CGFloat, CGFloat)] = [
            (screen.minX - 100, cuts[0] - cutGap / 2),
            (cuts[0] + cutGap / 2, cuts[1] - cutGap / 2),
            (cuts[1] + cutGap / 2, screen.maxX + 100),
        ]
        for (i, e) in edges.enumerated() {
            ctx.saveGState()
            ctx.translateBy(x: offsets[i].x, y: offsets[i].y)
            // 이 조각의 영역 (비스듬한 띠)
            let band = CGMutablePath()
            band.move(to: CGPoint(x: e.0 - slant, y: screen.minY - 40))
            band.addLine(to: CGPoint(x: e.1 - slant, y: screen.minY - 40))
            band.addLine(to: CGPoint(x: e.1 + slant, y: screen.maxY + 40))
            band.addLine(to: CGPoint(x: e.0 + slant, y: screen.maxY + 40))
            band.closeSubpath()
            ctx.addPath(band); ctx.clip()
            // 틀 — 흰 테두리 + 안쪽 화면
            ctx.addPath(screenPath); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
            let inner = screen.insetBy(dx: 34, dy: 34)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: inner, cornerWidth: 36, cornerHeight: 36, transform: nil)); ctx.clip()
            let g = CGGradient(colorsSpace: space, colors: [rgb(0xFFD36E), rgb(0xFF8E6B)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: inner.minX, y: inner.maxY), end: CGPoint(x: inner.maxX, y: inner.minY), options: [])
            // 화면 아래 탐색 막대 — 영상 플레이어로 읽히게 (▶ 없이). 컷을 가로질러 어긋남이 보인다
            let bar = CGRect(x: inner.minX + 36, y: inner.minY + 44, width: inner.width - 72, height: 22)
            roundRect(ctx, bar, 11, rgb(0xFFFFFF, 0.45))
            roundRect(ctx, CGRect(x: bar.minX, y: bar.minY, width: bar.width * 0.62, height: bar.height), 11, rgb(0xFFFFFF))
            ctx.setFillColor(rgb(0xFFFFFF))
            ctx.fillEllipse(in: CGRect(x: bar.minX + bar.width * 0.62 - 24, y: bar.midY - 24, width: 48, height: 48))
            ctx.restoreGState()
            ctx.restoreGState()
        }
    }
}

// MARK: - 내보내기

func render(_ size: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let dir = "docs/design/icon"
let directions: [(String, String, (CGContext) -> Void)] = [
    ("1 타임라인", "direction-1-timeline", drawTimeline),
    ("2 필름 스트립", "direction-2-filmstrip", drawFilmStrip),
    ("3 컷", "direction-3-cut", drawCut),
]
for d in directions { write(render(1024, d.2), "\(dir)/\(d.1).png") }

// 비교 시트 — 셋을 나란히. 크기별로 다시 그린다 (16px 에서도 알아보는지).
let colW: CGFloat = 520, sheetH: CGFloat = 560
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(colW) * 3, pixelsHigh: Int(sheetH), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: colW * 3, height: sheetH).fill()
for (i, d) in directions.enumerated() {
    let x0 = CGFloat(i) * colW
    let title = NSAttributedString(string: d.0, attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.black])
    title.draw(at: NSPoint(x: x0 + 32, y: sheetH - 52))
    NSImage(cgImage: render(256, d.2).cgImage!, size: NSSize(width: 256, height: 256))
        .draw(in: NSRect(x: x0 + 32, y: sheetH - 330, width: 256, height: 256))
    var sx = x0 + 32
    for s in [64, 32, 16] {
        let img = NSImage(cgImage: render(s, d.2).cgImage!, size: NSSize(width: s, height: s))
        img.draw(in: NSRect(x: sx, y: 120, width: CGFloat(s), height: CGFloat(s)))
        NSAttributedString(string: "\(s)", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray])
            .draw(at: NSPoint(x: sx, y: 96))
        sx += CGFloat(s) + 40
    }
    // 어두운 바탕 위 16 · 32 (메뉴 막대 · Dock 이 어두울 때)
    NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
    NSRect(x: x0 + 300, y: 110, width: 190, height: 90).fill()
    NSImage(cgImage: render(32, d.2).cgImage!, size: NSSize(width: 32, height: 32)).draw(in: NSRect(x: x0 + 330, y: 140, width: 32, height: 32))
    NSImage(cgImage: render(16, d.2).cgImage!, size: NSSize(width: 16, height: 16)).draw(in: NSRect(x: x0 + 400, y: 148, width: 16, height: 16))
}
NSGraphicsContext.restoreGraphicsState()
write(sheet, "\(dir)/directions-sheet.png")
print("\(dir)/directions-sheet.png")
