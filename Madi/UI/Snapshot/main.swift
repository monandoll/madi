import AppKit
import QuartzCore
import SwiftUI

// 화면을 PNG 로 뜬다. `#Preview` 를 Xcode 에서 보는 것과 별개로, 확정된 화면은 파일로 남아야
// 사람이 확인하고 커밋에 붙일 수 있다 (docs/prompts/design-ai.md).
//
// Xcode 프리뷰 캔버스를 캡처할 방법이 없어서 같은 뷰를 **진짜 NSWindow 에 띄우고** 찍는다.
// 그래서 나오는 그림은 프리뷰 근사치가 아니라 실제 AppKit 이 그린 창이다 — 툴바 · 사이드바
// 재질 · 인스펙터 분리선까지 실물과 같다.
//
//   madi-ui-shots <출력 폴더>
//
// 모든 화면을 1440×900 과 1100×700 두 크기로 뜬다. 1100×700 은 창 최소 크기다.

struct Shot {
    var name: String
    var view: AnyView
    /// 첫 실행 창처럼 크기가 고정인 화면은 여기에 적는다. 비면 두 기본 크기로 찍는다.
    var sizes: [CGSize]?
}

let defaultSizes = [Tokens.Size.windowIdeal, Tokens.Size.windowMin]

let shots: [Shot] = [
    Shot(name: "gallery-loaded", view: AnyView(
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            selectedShotID: SampleData.shotsToday[0].id
        )
    ), sizes: nil),
    Shot(name: "gallery-empty", view: AnyView(
        RootView(studio: SampleData.studioEmpty, gallery: .empty)
    ), sizes: nil),
    Shot(name: "gallery-importing", view: AnyView(
        RootView(
            studio: SampleData.studio,
            gallery: .importing(done: 3, total: 7, groups: SampleData.importingGroups)
        )
    ), sizes: nil),
    Shot(name: "gallery-loading", view: AnyView(
        RootView(studio: SampleData.studio, gallery: .loading)
    ), sizes: nil),
    Shot(name: "gallery-no-access", view: AnyView(
        RootView(studio: SampleData.studioEmpty, gallery: .noPhotoAccess)
    ), sizes: nil),
]

// MARK: - 찍기

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("사용법: madi-ui-shots <출력 폴더>\n".utf8))
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// 사이드바 · 인스펙터의 재질은 **앱 appearance** 를 따라간다. 창에만 걸면 다크 모드 Mac 에서
// 사이드바가 검게 찍힌다. 라이트 모드만 만들기로 했으므로 (AGENTS.md §16) 앱째로 고정한다.
app.appearance = NSAppearance(named: .aqua)

/// 사이드바 · 툴바의 재질(`NSVisualEffectView`)은 윈도우 서버가 그리는 것이라
/// 뷰를 떠도 안 따라오고 그 자리가 **검게** 남는다. 스크린샷용으로만 단색을 깔아 둔다.
/// 앱 코드는 그대로 재질을 쓴다 — 여기서 바꾸는 것은 찍는 순간의 창뿐이다.
@MainActor
func fillMaterials(_ view: NSView) {
    if let effect = view as? NSVisualEffectView {
        // 핵심은 이 줄이다. `behindWindow` 는 윈도우 서버가 창 **뒤**를 섞어 그리는 것이라
        // 뷰를 떠도 아무것도 안 따라온다 (사이드바가 통째로 비어 나온다).
        // `withinWindow` 로 바꾸면 창 안에서 그려져서 그대로 찍힌다.
        effect.blendingMode = .withinWindow
        effect.state = .inactive
        effect.material = .windowBackground
        effect.wantsLayer = true
        effect.layer?.backgroundColor = NSAppearance(named: .aqua).map { appearance in
            var color = CGColor(gray: 0.93, alpha: 1)
            appearance.performAsCurrentDrawingAppearance {
                color = NSColor.windowBackgroundColor.cgColor
            }
            return color
        } ?? CGColor(gray: 0.93, alpha: 1)
    }
    for subview in view.subviews { fillMaterials(subview) }
}

/// `displayIgnoringOpacity` 로 안 따라오는 부분을 레이어로 다시 그린다.
///
/// SwiftUI 의 사이드바 목록(`SwiftUIOutlineListView`)은 AppKit 테이블 안에 SwiftUI 를 또 얹은
/// 구조라 뷰 그리기 경로로는 빈 채로 나온다. 뷰 계층에는 멀쩡히 있다(행이 제 높이로 잡혀 있다)
/// — 그리기만 안 따라온다. 그래서 그 subtree 만 레이어를 직접 그려 넣는다.
/// 화면 전체 레이어를 그리면 정보 패널이 흰색으로 덮이므로 **거기만** 한다.
@MainActor
func overlayLayerOnly(_ view: NSView, root: NSView, context: CGContext) {
    let name = String(describing: type(of: view))
    let needsLayerPass = name.contains("OutlineListView")
    if needsLayerPass, let layer = view.layer {
        // `render(in:)` 은 이미 그려진 레이어 내용만 베낀다. 아직 안 그려진 행은 빈 채로 나오고,
        // 그래서 창 크기에 따라 어떤 판은 행이 하나만 찍혔다. 먼저 전부 그리게 시킨다.
        func prime(_ l: CALayer) {
            l.displayIfNeeded()
            l.sublayers?.forEach(prime)
        }
        prime(layer)
        let frame = view.convert(view.bounds, to: root)
        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        context.restoreGState()
        return
    }
    for sub in view.subviews { overlayLayerOnly(sub, root: root, context: context) }
}

/// 창을 띄우고 한 박자 쉬었다가 통째로 뜬다.
/// 쉬는 이유: 사이드바 · 인스펙터가 첫 레이아웃 뒤에 한 번 더 자리를 잡고,
/// 썸네일 그림도 그때 올라온다. 바로 찍으면 회색 자리표시만 찍힌다.
@MainActor
func capture(_ shot: Shot, size: CGSize) -> Data? {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.contentView = NSHostingView(rootView: shot.view)
    window.title = Copy.App.galleryWindowTitle
    window.setContentSize(size)
    // 라이트 모드만 만든다 (AGENTS.md §16). 찍는 Mac 이 다크 모드여도 화면은 라이트로 남아야 한다.
    window.appearance = NSAppearance(named: .aqua)
    window.makeKeyAndOrderFront(nil)

    RunLoop.main.run(until: Date().addingTimeInterval(1.2))

    // 타이틀바(툴바)까지 같이 뜨려면 콘텐츠 뷰가 아니라 그 위의 프레임 뷰를 찍어야 한다.
    guard let frameView = window.contentView?.superview else { return nil }
    fillMaterials(frameView)
    let bounds = frameView.bounds
    // 1x 로 뜬다. 레티나(2x)로 뜨면 한 장에 2MB 가까이 나와서 화면이 늘수록 레포가 무거워진다.
    // 보는 목적은 배치 확인이라 1x 로 충분하다.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = bounds.size
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    func render(into target: NSGraphicsContext?) {
        guard let scratch = target ?? NSGraphicsContext(bitmapImageRep: rep) else { return }
        window.displayIfNeeded()
        CATransaction.flush()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = scratch
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        frameView.displayIgnoringOpacity(bounds, in: scratch)
        overlayLayerOnly(frameView, root: frameView, context: scratch.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        // 비트맵으로 내려보내야 아래에서 픽셀을 읽을 수 있다.
        scratch.flushGraphics()
    }

    // 사이드바 · 인스펙터의 재질(NSVisualEffectView)은 윈도우 서버가 그리는 것이라
    // 뷰를 통째로 뜨면 그 자리가 **검게** 남는다. 그래서 (1) 창 배경색을 먼저 깔고
    // (2) `cacheDisplay` 대신 `displayIgnoringOpacity` 로 그 위에 겹쳐 그린다.
    // `cacheDisplay` 는 비트맵을 지우고 시작해서 깔아 둔 배경이 날아간다.
    // 즉 **재질의 반투명 느낌은 이 PNG 에 없다** — 실제 앱에서는 사이드바가 살짝 비친다.
    // 사이드바 목록은 첫 판에 비어 나온다. 창 크기 · 타이밍에 따라 두 판째도 빌 때가 있어서
    // 몇 판 돌리고 마지막 판을 쓴다. (찍히는 것은 여전히 진짜 창이다 — 덜 그려진 판을 안 쓸 뿐이다.)
    // 비트맵을 직접 읽어 "다 그려졌나" 를 검사해 보려 했지만, 그래픽 컨텍스트가 붙어 있는 동안에는
    // 픽셀이 계속 검정으로 읽혀서 검사가 안 된다. 그래서 횟수로 민다.
    for _ in 0..<4 {
        render(into: context)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    window.orderOut(nil)

    return rep.representation(using: .png, properties: [:])
}

MainActor.assumeIsolated {
    for shot in shots {
        for size in shot.sizes ?? defaultSizes {
            let name = "\(shot.name)-\(Int(size.width))x\(Int(size.height)).png"
            guard let data = capture(shot, size: size) else {
                FileHandle.standardError.write(Data("못 찍음: \(name)\n".utf8))
                continue
            }
            let url = outputDirectory.appending(path: name)
            try? data.write(to: url)
            print(name)
        }
    }
}

exit(0)
