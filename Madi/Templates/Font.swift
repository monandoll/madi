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

    /// 지정한 웨이트·크기의 Pretendard.
    ///
    /// - Parameters:
    ///   - size: 포인트(=픽셀, `contentsScale` 1 로 그리므로).
    ///   - weight: `wght` 축 값. 400 Regular · 700 Bold · 800 ExtraBold · 900 Black.
    ///   - italic: Pretendard Variable 에는 기울임 축이 없다. true 면 **기울임 변환**으로
    ///             흉내 낸다. 진짜 이탤릭 자형이 아니므로 원본이 이탤릭이면 폰트부터 확인한다.
    public static func pretendard(size: CGFloat, weight: CGFloat, italic: Bool = false) -> CTFont {
        guard let name = registeredName else {
            // 폰트가 없으면 조용히 다른 글꼴로 그리지 않는다. 눈에 띄게 만든다.
            log.fault("Pretendard 를 못 써서 시스템 글꼴로 그립니다 — 이 렌더 결과는 믿으면 안 됩니다")
            return CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        let base = CTFontDescriptorCreateWithNameAndSize(name as CFString, size)
        let varied = CTFontDescriptorCreateCopyWithAttributes(base, [
            kCTFontVariationAttribute: [weightAxisTag: weight],
        ] as CFDictionary)
        if italic {
            // 12도. 기울임 각도는 관습값이고 측정 대상이 아니다.
            var slant = CGAffineTransform(a: 1, b: 0, c: CGFloat(tan(12 * Double.pi / 180)), d: 1, tx: 0, ty: 0)
            return CTFontCreateWithFontDescriptor(varied, size, &slant)
        }
        return CTFontCreateWithFontDescriptor(varied, size, nil)
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
