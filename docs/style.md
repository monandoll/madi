# 스타일 학습 (5단계)

`StyleProfile` = `~/.madi/style/`
- `style.md` — 자연어 규칙. 사용자가 쓴 줄 + 맨 아래 학습 블록(`<!-- learned:start/end -->`, 자동 갱신). 에이전트 시스템 프롬프트에 통째로 들어간다.
- `params.json` — `subtitleStyle`, `silenceMinSec`(무음 잘라내기 기준), `learned`(합친 값).
- `examples/` — 아직 비어 있음.

## 기존 영상으로 배우기

설정 → 내 편집 스타일 → 기존 영상으로 배우기. 두 갈래가 같은 `references` 테이블·`analyze` 잡으로 모인다.

**완성본 폴더** — 폴더를 고르면(`settings.referenceFolders`):

1. `style/scan.ts` 가 폴더(하위 2단계)를 훑어 영상 파일을 `references` 테이블에 넣는다. 감시(chokidar)는 안 한다 — 설정이 바뀌거나 "다시 배우기"를 누를 때 다시 훑는다.
2. 파일마다 `analyze` 잡: ffprobe(길이·비율·소리), silencedetect(완성본에 **남아 있는** 무음 — 가장 긴 것이 "이 정도는 참는다"), 장면 전환 수(분당 컷)와 시각(`sceneTimes`, 앞 200개).
3. 제목이 갤러리의 원본과 같아 보이고(`looksLikeSameVideo`: 완성/final/v2/숏폼N 등을 뗀 뒤 비교) 그 원본에 자막이 있으면, 완성본도 whisper 로 자막을 만들어 문장 LCS 로 맞춘다(`pairDiff`): 남긴 비율, 앞·뒤 잘라낸 길이, 중간 컷 수. whisper 가 없으면 조용히 건너뛴다.
4. `aggregate` 가 합친다: 비율 다수결(70%), 길이 중앙값, 무음 기준 = 남아 있는 최대 무음의 90분위 + 0.1초(0.4~3초), 분당 컷 중앙값, 짝이 있으면 남긴 비율·인트로 길이.
5. `StyleProfile.setLearned` 가 학습 블록과 `params.learned`/`silenceMinSec` 를 바꾼다. WS `style.updated`.

**링크** — 유튜브·틱톡·인스타 릴스 등 공개 영상 주소를 붙여 넣으면(`POST /api/style/links`):

1. `references` 에 `source=link`, `url` 로 한 줄 (같은 링크는 한 번만; 실패했던 것은 다시). 파일은 `~/.madi/references/<id>.mp4` 로 받는다 — 갤러리(감시 폴더)와 무관.
2. `download` 잡이 사이드카 `yt-dlp`(`style/link.ts` 의 `ytdlpArgs`: 재생목록 제외, 720p 이하 mp4 하나, `--print` 로 파일 경로·제목)를 돌린다. 끝나면 제목을 채우고 `analyze` 로 이어진다.
3. 실패는 잡 실패가 아니라 완성본의 `error` 에 코드(`link_private` 로그인 필요 · `link_unsupported` · `link_unavailable` · `link_network` · `link_failed`)로 남고, 화면이 AI 말투로 풀어 보여 준다. "다시 배우기"가 실패한 링크를 다시 받는다.
4. yt-dlp 가 없는 PC(개발 모드)는 `StyleResponse.linkImport=false` → 입력은 보이되 501 `no_downloader`. 테스트는 `MADI_YTDLP=fixtures/fake-ytdlp.mjs`.
5. `DELETE /api/style/references/:id` 로 빼면 파일도 지우고 다시 합친다. 폴더를 훑을 때 링크 완성본은 missing 이 되지 않는다.

배운 값이 쓰이는 곳:
- 무음 잘라내기(버튼·`propose_cuts`·`find_silences`)의 기본 `minSec`
- 에이전트 프롬프트의 "(배움) …" 줄 → 숏폼 길이·비율·컷 빈도 판단

## 완성본의 뜻 읽기 · 기억 (기획안 §7 · §8)

숫자(길이 · 비율 · 무음)만으로는 "어디를 왜 잘랐는지"를 모른다. AI 가 연결돼 있으면 완성본마다 자막을 읽고 메모를 남기고,
여러 편에서 반복되는 것만 제작자 기억으로 굳힌다. 처음 한 번 넉넉히 읽고 저장하며, 편집할 때는 저장한 것만 꺼낸다 — 영상을 매번 다시 읽지 않는다.

```
완성본 → analyze (숫자 + 자막은 항상 뜬다)
       → insight 잡 (AI 한 턴, 도구 없음) → references.insight   ← 영상별 기억
       → 2초 뒤 rememory (AI 한 턴)      → memory (source=reference) ← 제작자 기억
새 영상 편집 → recall(video) → 태그가 겹치는 기억 + 비슷한 완성본 요약 2개 → 시스템 프롬프트 "# 기억"
```

- **영상별 기억** `ReferenceInsight` (`packages/shared/src/style.ts`): 취지 · 대상 · 도입 방식 · 말투 · 구성(구간 + 종류) · 핵심 문장 ·
  **지우면 안 되는 구간**(시범 · 시범 중 침묵 · 주의사항) · 반복/NG 후보 · 숏폼 후보(+이유) · 용어 · 자막 특징 · **제목과 내용의 관계**(`titleNote`, 기획안 §8.1) · 태그.
  프롬프트에는 자막과 함께 장면 전환 시각이 들어간다 — 말이 이어지는데 화면이 바뀌면 앵글 전환, 말이 멈추고 바뀌면 동작 전환 (§7).
  프롬프트 · 파서는 `src/style/insight.ts` (순수 함수). 답이 코드펜스에 싸여 있거나 시각이 "1:23" 이어도 받고, 길이 밖 구간은 버리고, 취지가 없으면 null (지어내지 않는다).
- **제작자 기억** `MemoryItem`: `kind`(style · keep · avoid · term) · `scope`(all · topic+topics · video) · `source`(reference · feedback · user) · `status`(proposed · approved) · 근거 완성본 id.
  `src/style/memory.ts`. 완성본에서 온 것은 **제안(proposed)** 으로 들어오고 사용자가 "쓰기"를 눌러야 편집에 쓰인다 (`recall()` 은 approved 만 본다).
  다시 정리할 때 통째로 바뀌되 이미 확인한 글은 확인 상태를 이어받고, 사용자가 뺀 글(kv `memory.dismissed`)은 다시 제안하지 않는다.
  편집 중 남긴 것(사용자가 예라고 한 것)과 직접 쓴 것은 바로 approved.
- **검색** `retrieve()`: 새 영상의 제목 · 자막에 나온 태그로 topic 기억과 비슷한 완성본을 고른다. 벡터 없이 낱말 겹침 (기획안 §11 초기 범위).
- **범위 있는 규칙**: `update_style_rule(rule, scope, topics, kind)`. scope=all · kind=style 이면 전처럼 `style.md` 에, 그 밖은 기억에 (source=feedback).
- **세기**: 제작 지침 < 기억 < 사용자가 쓴 규칙(style.md). 시스템 프롬프트에 그 순서로 들어간다.
- **사용자 통제** (§12): 설정 → 기존 영상으로 배우기의 완성본 줄마다 "메모" 로 취지 · 구성 · 숏폼 후보를 보고, "학습에서 빼기" 로 그 완성본을 숫자 · 기억 어디에도 안 쓰게 한다 (`references.excluded`, 파일은 그대로).
  "AI 가 기억한 것" 은 완성본에서 찾은 제안(쓰기 · 모두 쓰기 · 빼기)과 확인된 목록(고치기 · 빼기)으로 나뉘고, 직접 한 줄 쓰고, 전부 지울 수 있다.
  AI 연결 화면에 자막 · 편집 요청이 그 도구를 통해 AI 회사 서버로 간다는 안내가 있다 (영상 파일은 안 나간다).
- AI 를 나중에 연결했으면 **다시 배우기** 가 메모 없는 완성본을 읽는다.
- 분석 모드는 `AgentProvider.analyze()`: claude 는 `-p --mcp-config '{"mcpServers":{}}' --strict-mcp-config --max-turns 1`, codex 는 `exec` 에 MCP 설정 없이.

미룬 것: 대표 프레임 보기(§10 — 부위가 보이는 크롭 판단에 필요), 롱폼 편집안 표 화면(§4), 벡터 검색(§11).

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
| `POST /api/style/relearn` | 폴더 다시 훑기 + 실패한 것(링크 포함) 재분석 |
| `POST /api/style/links {url}` | 링크로 배우기 (400 `bad_link`, 501 `no_downloader`) |
| `DELETE /api/style/references/:id` | 완성본 빼기 (링크면 받은 파일도) |
| `PATCH /api/style/references/:id {excluded}` | 완성본을 학습에서 빼기 · 다시 넣기 |
| `POST /api/style/memory {text, kind?, scope?, topics?}` | 기억 직접 쓰기 (바로 approved) |
| `PATCH /api/style/memory/:id {text? \| status:'approved'}` | 글 고치기 · 제안 확인 |
| `POST /api/style/memory/approve {ids?}` | 제안 확인 (ids 없으면 전부) |
| `DELETE /api/style/memory/:id` | 한 줄 빼기 (완성본에서 온 것은 다시 제안하지 않는다) |
| `DELETE /api/style/memory[?only=proposed]` | 전부 지우기 · 제안만 지우기 |

## 테스트

- 단위 `test/insight.test.ts`: 자막 줄이기, JSON 꺼내기, 메모 파싱(시각 clamp · 중복), 기억 파싱(모르는 근거 버림), 검색 · 기억 블록.
- 단위 `test/memory.test.ts`: 제안 · 확인 · 확인 상태 이어받기 · 뺀 글 다시 제안 안 함 · 고치기 · 전부 지우기.
- 엔진 e2e `test/e2e.style.test.ts` 마지막 describe: AI 연결 → 다시 배우기 → 완성본마다 메모 → 제안, 확인해야 붙음, 관련 기억만 붙음, 고치기, 학습에서 빼기, 직접 쓰기 · 빼기, 완성본 다 빼면 비움, 전부 지우기.

- 단위 `test/learn.test.ts`: 비율, aggregate, 문장 생성, 제목 정규화, pairDiff(LCS), StyleProfile 블록, 스캔. `test/link.test.ts`: 주소 고르기, yt-dlp 인자·출력, 오류 분류.
- 엔진 e2e `test/e2e.style.test.ts`: 폴더 지정 → 진짜 ffmpeg 분석 → 배운 줄·무음 기준, 폴더 제거 → 원복, 다시 배우기, 링크(가짜 yt-dlp) → 받아서 배움·실패 코드·빼기.
- 브라우저 e2e `e2e/4-style.spec.ts`: 규칙 추가/빼기, 완성본 폴더 고르기 → 배운 줄, 링크 붙여넣기 → 배움.
