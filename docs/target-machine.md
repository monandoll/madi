# 타깃 머신

크리에이터 Mac 한 대에서 전부 돌아간다 (`AGENTS.md §2`, `§17`).

## 확인 필요 — 1단계 전에 채운다

| 항목 | 값 | 왜 중요한가 |
|---|---|---|
| 모델 | ? | |
| 칩 | ? | **Apple Silicon 이어야 한다.** whisper.cpp CoreML 가속과 ffmpeg VideoToolbox 가 여기 붙는다. Intel 이면 전사만 몇 분씩 걸려 "편집 10분" 목표가 깨진다 |
| 메모리 | ? | Remotion 렌더 + whisper 동시 실행. 16GB 이하면 큐 동시성을 1로 묶어야 한다 |
| macOS 버전 | ? | Chrome Headless Shell · CoreML 요구사항 |
| 저장 공간 여유 | ? | 촬영 원본 + 프록시 + 중간 산출물이 편당 수백 MB 쌓인다. 정리 주기를 정해야 한다 |

확인 전에는 사양을 단정하지 않는다.

## 확인된 것

| 항목 | 값 |
|---|---|
| AI 구독 | 보유 (제품 미확인 — Claude 계열이면 `claude`, ChatGPT 계열이면 `codex`) |

`AgentProvider` 가 둘 다 지원하므로 어느 쪽이든 동작한다. 다만 설치 안내 문구가 달라지므로
어느 구독인지는 `install.sh` 를 쓰기 전에 확인한다.

## 확인 방법

크리에이터에게 물어볼 필요 없이 이 한 줄이면 나온다.

```bash
system_profiler SPHardwareDataType | grep -E "Model Name|Chip|Memory"; sw_vers; df -h /
```
