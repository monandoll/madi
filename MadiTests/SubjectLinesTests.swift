import Testing
@testable import MadiKit

/// 다이제스트 사람 위치 줄 — 비슷한 0.5초 표본은 한 줄로 묶는다 (31분 영상에서 이 칸이 다이제스트의 93% 였다).
struct SubjectLinesTests {

    private func s(_ t: Double, _ box: NormRect?) -> SubjectSample {
        SubjectSample(t: t, box: box, massCenterX: nil, massCenterY: nil, coverage: box == nil ? 0 : 0.2)
    }

    @Test("가만히 있는 구간은 한 줄 — `시작-끝` 과 평균 상자")
    func mergesStillRun() {
        let box = NormRect(x: 0.40, y: 0.20, w: 0.20, h: 0.60)
        let lines = DigestBuilder.subjectLines((0..<10).map { s(Double($0) * 0.5, box) })
        #expect(lines == ["000.0-004.5  0.40 0.20 0.20 0.60"])
    }

    @Test("자세가 바뀌면(높이가 크게) 구간이 끊긴다. 3% 안의 흔들림은 같은 구간")
    func splitsOnPostureChange() {
        let stand = NormRect(x: 0.40, y: 0.20, w: 0.20, h: 0.60)
        let wobble = NormRect(x: 0.42, y: 0.21, w: 0.19, h: 0.62)      // 3% 안
        let floor = NormRect(x: 0.30, y: 0.05, w: 0.40, h: 0.25)       // 바닥 자세
        let lines = DigestBuilder.subjectLines([s(0, stand), s(0.5, wobble), s(1.0, stand), s(1.5, floor), s(2.0, floor)])
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("000.0-001.0"))
        #expect(lines[1] == "001.5-002.0  0.30 0.05 0.40 0.25")
    }

    @Test("못 찾은 구간도 묶고, 하나뿐인 표본은 예전 꼴 그대로")
    func missingAndSingles() {
        let box = NormRect(x: 0.40, y: 0.20, w: 0.20, h: 0.60)
        let lines = DigestBuilder.subjectLines([s(0, box), s(0.5, nil), s(1.0, nil), s(1.5, nil), s(2.0, box)])
        #expect(lines == ["000.0  0.40 0.20 0.20 0.60", "000.5-001.5  -", "002.0  0.40 0.20 0.20 0.60"])
    }
}
