# 타깃 머신

앱은 **크리에이터 Mac** 에서 돈다. 영상도 AI 구독도 그 Mac 을 떠나지 않는다
(`AGENTS.md §2`, `§17`).

## 크리에이터 Mac (앱이 도는 곳)

| 항목 | 값 | 왜 중요한가 |
|---|---|---|
| 모델 | ? | |
| 칩 | ? | **Apple Silicon 필수.** Vision(Neural Engine) · WhisperKit(CoreML) · VideoToolbox 가 전부 여기 붙는다. Intel 이면 "편집 10분" 목표가 깨진다 |
| 메모리 | ? | Remotion 렌더 + 전사 동시 실행. 큐 동시성은 렌더 1 · 분석 1 |
| macOS | ? | Vision 관절 API · Chrome Headless · 로컬 네트워크 권한(15+) |
| 저장 여유 | ? | 촬영 원본 + 프록시 + 중간 산출물이 편당 수백 MB |
| AI 구독 | 보유 | Claude · Codex 둘 다 지원. 어느 쪽이든 동작한다 |

확인 명령 (크리에이터에게 실행을 부탁하지 말 것 — 전달 시 직접 확인한다):

```bash
system_profiler SPHardwareDataType | grep -E "Model Name|Chip|Memory"; sw_vers; df -h /
```

## 아이폰

**앱을 설치하지 않는다.** Safari 로 붙는다.

| 항목 | 값 |
|---|---|
| 용도 | 촬영 · 업로드 · 진행 확인 · 결과 저장 |
| 접속 | 같은 와이파이 → 앱이 띄운 QR 스캔 |
| 주소 | `http://<mac>.local:41520/?t=<페어링토큰>` |
| 필요한 것 | Safari, 같은 와이파이 |

집 밖에서는 안 된다. 터널은 요구가 실제로 생기면 붙인다 (`AGENTS.md §2`).

## 전달 전 체크리스트 (§12-7)

- [ ] `.dmg` 드래그 → 아이콘 클릭 → 준비 완료까지 터미널 0회
- [ ] 앱 창이 주소창 없이 뜬다 (Safari 탭이 아니다)
- [ ] 첫 실행 준비 화면이 ffmpeg · Chrome 다운로드 진행률을 보여준다
- [ ] quarantine 자동 해제 (0단계에서 이미 겪은 문제)
- [ ] claude / codex 감지 → 없으면 설치 → 브라우저 OAuth 로그인
- [ ] 로컬 네트워크 권한 허용 후 QR 접속 성공
- [ ] Mac 이 잠들면 아이폰에서 안 보인다 — 앱이 이유를 알려준다
- [ ] 저장 공간 경고 (여유 20GB 이하)
