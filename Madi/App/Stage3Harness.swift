import Foundation
import MadiKit

/// ⚠ **3단계 판정 전용. 4단계에서 지운다** (AGENTS.md §12-3).
///
/// 앱을 `-stage3Slot <upperBody|fullBody|lowerBody>` 로 켰을 때만 동작한다.
/// 다이제스트가 끝나면 **기본 편집안**(영상 전체 한 장면 · 분절기 자막 · 자동 화면 잡기)을 만들어 렌더에 건다.
///
/// 왜 있나: 3단계는 AI 없이 "수동 편집안" 으로 판정한다. 아이폰 영상의 id 는 들어올 때 생기므로
/// 사람이 JSON 을 쓰면 그 시간이 3분에 섞인다. 기계 시간만 재려고 편집안을 자동으로 붙인다.
/// `§10` 대로 **AI 없는 편집 경로를 제품에 두지 않는다** — 옵션 없이는 아무것도 안 하고, 4단계에서 AI 로 대체된다.
enum Stage3Harness {
    static var slot: CaptionSlot? {
        UserDefaults.standard.string(forKey: "stage3Slot").flatMap(CaptionSlot.init(rawValue:))
    }

    /// 분석 처리기를 감싼다. 옵션이 없으면 그대로 돌려준다.
    static func wrap(_ analyze: @escaping JobQueue.Handler, db: AppDatabase, queue: @escaping @Sendable () -> JobQueue?) -> JobQueue.Handler {
        guard let slot else { return analyze }
        return { job in
            try await analyze(job)
            guard let digest = try await db.writer.read({ try DigestRecord.fetchOne($0, key: job.targetId) }),
                  let video = try await db.writer.read({ try VideoRecord.fetchOne($0, key: job.targetId) }),
                  let duration = video.durationSec else { return }
            let style = try StyleStore.load(try StyleStore.latest())
            let end = max(duration - 0.05, 0.1)
            let comp = Composition(
                id: "stage3_" + video.id, videoID: video.id, templateID: "short", style: try StyleStore.latest(),
                meta: Composition.Meta(title: "3단계 판정", targetDurationSec: end), captionSlot: slot,
                scenes: [Scene(
                    id: "s1", role: .hook, source: Scene.Source(videoID: video.id, start: 0, end: end),
                    captions: CaptionSplitter.split(digest.transcript.words.filter { $0.end <= end }, style: style.values.caption)
                )]
            )
            try db.saveComposition(comp)
            try db.log("stage3.composition", subject: comp.id)
            try await queue()?.enqueue(.render, targetId: comp.id)
        }
    }
}
