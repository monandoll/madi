# 스타일 학습 (5단계)

`StyleProfile` = `~/.madi/style/`
- `style.md` — 자연어 규칙. 사용자가 쓴 줄 + 맨 아래 학습 블록(`<!-- learned:start/end -->`, 자동 갱신). 에이전트 시스템 프롬프트에 통째로 들어간다.
- `params.json` — `subtitleStyle`, `silenceMinSec`(무음 잘라내기 기준), `learned`(합친 값).
- `examples/` — 아직 비어 있음.

## 완성본에서 배우기

설정 → 완성본에서 배우기 → 폴더를 고르면(`settings.referenceFolders`):

1. `style/scan.ts` 가 폴더(하위 2단계)를 훑어 영상 파일을 `references` 테이블에 넣는다. 감시(chokidar)는 안 한다 — 설정이 바뀌거나 "다시 배우기"를 누를 때 다시 훑는다.
2. 파일마다 `analyze` 잡: ffprobe(길이·비율·소리), silencedetect(완성본에 **남아 있는** 무음 — 가장 긴 것이 "이 정도는 참는다"), 장면 전환 수(분당 컷).
3. 제목이 갤러리의 원본과 같아 보이고(`looksLikeSameVideo`: 완성/final/v2/숏폼N 등을 뗀 뒤 비교) 그 원본에 자막이 있으면, 완성본도 whisper 로 자막을 만들어 문장 LCS 로 맞춘다(`pairDiff`): 남긴 비율, 앞·뒤 잘라낸 길이, 중간 컷 수. whisper 가 없으면 조용히 건너뛴다.
4. `aggregate` 가 합친다: 비율 다수결(70%), 길이 중앙값, 무음 기준 = 남아 있는 최대 무음의 90분위 + 0.1초(0.4~3초), 분당 컷 중앙값, 짝이 있으면 남긴 비율·인트로 길이.
5. `StyleProfile.setLearned` 가 학습 블록과 `params.learned`/`silenceMinSec` 를 바꾼다. WS `style.updated`.

배운 값이 쓰이는 곳:
- 무음 잘라내기(버튼·`propose_cuts`·`find_silences`)의 기본 `minSec`
- 에이전트 프롬프트의 "(배움) …" 줄 → 숏폼 길이·비율·컷 빈도 판단

## 피드백 루프

- 채팅에서 수정 요청 → 에이전트가 고친 뒤 "앞으로도 이렇게 할까요?" → 예 → `update_style_rule` 로 한 줄 추가.
- 설정에서 규칙을 직접 추가/삭제 (`POST/DELETE /api/style/rules`). 배운 줄은 지울 수 없고 다시 배우면 갱신된다.
- 완성본이 늘면 "다시 배우기" (`POST /api/style/relearn`).

## API

| | |
|---|---|
| `GET /api/style` | 규칙 목록(learned 표시), learned, 완성본 목록·상태, 자막 스타일, silenceMinSec |
| `POST /api/style/rules {rule}` | 규칙 추가 |
| `DELETE /api/style/rules/:index` | 사용자 규칙 삭제 (배운 줄이면 400) |
| `POST /api/style/relearn` | 폴더 다시 훑기 + 실패한 것 재분석 |

## 테스트

- 단위 `test/learn.test.ts`: 비율, aggregate, 문장 생성, 제목 정규화, pairDiff(LCS), StyleProfile 블록, 스캔.
- 엔진 e2e `test/e2e.style.test.ts`: 폴더 지정 → 진짜 ffmpeg 분석 → 배운 줄·무음 기준, 폴더 제거 → 원복, 다시 배우기.
- 브라우저 e2e `e2e/4-style.spec.ts`: 규칙 추가/빼기, 완성본 폴더 고르기 → 배운 줄.
