import Foundation

/// 오버레이 `payload` 스키마. `Spec.json` 의 `overlay` 절과 **같은 내용**이다 — AI 는 Spec.json 을 읽고,
/// 저장할 때 이 코드가 검사한다. 둘이 어긋나면 AI 가 쓴 편집안이 저장되지 않는다.
///
/// 근거: 공개본 10편 · 오버레이 55개 (`docs/findings/2026-09-27-overlay-payload.md`).
///
/// ★ payload 에는 **뜻**만 있다. 색 · 굵기 · 점선 여부 · 크기 수치 · 애니메이션은 스타일이 정한다.
///   크리에이터 영상에서 색은 뜻을 따랐다 — 빨강 = 문제 · 틀림, 초록/노랑 = 맞음, 흰색 = 중립.
///   그래서 AI 는 색이 아니라 `tone` 을 고른다.
///
/// ★ 모르는 키는 거절한다. 느슨하게 받으면 AI 가 매번 다른 키를 지어내고 렌더가 조용히 무시한다.
enum OverlayPayload {

    /// 오버레이가 전하는 뜻. 색은 스타일이 이 이름에 붙인다.
    /// "맞음"(원본 초록 · 노랑)은 ○ 모양으로만 나왔다 — 그래서 tone 에는 없다.
    enum Tone: String, CaseIterable {
        case problem   // 잘못된 자세 · 아픈 곳 · 틀린 쪽 — 원본은 빨강
        case neutral   // 어떻게 움직일지 · 어디를 볼지 — 원본은 흰색
    }

    private struct Field {
        let key: String
        let values: [String]?      // nil = 자유 문자열
        let required: Bool
    }

    private static func schema(_ kind: Overlay.Kind, _ payload: [String: JSONValue]) -> [Field] {
        switch kind {
        case .arrow:
            // 문제 동작(빨강, 꼬리 번짐)과 움직이는 방향 안내(흰색, 곡선 점선)가 원본의 두 갈래다.
            // `correct` 화살표는 원본에 없었다.
            var fields = [
                Field(key: "tone", values: Tone.allCases.map(\.rawValue), required: true),
                Field(key: "path", values: ["straight", "curved"], required: true),
            ]
            // 곡선은 어느 쪽으로 휘는지가 있어야 그릴 수 있다. 진행 방향 기준 왼쪽/오른쪽.
            let curved = payload["path"]?.stringValue == "curved"
            fields.append(Field(key: "bend", values: ["left", "right"], required: curved))
            return fields
        case .circle:
            // ring = 테두리 원(가만히), pulse = 빨간 점이 깜빡이며 퍼짐(아픈 근육),
            // tap = 흰 점이 퍼지며 사라짐(여기를 보라). pulse · tap 은 모양이 뜻을 정한다.
            let form = payload["form"]?.stringValue
            var fields = [Field(key: "form", values: ["ring", "pulse", "tap"], required: true)]
            if form == "ring" {
                fields.append(Field(key: "tone", values: Tone.allCases.map(\.rawValue), required: true))
                // 무엇을 덮는가. 크기 수치는 스타일이 정한다 — 원본 관절 0.16w · 부위 0.25~0.32w · 넓은 곳 0.45w.
                fields.append(Field(key: "covers", values: ["joint", "part", "area"], required: true))
            }
            return fields
        case .image:
            return [
                // 그림 · 사진 자산. 자산 보관소는 아직 없다 (3단계).
                Field(key: "assetId", values: nil, required: true),
                // 어디에 놓는가. 원본 네 가지 — 자막 아래 작은 카드 · 화면 대부분 · 가로 띠 · 옆 세로 카드.
                Field(key: "placement", values: ["under", "large", "band", "side"], required: true),
            ]
        case .mark:
            // ○ = 맞음, ✗ = 틀림. 색은 모양이 정한다 (tone 을 따로 받지 않는다).
            return [Field(key: "symbol", values: ["o", "x"], required: true)]
        }
    }

    /// 문제 목록. 비었으면 통과. 메시지는 AI 가 읽고 고칠 수 있게 쓴다 (`AGENTS.md §10`).
    static func problems(_ overlay: Overlay, at path: String) -> [String] {
        var out: [String] = []
        let fields = schema(overlay.kind, overlay.payload)
        let allowed = Set(fields.map(\.key))

        for key in overlay.payload.keys.sorted() where !allowed.contains(key) {
            let list = fields.map(\.key).joined(separator: ", ")
            out.append("\(path).payload.\(key) 는 \(overlay.kind.rawValue) 에 없는 키다 (쓸 수 있는 키: \(list))")
        }
        for f in fields {
            guard let value = overlay.payload[f.key] else {
                if f.required { out.append("\(path).payload.\(f.key) 가 필요하다") }
                continue
            }
            guard let s = value.stringValue, !s.isEmpty else {
                out.append("\(path).payload.\(f.key) 는 문자열이어야 한다")
                continue
            }
            if let values = f.values, !values.contains(s) {
                out.append("\(path).payload.\(f.key) \"\(s)\" 는 쓸 수 없다 (\(values.joined(separator: " · ")) 중 하나)")
            }
        }

        // 화살표만 끝점이 있다. 시작점은 anchor.
        switch (overlay.kind, overlay.to) {
        case (.arrow, nil):
            out.append("\(path).to 가 필요하다 — 화살표 머리가 가리키는 점 (0..1). 시작점은 anchor")
        case (.arrow, let to?):
            if to.x < 0 || to.x > 1 || to.y < 0 || to.y > 1 { out.append("\(path).to 가 0..1 밖이다") }
            if to == overlay.anchor { out.append("\(path).to 가 anchor 와 같다 — 길이가 0 인 화살표") }
        case (_, .some):
            out.append("\(path).to 는 arrow 에만 쓴다")
        default:
            break
        }
        return out
    }
}
