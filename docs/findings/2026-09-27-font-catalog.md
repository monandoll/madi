# 자막 글꼴 목록 — 결정 기록 (2026-09-27)

크리에이터 자막 스타일은 바뀐다 (`2026-09-27-secondary-10.md`). 자막 모양(`look`)은 사용자가 고르고,
글꼴은 이 Mac 에 설치된 것에서 고른다 (`AGENTS.md §9`). 여기에 **무료 글꼴 목록**을 더한다.

## 결정

- **A안 — 필요할 때 받는다.** 앱에는 Pretendard 만 넣는다. 나머지는 사용자가 고를 때 공식 배포처에서 받는다
- 후보 **8개** (나눔스퀘어라운드는 뺐다 — 공식 배포가 zip 뿐이고 원문 라이선스를 직접 확인하지 못했다)
- **만드는 시점: 3단계.** WhisperKit 모델 받기를 정할 때 같이 만든다.
  `AGENTS.md §3` 의 "네트워크 요청은 AI CLI 와 whisper.cpp 다운로드 외에 없다" 도 그때 한 번에 고친다

## 조건

- 라이선스가 **OFL 1.1** — 앱에 넣거나 대신 받아 나눠 줘도 된다. "상업용 무료" 만으로는 안 된다
- 서버가 없다 → **공식 배포처에서 개별 파일로** 받는다 (zip 풀기 없음)

## 목록

| 글꼴 | 느낌 | 굵기 | 크기 | 공식 배포처 (파일) |
|---|---|---|---|---|
| Pretendard | 고딕 (기본) | 가변 | 6.7MB | **번들** (`Madi/Resources/Fonts/`) |
| SUIT (패밀리 이름 `SUIT Variable`) | 고딕 | 가변 | ~1MB | `github.com/sun-typeface/SUIT` — `fonts/variable/ttf/SUIT-Variable.ttf` |
| Noto Sans KR | 고딕 | 가변 | 9.9MB | `github.com/google/fonts` — `ofl/notosanskr/NotoSansKR[wght].ttf` |
| Gothic A1 | 고딕 | 9단계 | 파일당 ~2MB | `google/fonts` — `ofl/gothica1/GothicA1-*.ttf` |
| Jua | 둥근 굵은 제목체 | 1 | 2.0MB | `google/fonts` — `ofl/jua/Jua-Regular.ttf` |
| Gowun Dodum | 부드러운 둥근 고딕 | 1 | 6.8MB | `google/fonts` — `ofl/gowundodum/GowunDodum-Regular.ttf` |
| Do Hyeon | 굵은 제목체 | 1 | 0.8MB | `google/fonts` — `ofl/dohyeon/DoHyeon-Regular.ttf` |
| Black Han Sans | 아주 굵은 제목체 | 1 | 0.9MB | `google/fonts` — `ofl/blackhansans/BlackHanSans-Regular.ttf` |

확인한 것: `google/fonts` 의 7종 모두 `ofl/` 폴더에 `OFL.txt` 가 있다. SUIT 저장소 라이선스는 OFL-1.1.
(2026-09-27 기준 `google/fonts` main 은 `23e54b51ddff`.)

## 3단계에서 만들 때

- 목록은 앱 안의 데이터 — 글꼴마다 주소 · **SHA-256** · 라이선스 · 크기
- 주소는 **커밋이나 태그에 고정**한다. 배포처가 파일을 바꿔도 결과물이 바뀌지 않아야 한다 —
  같은 이름의 글꼴 모양이 바뀌면 옛 편집안을 똑같이 다시 그릴 수 없다 (`§1-8`)
- 받은 파일은 해시로 확인하고, 틀리면 쓰지 않고 채팅으로 알린다 (`§1-6`)
- `~/Library/Application Support/madi/downloads/fonts/<패밀리>/` 에 `OFL.txt` 와 같이 둔다.
  시스템에 설치하지 않고 **앱 프로세스에만 등록**한다 (`CTFontManager` `.process`)
- 글꼴 목록 = 설치된 한글 글꼴 ∪ 이 목록. 목록 글꼴은 받기 전에도 보인다
- 편집안이 쓰던 목록 글꼴이 지워졌으면 다시 받아 복구할 수 있다 (사용자가 직접 설치한 글꼴은 못 한다)
- 굵기가 하나뿐인 글꼴을 고르면 설정의 굵기 선택을 숨긴다 (`docs/design/copy-keys.md` 에 키 추가)
- 글꼴을 고치거나 잘라 쓰지(subset) 않는다 — OFL 의 예약 글꼴 이름 조항에 걸리지 않게

## 만들었다 (2026-09-27)

`Resources/downloads.json` · `Madi/Downloads/`. 전사 모델과 같은 방식으로 한 번에 만들었다.

- 고정: `google/fonts` `23e54b51ddffbc7713c583748e3bd86f62b1fa4a` · SUIT `55118d981336d8fce005eb62888c12c0568ef7b0` (v2.0.5)
- SUIT 의 실제 패밀리 이름은 **`SUIT Variable`** 이다 (파일에서 읽음). 스타일은 이 이름으로 찾는다
- SUIT 라이선스 파일 이름은 `LICENSE` — 받아서 `OFL.txt` 로 둔다. 7종 모두 본문이 SIL OFL 인지 확인했다
- 실제로 받아 봤다: Do Hyeon 0.9MB · 0.7초 · 해시 일치 · 프로세스 등록 후 `isInstalled` 참
