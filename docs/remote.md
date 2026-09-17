# 밖에서 접속

집 밖에서도 폰으로 마디를 열 수 있게 하는 길. 설정 → **밖에서 접속하기 → 켜기** 한 번이면 끝난다.
계정·토큰·도메인이 하나도 필요 없다 (1차 사용자가 그런 걸 만들 사람이 아니다).

## 두 갈래

| 모드 | 설정값 | 명령 | 주소 |
|---|---|---|---|
| 끔 | `remoteMode: 'off'` | — | 이 PC 브라우저만 |
| 빠른 터널 (기본) | `remoteMode: 'quick'` | `cloudflared tunnel --no-autoupdate --url http://127.0.0.1:41520` | `https://<랜덤>.trycloudflare.com`, 껐다 켜면 바뀐다 |
| 고정 주소 (고급) | `remoteMode: 'token'` + `tunnelToken` | `cloudflared tunnel --no-autoupdate run --token …` | 사용자가 정한 도메인 |

빠른 터널은 Cloudflare 가 계정 없이 내주는 임시 주소다. 엔진은 cloudflared 가 찍는 로그 한 줄에서 주소를 읽는다
(`parseQuickUrl`). 죽으면 백오프로 다시 띄우고, 새 주소를 다시 읽는다.

고정 주소가 필요한 사람만 설정의 "고정 주소 쓰기 (고급)"를 펴서 토큰을 넣는다. 만드는 법은
`docs/packaging.md` 의 같은 이름 절에 있다. 예전에 토큰만 넣어 두었던 설정은 기동할 때 `remoteMode: 'token'` 으로 옮겨 준다.

## 잠금 (6자리 숫자)

빠른 터널 주소에는 로그인이 없다. 주소를 아는 사람은 누구나 들어온다. 그래서 엔진이 직접 문을 지킨다.

- **이 PC 에서 직접 연 브라우저**는 늘 통과한다. 숫자를 물어보지 않는다.
- **밖에서 들어온 요청**은 6자리 숫자를 한 번 맞혀야 한다. 맞히면 그 기기에 표(쿠키 `madi_pair`)를 준다.
- QR 에 숫자를 실어 주므로(`?pin=…`) 폰은 찍기만 하면 된다. 주소에서 숫자는 바로 지운다.

"이 PC 에서 직접"은 IP 로 못 가른다 — cloudflared 도 `127.0.0.1` 로 붙는다. 대신 터널을 지나온 요청에는
cloudflared 가 붙이는 헤더(`cf-connecting-ip`, `cf-ray`, `x-forwarded-for` 등)가 있다. 클라이언트가 지울 수 없는 값이다.
`isDirectRequest()` 가 루프백 + 그 헤더 없음을 본다.

| 것 | 어디 |
|---|---|
| 숫자 | 메모리에만. 엔진을 켤 때마다, 밖에서 접속을 켤 때마다 새로 만든다 |
| 기기 표 | `~/.madi/pairs.json` (0600). 껐다 켜도 폰이 다시 숫자를 치지 않게 |
| 틀린 횟수 | 10번 틀리면 숫자를 새로 만든다 (찍어서 맞히기 방지) |
| 밖에서 접속 끄기 | 짝지은 기기를 전부 끊는다 |

비교는 `crypto.timingSafeEqual`. 숫자는 `GET /api/remote` 가 **이 PC 에서 직접 물었을 때만** 돌려준다.

## API

| 길 | 하는 일 |
|---|---|
| `GET /api/remote` | 모드·상태·주소·숫자(직접일 때만)·들어온 기기 수 |
| `POST /api/remote/pair` | `{ pin }` → 맞으면 `set-cookie: madi_pair=…` (1년, HttpOnly, SameSite=Lax). 틀리면 403 `bad_pin`, 꺼져 있으면 409 `remote_off` |
| `/api/*`, `/media/*`, `/ws` | 밖에서 왔고 표가 없으면 401 `needs_pair` |

화면(정적 파일)은 막지 않는다. 폰이 숫자 넣는 화면을 봐야 하기 때문이다. 웹은 설정 조회가 `needs_pair` 로 막히면
`screens/Pair.tsx` 를 띄운다.

## 화면

- 설정 → 밖에서 접속하기: 켜기/끊기, QR, 주소, 잠금 숫자, 들어온 기기 수, "껐다 켜면 주소가 바뀌어요" 안내. 토큰은 "고급" 안에 접어 둔다.
- 갤러리 → 폰에서 올리기: 같은 QR 과 숫자를 보여 준다.
- 폰이 처음 들어오면 숫자 화면 하나. QR 로 왔으면 스쳐 지나간다.

## 한계

- 임시 주소는 껐다 켜면 바뀐다. QR 을 다시 찍으면 된다.
- Cloudflare 의 임시 터널이라 동시 요청 수에 제한이 있다. 큰 영상을 여럿이 동시에 올리는 용도가 아니다.
- 표는 쿠키다. 폰에서 브라우저 데이터를 지우면 숫자를 다시 묻는다.

## 테스트

- 단위 `apps/engine/test/remote.test.ts`: 직접/밖 판별, 숫자 만들기, 짝짓기·10번 제한·파일 기억, 쿠키 읽기.
- 단위 `apps/engine/test/tunnel.test.ts`: quick/token 인자, 주소 읽기, 재시작 백오프.
- 엔진 e2e `apps/engine/test/e2e.remote.test.ts`: 가짜 cloudflared(`fixtures/fake-cloudflared.mjs`) → 켜기 → 주소 →
  밖에서 401 → 짝짓기 → 통과 → 끄면 다 끊김.
- 브라우저 e2e `e2e/6-remote.spec.ts`: 설정 켜기 → QR·숫자, 폰(터널 헤더)으로 숫자 화면 → 맞히면 갤러리, QR 로 오면 안 묻는다.
