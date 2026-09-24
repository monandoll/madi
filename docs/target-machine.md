# 타깃 머신

엔진은 **운영자 Mac 한 대**에서 상시로 돈다. 크리에이터는 브라우저로만 접근한다
(`AGENTS.md §2`, `§17`).

## 운영자 Mac (엔진이 도는 곳)

| 항목 | 값 | 비고 |
|---|---|---|
| 모델 | Mac Studio | |
| 칩 | ? | Apple Silicon. whisper.cpp CoreML · ffmpeg VideoToolbox 가 여기 붙는다 |
| 메모리 | ? | Remotion 렌더 + whisper 동시 실행. 큐 동시성은 렌더 1 · 분석 1 로 묶는다 |
| macOS | ? | Chrome Headless Shell · CoreML 요구사항 |
| 저장 여유 | ? | 촬영 원본 + 프록시 + 중간 산출물이 편당 수백 MB. 보관 기간 정책 필요 |
| 업로드 회선 | ? | 결과물 다운로드가 이 회선을 탄다 |
| AI 구독 | 보유 | Claude · Codex 둘 다 지원. 어느 쪽이든 동작한다 |

확인 명령:

```bash
system_profiler SPHardwareDataType | grep -E "Model Name|Chip|Memory"; sw_vers; df -h /
```

## 크리에이터 단말

**사양 요구 없음.** 브라우저와 이메일만 있으면 된다.

| 항목 | 값 |
|---|---|
| 주 단말 | 아이폰 (촬영 · 업로드 · 확인) |
| 보조 | Mac (보유) |
| 필요한 것 | Safari, 이메일 (Cloudflare Access OTP) |

아이폰이 주 경로이므로 **모바일 화면을 나중으로 미루지 않는다.**

## 상시 가동 체크리스트 (§12-7)

- [ ] 절전 해제 (`pmset`) — 잠들면 크리에이터 화면이 죽는다
- [ ] launchd 등록, 재부팅 후 5분 안에 자동 복구
- [ ] cloudflared 상시 연결 + 끊김 시 자동 재연결
- [ ] Cloudflare Access 이메일 허용 목록에 크리에이터 이메일
- [ ] 촬영본 보관 기간 자동 삭제 잡
- [ ] 저장 공간 경고 (여유 20GB 이하)
