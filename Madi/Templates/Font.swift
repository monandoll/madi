import Foundation
import CoreText
import CoreGraphics
import os

/// Pretendard Variable 을 프레임워크 번들에서 등록하고, `wght` 축을 지정해 꺼낸다.
///
/// 가변 폰트는 축을 **명시하지 않으면 기본 웨이트(Regular)로 그려진다.**
/// 자막이 Regular 로 나오면 원본과 전혀 다른 인상이 되므로 여기서 한 곳에 가둔다
/// (docs/stage-0.spec.md 알려진 함정).
public enum MadiFont {
    private static let log = Logger(subsystem: "app.madi", category: "font")

    /// OpenType `wght` 가변 축 태그.
    private static let weightAxisTag: UInt32 = 0x77676874 // 'wght'

    /// 번들 등록은 한 번만. `registeredName` 이 nil 이면 등록에 실패한 것이다.
    private static let registeredName: String? = {
        let bundle = Bundle(for: FontBundleToken.self)
        guard let url = bundle.url(forResource: "PretendardVariable", withExtension: "ttf") else {
            log.error("PretendardVariable.ttf 를 번들에서 찾지 못했습니다")
            return nil
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // 같은 프로세스에서 이미 등록됐으면 실패가 아니다.
            let code = (error?.takeRetainedValue() as Error?).map { ($0 as NSError).code } ?? -1
            if code != Int(CTFontManagerError.alreadyRegistered.rawValue) {
                log.error("폰트 등록 실패 (code \(code))")
                return nil
            }
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        else {
            log.error("등록한 폰트의 PostScript 이름을 읽지 못했습니다")
            return nil
        }
        return name
    }()

    /// 지정한 웨이트·크기의 Pretendard. 측정 도구와 테스트가 기준 글꼴로 쓴다.
    ///
    /// - Parameters:
    ///   - size: 포인트(=픽셀, `contentsScale` 1 로 그리므로).
    ///   - weight: `wght` 축 값. 400 Regular · 700 Bold · 800 ExtraBold · 900 Black.
    ///   - italic: Pretendard Variable 에는 기울임 축이 없다. true 면 **기울임 변환**으로 흉내 낸다.
    public static func pretendard(
        size: CGFloat, weight: CGFloat, italic: Bool = false, slantDeg: CGFloat = 10
    ) -> CTFont {
        font(family: nil, size: size, weight: weight, italic: italic, slantDeg: slantDeg)
    }

    /// 스타일 `look` 이 고른 글꼴. **자막을 그리는 글꼴은 전부 여기서 나온다.**
    ///
    /// - Parameters:
    ///   - family: 패밀리 이름. `nil` 이면 번들 Pretendard.
    ///   - weight: 100~900. 가변 글꼴이면 `wght` 축에, 아니면 가장 가까운 굵기의 자형을 고른다.
    ///   - italic: 이탤릭 자형이 있으면 그걸 쓰고, 없으면 `slantDeg` 만큼 기울인다.
    public static func font(
        family: String?, size: CGFloat, weight: CGFloat, italic: Bool, slantDeg: CGFloat
    ) -> CTFont {
        var slant = CGAffineTransform(a: 1, b: 0, c: tan(slantDeg * .pi / 180), d: 1, tx: 0, ty: 0)

        guard let family else {
            guard let name = registeredName else {
                // 폰트가 없으면 조용히 다른 글꼴로 그리지 않는다. 눈에 띄게 만든다.
                log.fault("Pretendard 를 못 써서 시스템 글꼴로 그립니다 — 이 렌더 결과는 믿으면 안 됩니다")
                return CTFontCreateWithName("Helvetica" as CFString, size, nil)
            }
            let base = CTFontDescriptorCreateWithNameAndSize(name as CFString, size)
            let varied = CTFontDescriptorCreateCopyWithAttributes(base, [
                kCTFontVariationAttribute: [weightAxisTag: weight],
            ] as CFDictionary)
            return italic
                ? CTFontCreateWithFontDescriptor(varied, size, &slant)
                : CTFontCreateWithFontDescriptor(varied, size, nil)
        }

        let faces = self.faces(of: family)
        guard !faces.isEmpty else {
            // 스타일 검증(`validate`)이 먼저 막는다. 여기까지 왔으면 렌더 도중에 글꼴이 지워진 것이다.
            log.fault("글꼴 \(family, privacy: .public) 이 없어 Pretendard 로 그립니다 — 이 렌더 결과는 믿으면 안 됩니다")
            return pretendard(size: size, weight: weight, italic: italic, slantDeg: slantDeg)
        }
        // 기울임이 맞는 자형을 먼저, 그중 굵기가 가장 가까운 것.
        let target = coreTextWeight(weight)
        let sameSlant = faces.filter { $0.italic == italic }
        let pool = sameSlant.isEmpty ? faces : sameSlant
        let face = pool.min { abs($0.weight - target) < abs($1.weight - target) }!

        var descriptor = face.descriptor
        let probe = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if hasWeightAxis(probe) {
            descriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor, [
                kCTFontVariationAttribute: [weightAxisTag: weight],
            ] as CFDictionary)
        }
        let needsSlant = italic && !face.italic
        return needsSlant
            ? CTFontCreateWithFontDescriptor(descriptor, size, &slant)
            : CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// 이 Mac 에서 그 이름의 글꼴 패밀리를 쓸 수 있는가.
    public static func isInstalled(family: String) -> Bool {
        !faces(of: family).isEmpty
    }

    /// 한글을 그릴 수 있는 설치 글꼴 패밀리. 설정 화면의 글꼴 목록이다.
    ///
    /// 자막 본문이 한국어라 한글 자형이 없는 글꼴은 목록에서 뺀다
    /// (고르면 시스템이 다른 글꼴로 대신 그려서 "고른 글꼴" 이 아니게 된다).
    public static func hangulFamilies() -> [String] {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return names.filter { family in
            guard let face = faces(of: family).first else { return false }
            let font = CTFontCreateWithFontDescriptor(face.descriptor, 12, nil)
            var chars: [UniChar] = Array(metricProbeHangul.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            return CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
        }.sorted()
    }

    private static let metricProbeHangul = "가힣"

    private struct Face { let descriptor: CTFontDescriptor; let weight: Double; let italic: Bool }

    /// 패밀리의 자형들. 번들 Pretendard 는 프로세스에 등록돼 있어 이름으로도 잡힌다.
    private static func faces(of family: String) -> [Face] {
        _ = registeredName
        let query = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family,
        ] as CFDictionary)
        let mandatory = Set([kCTFontFamilyNameAttribute as String]) as CFSet
        let found = CTFontDescriptorCreateMatchingFontDescriptors(query, mandatory) as? [CTFontDescriptor] ?? []
        return found.map { d in
            let traits = CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
            let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
            let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            return Face(
                descriptor: d, weight: weight,
                italic: symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0
            )
        }
    }

    private static func hasWeightAxis(_ font: CTFont) -> Bool {
        guard let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] else { return false }
        return axes.contains { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value == weightAxisTag }
    }

    /// CSS 굵기(100~900) → CoreText 굵기 특성(-1~1). `NSFont.Weight` 표와 같은 점을 선형으로 잇는다.
    static func coreTextWeight(_ css: CGFloat) -> Double {
        let table: [(Double, Double)] = [
            (100, -0.8), (200, -0.6), (300, -0.4), (400, 0), (500, 0.23),
            (600, 0.3), (700, 0.4), (800, 0.56), (900, 0.62),
        ]
        let x = min(max(Double(css), 100), 900)
        for (a, b) in zip(table, table.dropFirst()) where x <= b.0 {
            return a.1 + (b.1 - a.1) * (x - a.0) / (b.0 - a.0)
        }
        return table.last!.1
    }

    /// 사용 가능한 가변 축. 값이 실제로 먹는지 첫 렌더에서 확인하는 용도.
    public static func variationAxes() -> [String] {
        guard let name = registeredName else { return [] }
        let font = CTFontCreateWithName(name as CFString, 100, nil)
        guard let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] else { return [] }
        return axes.map { axis in
            let n = axis[kCTFontVariationAxisNameKey] as? String ?? "?"
            let lo = axis[kCTFontVariationAxisMinimumValueKey] as? Double ?? 0
            let hi = axis[kCTFontVariationAxisMaximumValueKey] as? Double ?? 0
            return "\(n) \(lo)~\(hi)"
        }
    }

    public static var postScriptName: String? { registeredName }
}

/// `Bundle(for:)` 로 MadiKit 프레임워크 번들을 잡기 위한 앵커.
private final class FontBundleToken {}
