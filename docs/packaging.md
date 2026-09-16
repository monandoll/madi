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

`v0.2.0` 처럼 태그를 푸시하면 `.github/workflows/release.yml` 이 Windows x64, macOS arm64, macOS x64 를 만들어
GitHub Release 에 올린다. 설치된 앱은 electron-updater 로 이 Release 를 보고 스스로 갱신한다(6시간마다, 다음 실행 때 적용).
버전은 `apps/engine/package.json` 의 `version` 이다 — 태그와 맞춘다.

`workflow_dispatch` 로 돌리면 Release 없이 아티팩트만 남는다. 설정을 바꿨을 때 먼저 이걸로 확인한다.

## 패키지 안 구조

```
resources/            (= process.resourcesPath, 엔진의 MADI_ROOT)
  web/                브라우저 UI
  drizzle/            마이그레이션
  bin/<platform>/     ffmpeg, ffprobe, whisper-cli, cloudflared
  fonts/              Pretendard OTF (자막 번인)
  tray.png            트레이 아이콘
app.asar              main.mjs (esbuild 번들) + package.json
app.asar.unpacked/    better-sqlite3 (네이티브)
```

## 서명

아직 없다. Windows 는 SmartScreen "추가 정보 → 실행", macOS 는 우클릭 → 열기. Apple Developer / 코드 서명 인증서가 생기면
`electron-builder.yml` 의 `mac.identity` 와 `win.certificateFile` 만 채우면 된다.

## 사이드카 출처

| 것 | Windows | macOS |
|---|---|---|
| ffmpeg/ffprobe | BtbN FFmpeg-Builds n7.1 gpl (NVENC 포함) | osxexperts (arm64) / evermeet (x64) 정적 빌드 |
| whisper-cli | whisper.cpp 릴리스 `whisper-bin-x64.zip` (CPU) | 소스 빌드 (정적, Metal) |
| cloudflared | cloudflared 릴리스 | cloudflared 릴리스 |
| Pretendard | orioncactus/pretendard 릴리스 OTF | 같음 |

GPU 자막(CUDA)은 CUDA 런타임 DLL 까지 동봉해야 해서 뒤로 뒀다. 엔진은 어느 빌드든 같은 인자로 부른다.

## 밖에서 접속 (Cloudflare Tunnel)

1. Cloudflare Zero Trust → Networks → Tunnels 에서 터널을 만들고 토큰을 복사한다.
2. Public hostname 을 `http://localhost:41520` 으로 잡는다.
3. Access → Applications 에서 그 호스트에 이메일 OTP 정책을 건다 (앱엔 로그인이 없다).
4. 마디 설정 → 밖에서 접속하기에 토큰을 붙여 넣는다. 엔진이 `cloudflared tunnel run --token` 을 띄우고 죽으면 다시 띄운다.
