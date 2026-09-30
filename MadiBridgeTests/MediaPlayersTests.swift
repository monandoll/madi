import Testing
import Foundation
import AVFoundation
@testable import MadiBridgeTests

/// 결과물 재생 — 보이는 것만 틀고, 소리는 하나만 (2026-09-30 "하나만" 에서 숨긴 이전 판이 소리를 냈다).
@MainActor
struct MediaPlayersTests {

    let previous = URL(fileURLWithPath: "/tmp/madi-prev.mp4")
    let current = URL(fileURLWithPath: "/tmp/madi-cur.mp4")
    let other = URL(fileURLWithPath: "/tmp/madi-other.mp4")

    @Test("'하나만' — 전에 만든 이전 판 · 다른 결과물 재생기는 틀지 않는다")
    func playsOnlyVisible() {
        let players = MediaPlayers()
        _ = players.player(for: other)      // 전에 골랐던 결과물
        _ = players.player(for: previous)   // "나란히" 때 만든 이전 판
        _ = players.player(for: current)
        players.playFromStart([current], soundFrom: current)
        #expect(players.player(for: current).rate > 0)
        #expect(players.player(for: previous).rate == 0)
        #expect(players.player(for: other).rate == 0)
    }

    @Test("'둘 다 처음부터 재생' — 둘 다 돌고, 소리는 지금 판만")
    func bothPlayOneSound() {
        let players = MediaPlayers()
        players.playFromStart([previous, current], soundFrom: current)
        #expect(players.player(for: previous).rate > 0 && players.player(for: current).rate > 0)
        #expect(players.player(for: previous).isMuted)
        #expect(!players.player(for: current).isMuted)
    }

    @Test("돌던 재생기도 안 보이면 멈춘다")
    func pausesHiddenPlaying() {
        let players = MediaPlayers()
        players.playFromStart([previous, current], soundFrom: current)
        players.playFromStart([current], soundFrom: current)
        #expect(players.player(for: previous).rate == 0)
    }
}
