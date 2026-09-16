# 폰에서 올리기

폰(또는 다른 브라우저)에서 고른 영상을 선생님 PC 의 **첫 번째 영상 폴더**로 넣는다. 그다음은 폴더에 파일을 복사한 것과 똑같다 — 감시가 등록하고 프록시·썸네일을 만든다.

## 흐름

1. 모바일 갤러리 헤더 **올리기** (PC 는 "폰에서 업로드" 안내 카드 안의 "이 브라우저에서 파일 고르기") → `<input type=file accept=video/*>`.
2. 브라우저 `tus-js-client` 가 `/api/uploads` 에 tus 프로토콜로 8MB 씩 올린다 (`apps/web/src/lib/uploads.ts`). 끊기면 0·1·3·5·10초 뒤 다시 붙는다. 진행 줄은 갤러리 위 카드(`upload-list`).
3. 엔진 `@tus/server` + `@tus/file-store` (`apps/engine/src/server/upload.ts`)가 조각을 `~/.madi/uploads/<id>` 에 모은다. Hono 를 거치지 않고 node req/res 를 그대로 넘긴다 (`RESPONSE_ALREADY_SENT`).
4. 다 올라오면 `onUploadFinish` 가 첫 영상 폴더로 옮긴다 (같은 이름이면 `이름 (2).mp4`). 응답 헤더 `X-Madi-File` 에 최종 이름. `upload.finished` 이벤트.
5. 감시(chokidar, awaitWriteFinish)가 등록 → WS `video.added` → 갤러리에 카드. 진행 줄은 같은 이름의 영상이 보이면 사라진다.

## 거절 (만들기부터 400, body 가 코드)

| 코드 | 언제 | 화면 |
|---|---|---|
| `no_folder` | 영상 폴더가 없음 | "영상 폴더를 먼저 정해 주세요." |
| `not_video` | 확장자가 영상이 아님 | "영상 파일만 올릴 수 있어요." (브라우저에서도 미리 거른다) |

네트워크 오류는 "올리다가 끊겼어요. 다시 눌러 주세요." + 다시 버튼 (파일 핸들이 남아 있을 때).

## 밖에서

엔진은 `127.0.0.1` 에만 붙는다. 같은 와이파이라도 폰이 직접 못 들어오고, **설정 → 밖에서 접속하기(Cloudflare Tunnel)** 로 연결해야 한다. PC 안내 카드가 그 상태를 보여 준다. 터널 뒤에서도 주소가 맞도록 tus 는 상대 Location 을 준다.

## 정리

- 하루 지난 미완성 조각은 기동 때 지운다 (`cleanUpExpiredUploads`).
- 한 번에 10개까지.

## 테스트

- 엔진 e2e `test/e2e.upload.test.ts`: tus 로 두 조각 → HEAD offset → 폴더에 파일 → 갤러리 ready, 같은 이름 (2), no_folder / not_video.
- 브라우저 e2e `e2e/1-gallery.spec.ts`: 375 올리기 → 진행 줄 → 카드, 영상 아닌 파일 거절, PC 안내 카드 + 이 브라우저에서 올리기.
