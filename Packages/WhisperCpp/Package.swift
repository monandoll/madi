// swift-tools-version:5.9
// Intel(x86_64) 전사 — whisper.cpp 공식 릴리스의 xcframework (MIT). AGENTS.md §3 · §17.
//
// Apple Silicon 은 WhisperKit 을 쓴다. WhisperKit 은 x86_64 로 빌드는 되지만 전사 중 죽는다
// (Rosetta 실측 — docs/stage-3.spec.md 결정 ④). 그래서 Intel 에서만 이걸 쓴다.
//
// ★ 레포에 바이너리를 커밋하지 않는다. SwiftPM 이 **공식 릴리스 주소 · 체크섬**으로 받는다 —
//   버전을 올릴 때는 url 과 checksum(`swift package compute-checksum`)을 같이 바꾼다.
import PackageDescription

let package = Package(
    name: "WhisperCpp",
    platforms: [.macOS(.v14)],
    products: [.library(name: "WhisperCpp", targets: ["whisper"])],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-v1.9.2-xcframework.zip",
            checksum: "af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b"
        ),
    ]
)
