# 패키징 · 배포 (3단계)

## 만드는 법

```
pnpm sidecars                 # resources/bin/<platform>/ 와 resources/fonts/ 채우기 (공식 배포본 다운로드)
pnpm build                    # web 빌드 → engine esbuild 번들 + resources/{web,drizzle} + 트레이 아이콘
pnpm --filter @madi/engine package        # 설치 파일 (apps/engine/release/)
pnpm --filter @madi/engine package:dir    # 압축 없이 폴더로 (빠른 확인)
pnpm --filter @madi/engine electron       # 개발 모드로 트레이 앱 실행 (빌드 뒤)
```

macOS 의 `whisper-cli` 는 릴리스 바이너리가 없어서 소스로 만든다 (릴리스 워크플로 참고).
로컬에서 만들려면:

```
git clone --depth 1 -b v1.7.6 https://github.com/ggml-org/whisper.cpp /tmp/whisper
cmake -S /tmp/whisper -B /tmp/whisper/build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_EXAMPLES=ON
cmake --build /tmp/whisper/build --config Release --target whisper-cli
cp /tmp/whisper/build/bin/whisper-cli resources/bin/darwin-arm64/
```

## 릴리스

`v0.2.0` 처럼 태그를 푸시하면 `.github/workflows/release.yml` 이 돈다.

1. `prepare` — 태그 이름으로 **draft** Release 를 만든다 (세 빌드가 동시에 만들려다 부딪히지 않게).
2. `build` — Windows x64 (`.exe`, NSIS 원클릭·설치 후 자동 실행), macOS arm64 / x64 (`.pkg` 설치 마법사 + `.zip` 업데이트용) 를 만들어 draft 에 올린다.
3. `publish` — 두 macOS 러너가 각자 올린 `latest-mac.yml` 을 `apps/engine/scripts/merge-latest-mac.mjs` 로 합쳐 다시 올리고
   (안 합치면 나중 것이 앞 것을 덮어 electron-updater 가 한쪽 아키텍처 zip 만 본다), 파일이 다 있는지 확인한 뒤 draft 를 풀어 latest 로 만든다.

설치된 앱은 electron-updater 로 이 Release 를 보고 스스로 갱신한다(6시간마다, 다음 실행 때 적용).
버전은 `apps/engine/package.json` 의 `version` 이다 — 태그와 맞춘다.

새 릴리스는 태그를 손으로 푸시하지 않아도 된다: `apps/engine/package.json` 의 `version` 을 올려 main 에 넣은 뒤
Actions → Release → Run workflow 에서 `tag` 에 `v0.2.0` 처럼 **아직 없는** 태그를 주면, 그 커밋에 태그를 찍고 Release 까지 만든다
(version 과 태그가 다르면 멈춘다).

`workflow_dispatch` 를 `tag` 없이 돌리면 Release 없이 아티팩트만 남는다. 설정을 바꿨을 때 먼저 이걸로 확인한다.
`tag` 에 `v0.1.1` 처럼 **이미 있는** 태그를 주면 그 태그의 코드를 **main 의 워크플로**로 다시 빌드해 같은 Release 에 올린다 —
워크플로만 고쳤을 때 태그를 다시 찍지 않아도 된다.

러너마다 자기 아키텍처만 만든다 (`electron-builder --mac pkg zip --arm64` 처럼 target 과 arch 를 CLI 로).
`electron-builder.yml` 에는 arch 목록을 두지 않는다: 두면 CLI 에 `--arm64` 를 줘도 목록대로 두 아키텍처를 다 만들어
사이드카 없는 빌드가 생기고 pkg 임시 파일이 충돌한다.

## 설치 페이지

`apps/site/index.html` 하나. `.github/workflows/pages.yml` 이 `main` 에 올라갈 때 GitHub Pages 로 배포한다 →
**https://monandoll.github.io/madi/**

페이지는 브라우저에서 OS 를 알아내고(Windows / Mac Apple Silicon / Mac Intel — 맥 아키텍처는 `userAgentData` → WebGL 렌더러 → 기본 Apple Silicon)
GitHub API 의 `releases/latest` 에서 그 파일을 골라 **버튼 하나**로 준다. API 를 못 읽으면 릴리스 페이지로 보낸다.
폰에서 열면 "PC 에서 열어주세요"만 보인다.

설치 흐름: 버튼 → 받은 파일 열기 → (서명 경고 한 번) → 설치 → 앱이 뜨고 **설정 전이면 브라우저를 스스로 연다** (`main/index.ts`).
macOS 는 `pkg-scripts/postinstall` 이 설치 직후 앱을 띄운다.

## 패키지 안 구조

```
resources/            (= process.resourcesPath, 엔진의 MADI_ROOT)
  web/                브라우저 UI
  drizzle/            마이그레이션
  bin/<platform>/     ffmpeg, ffprobe, whisper-cli, cloudflared, yt-dlp
  fonts/              Pretendard OTF (자막 번인)
  tray.png            트레이 아이콘
app.asar              main.mjs (esbuild 번들) + package.json
app.asar.unpacked/    better-sqlite3 (네이티브)
```

## 서명 · 공증

서명이 없으면 받은 설치 파일을 처음 열 때 OS 가 막는다.
- macOS: 「Apple은 … 악성 코드가 없음을 확인할 수 없습니다」 (macOS 15 부터는 그 창에 "열기"가 없다) → 완료 → 시스템 설정 → 개인정보 보호 및 보안 → 맨 아래 "그래도 열기". pkg 로 설치된 앱 자체는 격리 표시가 없어 그 뒤로는 경고 없이 뜬다.
- Windows: 파란 SmartScreen → 추가 정보 → 실행.

설치 페이지(`apps/site`)가 이 단계를 OS 별로 안내한다. 하지만 **근본 해결은 서명·공증**뿐이다. 릴리스 워크플로는 아래 secrets 가 있으면 자동으로 서명·공증하고, 없으면 서명 없이 만든다 (설정 파일은 손댈 것 없음).

### macOS (Apple Developer Program, 연 US$99)

1. https://developer.apple.com/programs/ 가입 (개인 계정이면 됨, 승인까지 1~2일).
2. Mac 에서 **키체인 접근 → 인증서 지원 → 인증 기관에서 인증서 요청** 으로 CSR 을 만든다.
3. https://developer.apple.com/account/resources/certificates 에서 인증서 **두 개**를 만든다: **Developer ID Application** (앱), **Developer ID Installer** (pkg). 둘 다 CSR 로 만들고 내려받아 더블클릭해 키체인에 넣는다.
4. 키체인 접근에서 그 두 인증서(개인 키 포함)를 **같이 선택 → 내보내기 → .p12** (암호 지정). 터미널에서 base64 로: `base64 -i madi.p12 | pbcopy`.
5. https://account.apple.com → 로그인 및 보안 → **앱 암호** 하나 만든다 (공증용).
6. **Team ID**: https://developer.apple.com/account → Membership details.
7. GitHub → 저장소 → Settings → Secrets and variables → Actions 에 넣는다:

| secret | 값 |
|---|---|
| `MAC_CERT_P12` | 4 의 base64 문자열 |
| `MAC_CERT_PASSWORD` | 4 의 .p12 암호 |
| `APPLE_ID` | Apple 계정 이메일 |
| `APPLE_APP_SPECIFIC_PASSWORD` | 5 의 앱 암호 |
| `APPLE_TEAM_ID` | 6 |

8. 다음 릴리스부터 electron-builder 가 앱(안의 ffmpeg·whisper-cli·cloudflared·yt-dlp·better-sqlite3 까지, `entitlements.mac.plist` 권한으로)과 pkg 를 서명하고 Apple 에 공증(notarize)·스테이플한다. 워크플로가 `spctl -a -t install` 로 "Notarized Developer ID" 를 확인한다. 실패하면 그 단계 로그를 본다 (흔한 원인: .p12 에 Installer 인증서가 빠짐, 앱 암호 오타).

### Windows (선택)

SmartScreen 을 없애려면 코드 서명 인증서가 필요하다. 저렴한 쪽부터:
- **Azure Trusted Signing** (월 US$10 안팎, 개인은 아직 지역 제한) — electron-builder 의 `win.azureSignOptions`.
- OV/EV 코드 서명 인증서 (연 US$200~400, SSL.com·Sectigo 등). .pfx 를 base64 로 `WIN_CERT_PFX`, 암호를 `WIN_CERT_PASSWORD` 에 넣으면 워크플로가 서명한다. OV 는 서명해도 평판이 쌓일 때까지 SmartScreen 이 몇 주 더 뜰 수 있다.

Windows 는 서명이 없어도 "추가 정보 → 실행" 두 번 누르면 되므로, macOS 부터 한다.

## 사이드카 출처

| 것 | Windows | macOS |
|---|---|---|
| ffmpeg/ffprobe | BtbN FFmpeg-Builds master-latest win64 gpl (NVENC 포함) | osxexperts (arm64) / evermeet (x64) 정적 빌드 |
| whisper-cli | whisper.cpp 릴리스 `whisper-bin-x64.zip` (CPU) | 소스 빌드 (정적, Metal) |
| cloudflared | cloudflared 릴리스 | cloudflared 릴리스 |
| yt-dlp (링크로 배우기) | yt-dlp 릴리스 latest `yt-dlp.exe` (단일 실행 파일) | `yt-dlp_macos` (universal2) |
| Pretendard | orioncactus/pretendard 릴리스 OTF | 같음 |

GPU 자막(CUDA)은 CUDA 런타임 DLL 까지 동봉해야 해서 뒤로 뒀다. 엔진은 어느 빌드든 같은 인자로 부른다.

## 밖에서 접속 (Cloudflare Tunnel)

1. Cloudflare Zero Trust → Networks → Tunnels 에서 터널을 만들고 토큰을 복사한다.
2. Public hostname 을 `http://localhost:41520` 으로 잡는다.
3. Access → Applications 에서 그 호스트에 이메일 OTP 정책을 건다 (앱엔 로그인이 없다).
4. 마디 설정 → 밖에서 접속하기에 토큰을 붙여 넣는다. 엔진이 `cloudflared tunnel run --token` 을 띄우고 죽으면 다시 띄운다.
