# 타깃 환경

1차 타깃은 **macOS와 Windows 둘 다**. 선생님 PC가 어느 쪽이든 같은 설치 파일 흐름(트레이 앱 → 브라우저)이 돌아야 한다.

| 플랫폼 | 아키텍처 | 영상 인코더 | 자막(whisper.cpp) |
|---|---|---|---|
| Windows 10/11 | x64 | NVIDIA면 `h264_nvenc`, 아니면 `libx264` | CUDA 빌드 (없으면 CPU) |
| macOS 13+ | arm64 (Apple Silicon) | `h264_videotoolbox` | CoreML 빌드 |
| macOS 13+ | x64 (Intel) | `h264_videotoolbox` | CPU |

인코더는 코드에 박지 않는다. 엔진이 기동 시 `ffmpeg -encoders` 로 실제 가능한 것을 확인하고
`@madi/ffmpeg-presets`의 `pickEncoder()` 로 고른다. 하드웨어 인코더가 없으면 자동으로 `libx264`.

## 실제 사용 PC (확인되면 채운다)

| 항목 | 값 |
|---|---|
| OS | [확인 필요] |
| CPU / GPU | [확인 필요] |
| RAM | [확인 필요] |
| 영상 원본 폴더 | [확인 필요 — 카메라/폰에서 옮겨 두는 경로] |
| 브라우저 | 최신 Chrome / Safari |

## 사이드카 바이너리 배치

`apps/engine/src/main/sidecar.ts`가 `process.platform`-`process.arch` 로 폴더를 고른다.

```
resources/bin/
  win32-x64/     ffmpeg.exe  ffprobe.exe  whisper-cli.exe  cloudflared.exe  yt-dlp.exe
  darwin-arm64/  ffmpeg      ffprobe      whisper-cli      cloudflared      yt-dlp
  darwin-x64/    ffmpeg      ffprobe      whisper-cli      cloudflared      yt-dlp
```

바이너리는 git-lfs. 개발 환경에서 폴더가 비어 있으면 `MADI_FFMPEG` / `MADI_FFPROBE` 환경변수,
그 다음 `@ffmpeg-installer` 패키지, 마지막으로 PATH 순으로 찾는다.
