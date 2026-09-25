import AppKit
import QuartzCore
import SwiftUI

// 화면을 PNG 로 뜬다. `#Preview` 를 Xcode 에서 보는 것과 별개로, 확정된 화면은 파일로 남아야
// 사람이 확인하고 커밋에 붙일 수 있다 (docs/prompts/design-ai.md).
//
//   madi-ui-shots <출력 폴더>
//   madi-ui-shots --권한            화면 기록 권한을 요청한다 (한 번만)
//
// 모든 화면을 1440×900 과 1100×700 두 크기로 뜬다. 1100×700 은 창 최소 크기다.
//
// ## 뜨는 방법이 둘이다
//
// 1. **화면 기록 권한이 있으면** 진짜 창을 그대로 뜬다. 재질 · 반투명 · 그림자가 실물과 같다.
//    재생 막대 · 채팅 말풍선처럼 재질로 판단해야 하는 화면은 이 방법이어야 한다.
// 2. 권한이 없으면 뷰 계층을 직접 그린다. 배치 · 문구는 맞지만 재질이 단색으로 나오고
//    세그먼트에서 고른 칸의 글자가 빠진다. **그 경우 그림 아래에 한 줄로 그렇게 적는다** —
//    나중에 그림만 보고 "사이드바 색이 왜 이래" 를 헷갈리지 않게.

struct Shot {
    var name: String
    var view: AnyView
    /// 첫 실행 창처럼 크기가 고정인 화면은 여기에 적는다. 비면 두 기본 크기로 찍는다.
    var sizes: [CGSize]?

    init(_ name: String, sizes: [CGSize]? = nil, @ViewBuilder view: () -> some View) {
        self.name = name
        self.view = AnyView(view())
        self.sizes = sizes
    }
}

let defaultSizes = [Tokens.Size.windowIdeal, Tokens.Size.windowMin]

let shots: [Shot] = [
    Shot("gallery-loaded") {
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            selectedShotID: SampleData.shotsToday[0].id
        )
    },
    Shot("gallery-empty") {
        RootView(studio: SampleData.studioEmpty, gallery: .empty)
    },
    Shot("gallery-importing") {
        RootView(
            studio: SampleData.studio,
            gallery: .importing(done: 3, total: 7, groups: SampleData.importingGroups)
        )
    },
    Shot("gallery-loading") {
        RootView(studio: SampleData.studio, gallery: .loading)
    },
    Shot("gallery-no-access") {
        RootView(studio: SampleData.studioEmpty, gallery: .noPhotoAccess)
    },
    Shot("gallery-hidden") {
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            galleryNotice: Copy.Gallery.Hidden.notice
        )
    },
    Shot("plan-ready") {
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            plan: .ready(SampleData.plan),
            planMessages: SampleData.chat,
            planChips: SampleData.chatChips,
            opensPlan: true,
            selectedSceneID: "s4"
        )
    },
    Shot("plan-editing-caption") {
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            plan: .ready(SampleData.plan),
            planMessages: SampleData.chat,
            planChips: SampleData.chatChips,
            opensPlan: true,
            selectedSceneID: "s4",
            editingSceneID: "s4"
        )
    },
    Shot("plan-preparing") {
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            plan: .preparing(SampleData.prepareSteps),
            planMessages: SampleData.chatPreparing,
            planChips: SampleData.chatChips,
            opensPlan: true
        )
    },
    Shot("plan-stuck") {
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            plan: .ready(SampleData.planNoCaptions),
            planMessages: SampleData.chatStuck,
            planChips: SampleData.chatChips,
            opensPlan: true,
            selectedSceneID: "n2"
        )
    },
    Shot("plan-unsure-reframe") {
        RootView(
            studio: SampleData.studio,
            gallery: .loaded(SampleData.groups),
            plan: .ready(SampleData.plan),
            planMessages: SampleData.chatUnsureReframe,
            planChips: SampleData.chatChips,
            opensPlan: true,
            selectedSceneID: "s6"
        )
    },
    Shot("plan-no-ai") {
        RootView(
            studio: SampleData.studioNoAI,
            gallery: .loaded(SampleData.groups),
            plan: .noAI,
            opensPlan: true
        )
    },
]

// MARK: - 들어가기

let arguments = CommandLine.arguments

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// 사이드바 · 인스펙터의 재질은 **앱 appearance** 를 따라간다. 창에만 걸면 다크 모드 Mac 에서
// 사이드바가 검게 찍힌다. 라이트 모드만 만들기로 했으므로 (AGENTS.md §16) 앱째로 고정한다.
app.appearance = NSAppearance(named: .aqua)

if arguments.contains("--권한") || arguments.contains("--ask-permission") {
    let granted = CGRequestScreenCaptureAccess()
    print(granted
        ? "권한 있음. 이제 진짜 창을 그대로 뜬다."
        : "시스템 설정 > 개인정보 보호 및 보안 > 화면 기록 에서 터미널을 켠 뒤 터미널을 다시 연다.")
    exit(granted ? 0 : 1)
}

guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("사용법: madi-ui-shots <출력 폴더> | --권한\n".utf8))
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canRecordScreen = CGPreflightScreenCaptureAccess()
print(canRecordScreen
    ? "화면 기록 권한 있음 — 진짜 창을 뜬다"
    : "화면 기록 권한 없음 — 뷰를 그려서 뜬다 (재질이 단색). `madi-ui-shots --권한` 으로 요청한다")

// MARK: - 뷰를 직접 그리는 길 (권한 없을 때)

/// 사이드바 · 툴바의 재질(`NSVisualEffectView`)은 창 **뒤**를 섞어 그리는 것이라
/// 뷰를 떠도 아무것도 안 따라오고 그 자리가 검게 남는다.
/// 창 안에서 그리도록 바꿔 두면 그대로 찍힌다. 스크린샷용이고 앱 코드는 건드리지 않는다.
@MainActor
func fillMaterials(_ view: NSView) {
    if let effect = view as? NSVisualEffectView {
        effect.blendingMode = .withinWindow
        effect.state = .inactive
        effect.material = .windowBackground
    }
    for subview in view.subviews { fillMaterials(subview) }
}

/// SwiftUI 의 사이드바 목록(`SwiftUIOutlineListView`)은 AppKit 테이블 안에 SwiftUI 를 또 얹은
/// 구조라 뷰 그리기 경로로는 빈 채로 나온다. 뷰 계층에는 멀쩡히 있다 — 그리기만 안 따라온다.
/// 그래서 그 subtree 만 레이어를 직접 그려 넣는다.
/// 화면 전체 레이어를 그리면 정보 패널이 흰색으로 덮이므로 **거기만** 한다.
@MainActor
func overlayLayerOnly(_ view: NSView, root: NSView, context: CGContext) {
    if String(describing: type(of: view)).contains("OutlineListView"), let layer = view.layer {
        // `render(in:)` 은 이미 그려진 레이어만 베낀다. 아직 안 그려진 행은 빈 채로 나온다.
        func prime(_ layer: CALayer) {
            layer.displayIfNeeded()
            layer.sublayers?.forEach(prime)
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
    for subview in view.subviews { overlayLayerOnly(subview, root: root, context: context) }
}

// MARK: - 찍기

/// 창을 띄우고 한 박자 쉬었다가 뜬다.
/// 쉬는 이유: 사이드바 · 인스펙터가 첫 레이아웃 뒤에 한 번 더 자리를 잡고,
/// 썸네일 그림도 그때 올라온다. 바로 찍으면 회색 자리표시만 찍힌다.
@MainActor
func capture(_ shot: Shot, size: CGSize) -> NSBitmapImageRep? {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.contentView = NSHostingView(rootView: shot.view)
    window.title = Copy.App.galleryWindowTitle
    window.setContentSize(size)
    window.appearance = NSAppearance(named: .aqua)
    window.center()
    window.makeKeyAndOrderFront(nil)
    // 앞으로 올리려고 해도 macOS 14 는 사용자가 띄우지 않은 앱의 활성화를 막는다.
    // 그래서 창은 **비활성 상태로** 찍힌다 — 툴바 버튼과 제목이 회색이다.
    // 본문(인스펙터 · 버튼)은 tint 를 그대로 쓰므로 색이 맞고, 툴바만 다르다.
    app.activate(ignoringOtherApps: true)

    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    window.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    defer { window.orderOut(nil) }

    return canRecordScreen ? captureRealWindow(window) : drawViewTree(of: window, size: size)
}

/// 권한이 있을 때 — 창을 화면에서 그대로 뜬다. 실물이다.
@MainActor
func captureRealWindow(_ window: NSWindow) -> NSBitmapImageRep? {
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(window.windowNumber),
        [.boundsIgnoreFraming, .bestResolution]
    ) else { return nil }
    return NSBitmapImageRep(cgImage: image)
}

/// 권한이 없을 때 — 뷰 계층을 직접 그린다.
@MainActor
func drawViewTree(of window: NSWindow, size: CGSize) -> NSBitmapImageRep? {
    guard let frameView = window.contentView?.superview else { return nil }
    fillMaterials(frameView)
    let bounds = frameView.bounds

    // 1x 로 뜬다. 레티나(2x)로 뜨면 한 장에 2MB 가까이 나와서 화면이 늘수록 레포가 무거워진다.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = bounds.size
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    // 사이드바 목록은 첫 판에 비어 나온다. 창 크기 · 타이밍에 따라 두 판째도 빌 때가 있어서
    // 몇 판 돌리고 마지막 판을 쓴다. 비트맵을 읽어 검사해 보려 했지만 그래픽 컨텍스트가
    // 붙어 있는 동안에는 픽셀이 계속 검정으로 읽혀서 검사가 안 된다. 그래서 횟수로 민다.
    for _ in 0..<4 {
        window.displayIfNeeded()
        CATransaction.flush()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        frameView.displayIgnoringOpacity(bounds, in: context)
        overlayLayerOnly(frameView, root: frameView, context: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
    return rep
}

/// 뷰를 그려서 뜬 그림에는 **아래에 한 줄을 붙인다.** 나중에 그림만 보고
/// 실물과 다른 부분을 진짜라고 읽지 않게, 무엇이 다른지 그림 안에 적어 둔다.
@MainActor
func withCaveat(_ rep: NSBitmapImageRep) -> Data? {
    let note = "⚠︎ 뷰를 그려서 뜬 그림 — 사이드바·툴바 재질이 단색이고, 고른 세그먼트의 글자가 빠진다."
        + "  실물은 화면 기록 권한을 켜고 다시 뜬다 (madi-ui-shots --권한)."
    let stripHeight: CGFloat = 24
    let width = rep.size.width
    let height = rep.size.height + stripHeight

    let canvas = NSImage(size: CGSize(width: width, height: height))
    canvas.lockFocusFlipped(false)
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: width, height: stripHeight).fill()
        rep.draw(in: CGRect(x: 0, y: stripHeight, width: width, height: rep.size.height))

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        note.draw(
            in: CGRect(x: 10, y: 5, width: width - 20, height: stripHeight - 7),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1),
                .paragraphStyle: style,
            ]
        )
    }
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let flattened = NSBitmapImageRep(data: tiff) else { return nil }
    return flattened.representation(using: .png, properties: [:])
}

MainActor.assumeIsolated {
    for shot in shots {
        for size in shot.sizes ?? defaultSizes {
            let name = "\(shot.name)-\(Int(size.width))x\(Int(size.height)).png"
            guard let rep = capture(shot, size: size) else {
                FileHandle.standardError.write(Data("못 찍음: \(name)\n".utf8))
                continue
            }
            let data = canRecordScreen
                ? rep.representation(using: .png, properties: [:])
                : withCaveat(rep)
            guard let data else {
                FileHandle.standardError.write(Data("못 만듦: \(name)\n".utf8))
                continue
            }
            try? data.write(to: outputDirectory.appending(path: name))
            print(name)
        }
    }
}

exit(0)
