# xcodebuild test 전체 로그

실행: 2026-09-26 01:49
머신: macOS 27.0 · arm64
Xcode: Xcode 27.0 · Swift: swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)

```
$ xcodebuild -project Madi.xcodeproj -scheme Madi -configuration Debug test
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Madi.xcodeproj -scheme Madi -configuration Debug test -derivedDataPath build
Resolve Package Graph
Resolved source packages:
  swift-transformers: https://github.com/huggingface/swift-transformers.git @ 0.1.8
  whisperkit: https://github.com/argmaxinc/WhisperKit @ 0.9.4
  swift-argument-parser: https://github.com/apple/swift-argument-parser.git @ 1.3.0
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64, id:00006001-000A083A11F8C01E, name:My Mac }
{ platform:macOS, arch:x86_64, id:00006001-000A083A11F8C01E, name:My Mac }
{ platform:macOS, name:Any Mac }
ComputePackagePrebuildTargetDependencyGraph
Prepare packages
CreateBuildRequest
SendProjectDescription
CreateBuildOperation
ComputeTargetDependencyGraph
note: Building targets in dependency order
note: Target dependency graph (13 targets)
    Target 'MadiTests' in project 'Madi'
        ➜ Explicit dependency on target 'MadiKit' in project 'Madi'
    Target 'MadiSpike' in project 'Madi'
        ➜ Explicit dependency on target 'MadiKit' in project 'Madi'
    Target 'Madi' in project 'Madi'
        ➜ Explicit dependency on target 'MadiKit' in project 'Madi'
    Target 'MadiKit' in project 'Madi'
        ➜ Explicit dependency on target 'WhisperKit-product' in project 'whisperkit'
    Target 'WhisperKit-product' in project 'whisperkit'
        ➜ Explicit dependency on target 'WhisperKit' in project 'whisperkit'
        ➜ Explicit dependency on target 'Transformers-product' in project 'swift-transformers'
    Target 'WhisperKit' in project 'whisperkit'
        ➜ Explicit dependency on target 'Transformers-product' in project 'swift-transformers'
    Target 'Transformers-product' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Tokenizers' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Generation' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Models' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Hub' in project 'swift-transformers'
        ➜ Explicit dependency on target 'TensorUtils' in project 'swift-transformers'
    Target 'Models' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Hub' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Tokenizers' in project 'swift-transformers'
        ➜ Explicit dependency on target 'TensorUtils' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Generation' in project 'swift-transformers'
    Target 'Generation' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Hub' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Tokenizers' in project 'swift-transformers'
        ➜ Explicit dependency on target 'TensorUtils' in project 'swift-transformers'
    Target 'TensorUtils' in project 'swift-transformers' (no dependencies)
    Target 'Tokenizers' in project 'swift-transformers'
        ➜ Explicit dependency on target 'Hub' in project 'swift-transformers'
    Target 'Hub' in project 'swift-transformers'
        ➜ Explicit dependency on target 'swift-transformers_Hub' in project 'swift-transformers'
    Target 'swift-transformers_Hub' in project 'swift-transformers' (no dependencies)
GatherProvisioningInputs
CreateBuildDescription
ClangStatCache /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk /Users/kimeunjoong/orca/madi/build/SDKStatCaches.noindex/macosx27.0-26A425-7231f6df4def33e022ae2eb8f782df1a.sdkstatcache
    cd /Users/kimeunjoong/orca/madi/Madi.xcodeproj
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -o /Users/kimeunjoong/orca/madi/build/SDKStatCaches.noindex/macosx27.0-26A425-7231f6df4def33e022ae2eb8f782df1a.sdkstatcache
Copy /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks/MadiKit.framework /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/MadiKit.framework (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks -remove-static-executable /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/MadiKit.framework /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks
CodeSign /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks/MadiKit.framework/Versions/A (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks/MadiKit.framework/Versions/A
/Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks/MadiKit.framework/Versions/A: replacing existing signature
ProcessInfoPlistFile /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Info.plist /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/Madi.build/empty-Madi.plist (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-infoPlistUtility /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/Madi.build/empty-Madi.plist -producttype com.apple.product-type.application -genpkginfo /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/PkgInfo -expandbuildsettings -platform macosx -scanforprivacyfile /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks/MadiKit.framework -scanforprivacyfile /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Resources/swift-transformers_Hub.bundle -o /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Info.plist
CopySwiftLibs /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-swiftStdLibTool --copy --verbose --sign - --scan-executable /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/MacOS/Madi.debug.dylib --scan-folder /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks --scan-folder /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/PlugIns --scan-folder /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Library/SystemExtensions --scan-folder /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Extensions --scan-folder /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/MadiKit.framework --platform macosx --toolchain /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --destination /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/Frameworks --strip-bitcode --strip-bitcode-tool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/bitcode_strip --emit-dependency-info /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/Madi.build/SwiftStdLibToolInputDependencies.dep --filter-for-swift-os --back-deploy-swift-span
CodeSign /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/MacOS/Madi.debug.dylib (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --generate-entitlement-der /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/MacOS/Madi.debug.dylib
/Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/MacOS/Madi.debug.dylib: replacing existing signature
CodeSign /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/MacOS/__preview.dylib (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --generate-entitlement-der /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/MacOS/__preview.dylib
/Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app/Contents/MacOS/__preview.dylib: replacing existing signature
CodeSign /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --entitlements /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/Madi.build/Madi.app.xcent --timestamp\=none --generate-entitlement-der /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app
/Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app: replacing existing signature
Validate /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-validationUtility /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app -no-validate-extension -infoplist-subpath Contents/Info.plist
RegisterWithLaunchServices /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-lsregisterurl --record-path /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/XCBuildData/registered-launchservices.txt -- /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app
PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/ExplicitPrecompiledModules
PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/SDKExplicitPrecompiledModules
PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules
2026-09-26 01:49:51.497 xcodebuild[255:103707045]  DVTAssertions: Warning in IDEFrameworks/IDEFoundation/Execution/LaunchSystem/IDELaunchSession.m:395
Details:  setRunnablePIDWithDiagnostics:logSection:andCompletionHandler: called without a completion handler - blocking until diagnostics setup completes. Callers should migrate to using a completion handler for better performance.
Object:   <IDELaunchSession: 0x7acd3ec180>
Method:   -setRunnablePIDWithDiagnostics:logSection:andCompletionHandler:
Thread:   <NSThread: 0x7acf480400>{number = 8, name = (null)}
Please file a bug at https://feedbackassistant.apple.com with this warning message and any useful information you can provide.
Test Suite 'All tests' started at 2026-09-26 01:49:51.667.
Test Suite 'All tests' passed at 2026-09-26 01:49:51.668.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
􀟈 Test run started.
􀄵 Testing Library Version: 2084
􀄵 Target Platform: arm64e-apple-macos14.0
􀟈 Suite CaptionGateTests started.
􀟈 Test "낱말 안에서는 절대 끊지 않는다" started.
2026-09-26 01:49:51.672328+0900 xctest[575:103707374] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "낱말 안에서는 절대 끊지 않는다" passed after 0.001 seconds.
􀟈 Test "글자 수 상한을 넘지 않는다" started.
2026-09-26 01:49:51.672916+0900 xctest[575:103707369] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "글자 수 상한을 넘지 않는다" passed after 0.001 seconds.
􀟈 Test "상한까지 눌러 담지 않는다 — 중앙값이 목표 근처다" started.
2026-09-26 01:49:51.673735+0900 xctest[575:103707370] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "상한까지 눌러 담지 않는다 — 중앙값이 목표 근처다" passed after 0.001 seconds.
􀟈 Test "목표를 채운 뒤 말이 쉬면 거기서 끊는다" started.
2026-09-26 01:49:51.674157+0900 xctest[575:103707375] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "목표를 채운 뒤 말이 쉬면 거기서 끊는다" passed after 0.001 seconds.
􀟈 Test "장면 오프셋을 빼서 장면 로컬 시각으로 만든다" started.
2026-09-26 01:49:51.675361+0900 xctest[575:103707369] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "장면 오프셋을 빼서 장면 로컬 시각으로 만든다" passed after 0.001 seconds.
􀟈 Test "세 슬롯 모두 G4 를 통과한다" started.
2026-09-26 01:49:51.675720+0900 xctest[575:103707374] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "세 슬롯 모두 G4 를 통과한다" passed after 0.010 seconds.
􀟈 Test "글자를 줄이면 G4 가 실패한다" started.
2026-09-26 01:49:51.685909+0900 xctest[575:103707370] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "글자를 줄이면 G4 가 실패한다" passed after 0.001 seconds.
􀟈 Test "15자까지는 통과, 넘으면 실패" started.
2026-09-26 01:49:51.686452+0900 xctest[575:103707369] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "15자까지는 통과, 넘으면 실패" passed after 0.007 seconds.
􀟈 Test "자막이 없으면 통과가 아니라 판정 불가" started.
2026-09-26 01:49:51.693647+0900 xctest[575:103707375] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "자막이 없으면 통과가 아니라 판정 불가" passed after 0.001 seconds.
􀟈 Test "싱크가 맞으면 통과, 어긋나면 실패" started.
􁁛 Test "싱크가 맞으면 통과, 어긋나면 실패" passed after 0.001 seconds.
􀟈 Test "전사가 없으면 통과가 아니라 판정 불가" started.
􁁛 Test "전사가 없으면 통과가 아니라 판정 불가" passed after 0.001 seconds.
􀟈 Test "자막 상자 안에 든 어깨선 위 관절을 찾아낸다" started.
􁁛 Test "자막 상자 안에 든 어깨선 위 관절을 찾아낸다" passed after 0.001 seconds.
􀟈 Test "확신이 낮은 관절은 세지 않는다" started.
􁁛 Test "확신이 낮은 관절은 세지 않는다" passed after 0.001 seconds.
􁁛 Suite CaptionGateTests passed after 0.023 seconds.
􀟈 Suite CompositionTests started.
􀟈 Test "최소 JSON 이 기본값과 함께 파싱된다" started.
􁁛 Test "최소 JSON 이 기본값과 함께 파싱된다" passed after 0.001 seconds.
􀟈 Test "captionSlot 이 없으면 거절한다" started.
􁁛 Test "captionSlot 이 없으면 거절한다" passed after 0.001 seconds.
􀟈 Test "장면이 자막 위치를 덮어쓸 수 있다" started.
􁁛 Test "장면이 자막 위치를 덮어쓸 수 있다" passed after 0.001 seconds.
􀟈 Test "JSON 키 이름이 in/out/videoId/templateId 그대로다" started.
􁁛 Test "JSON 키 이름이 in/out/videoId/templateId 그대로다" passed after 0.001 seconds.
􀟈 Test "라운드트립해도 값이 같다" started.
􁁛 Test "라운드트립해도 값이 같다" passed after 0.001 seconds.
􀟈 Test "장면 길이는 speed 를 반영한다" started.
􁁛 Test "장면 길이는 speed 를 반영한다" passed after 0.001 seconds.
􀟈 Test "장면 오프셋은 앞 장면 길이의 누적이다" started.
􁁛 Test "장면 오프셋은 앞 장면 길이의 누적이다" passed after 0.001 seconds.
􀟈 Test "배열 순서가 결과물 순서다 — 원본 순서와 달라도 된다" started.
􁁛 Test "배열 순서가 결과물 순서다 — 원본 순서와 달라도 된다" passed after 0.001 seconds.
􀟈 Test "out 이 in 보다 앞이면 거절한다" started.
􁁛 Test "out 이 in 보다 앞이면 거절한다" passed after 0.001 seconds.
􀟈 Test "자막 end 가 start 보다 앞이면 거절한다" started.
􁁛 Test "자막 end 가 start 보다 앞이면 거절한다" passed after 0.001 seconds.
􀟈 Test "자막이 장면 길이를 넘으면 거절한다" started.
􁁛 Test "자막이 장면 길이를 넘으면 거절한다" passed after 0.001 seconds.
􀟈 Test "강조 구간이 텍스트 밖이면 거절한다" started.
􁁛 Test "강조 구간이 텍스트 밖이면 거절한다" passed after 0.001 seconds.
􀟈 Test "auto 가 아닌 리프레임에 키프레임이 없으면 거절한다" started.
􁁛 Test "auto 가 아닌 리프레임에 키프레임이 없으면 거절한다" passed after 0.001 seconds.
􀟈 Test "장면이 없으면 거절한다" started.
􁁛 Test "장면이 없으면 거절한다" passed after 0.001 seconds.
􀟈 Test "payload 에 스타일 키가 있으면 거절한다" started.
􀟈 Test case passing 1 argument entry → ""fontSize": 72" to "payload 에 스타일 키가 있으면 거절한다" started.
​􀟈 Test case passing 1 argument entry → ""color": "red"" to "payload 에 스타일 키가 있으면 거절한다" started.
​􀟈 Test case passing 1 argument entry → ""strokeWidth": 7" to "payload 에 스타일 키가 있으면 거절한다" started.
​􀟈 Test case passing 1 argument entry → ""x": 0.5" to "payload 에 스타일 키가 있으면 거절한다" started.
​􀟈 Test case passing 1 argument entry → ""opacity": 0.8" to "payload 에 스타일 키가 있으면 거절한다" started.
​􀟈 Test case passing 1 argument entry → ""easing": "easeOut"" to "payload 에 스타일 키가 있으면 거절한다" started.
​􁁛 Test "payload 에 스타일 키가 있으면 거절한다" with 6 test cases passed after 0.001 seconds.
􀟈 Test "중첩된 payload 안쪽의 스타일 키도 거절한다" started.
􁁛 Test "중첩된 payload 안쪽의 스타일 키도 거절한다" passed after 0.001 seconds.
􀟈 Test "배열 안에 숨긴 스타일 키도 거절한다" started.
􁁛 Test "배열 안에 숨긴 스타일 키도 거절한다" passed after 0.001 seconds.
􀟈 Test "대소문자를 바꿔도 스타일 키는 거절한다" started.
􁁛 Test "대소문자를 바꿔도 스타일 키는 거절한다" passed after 0.001 seconds.
􀟈 Test "스타일이 아닌 payload 는 통과한다" started.
􁁛 Test "스타일이 아닌 payload 는 통과한다" passed after 0.001 seconds.
􀟈 Test "키프레임 사이를 선형 보간한다" started.
􁁛 Test "키프레임 사이를 선형 보간한다" passed after 0.001 seconds.
􀟈 Test "fixed 는 첫 키프레임을 전 구간 고정한다" started.
􁁛 Test "fixed 는 첫 키프레임을 전 구간 고정한다" passed after 0.001 seconds.
􁁛 Suite CompositionTests passed after 0.007 seconds.
􀟈 Suite ReframeLimitsTests started.
􀟈 Test "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
􀟈 Test case passing 2 arguments source → (2160.0, 3840.0), expected → 2160.0 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􀟈 Test case passing 2 arguments source → (1080.0, 1920.0), expected → 1080.0 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􀟈 Test case passing 2 arguments source → (3840.0, 2160.0), expected → 1215.0 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􀟈 Test case passing 2 arguments source → (1920.0, 1080.0), expected → 607.5 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􁁛 Test "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" with 4 test cases passed after 0.002 seconds.
􀟈 Test "가로 1080p 는 확대하기 전에 이미 업스케일이다" started.
􁁛 Test "가로 1080p 는 확대하기 전에 이미 업스케일이다" passed after 0.001 seconds.
􀟈 Test "세로 1080p 의 무손실 상한은 배율 1.00 이다" started.
􁁛 Test "세로 1080p 의 무손실 상한은 배율 1.00 이다" passed after 0.001 seconds.
􀟈 Test "세로 4K 는 maxUpscale 1.25 에서 배율 2.5 까지 쓴다" started.
􁁛 Test "세로 4K 는 maxUpscale 1.25 에서 배율 2.5 까지 쓴다" passed after 0.001 seconds.
􀟈 Test "목표에 닿으면 reachedTarget 이 참이다 — 세로 4K" started.
􁁛 Test "목표에 닿으면 reachedTarget 이 참이다 — 세로 4K" passed after 0.001 seconds.
􀟈 Test "원본 한계면 상한에서 자르고 못 닿았다고 알린다 — 저해상도 세로" started.
􁁛 Test "원본 한계면 상한에서 자르고 못 닿았다고 알린다 — 저해상도 세로" passed after 0.001 seconds.
􀟈 Test "이미 목표보다 크면 확대하지 않는다" started.
􁁛 Test "이미 목표보다 크면 확대하지 않는다" passed after 0.001 seconds.
􀟈 Test "스타일이 상한을 정한다 — 코드에 박혀 있지 않다" started.
2026-09-26 01:49:51.706704+0900 xctest[575:103707375] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "스타일이 상한을 정한다 — 코드에 박혀 있지 않다" passed after 0.001 seconds.
􁁛 Suite ReframeLimitsTests passed after 0.006 seconds.
􀟈 Suite ReframePlannerTests started.
􀟈 Test "NormRect.y 는 아래에서 잰다 — 중심을 위로 올리면 y 가 커진다" started.
􁁛 Test "NormRect.y 는 아래에서 잰다 — 중심을 위로 올리면 y 가 커진다" passed after 0.001 seconds.
􀟈 Test "크롭은 원본 밖으로 나가지 않는다" started.
􁁛 Test "크롭은 원본 밖으로 나가지 않는다" passed after 0.001 seconds.
􀟈 Test "배율 1 크롭은 가로 원본에서 전체 높이를 쓴다" started.
􁁛 Test "배율 1 크롭은 가로 원본에서 전체 높이를 쓴다" passed after 0.001 seconds.
􀟈 Test "스무딩이 좌우 떨림을 줄인다 (G3)" started.
􁁛 Test "스무딩이 좌우 떨림을 줄인다 (G3)" passed after 0.001 seconds.
􀟈 Test "마스크가 빈 구간은 이웃에서 채운다 — 화면 중앙으로 튀지 않는다" started.
􁁛 Test "마스크가 빈 구간은 이웃에서 채운다 — 화면 중앙으로 튀지 않는다" passed after 0.001 seconds.
􀟈 Test "입력 없음이 20% 를 넘으면 판정 불가 — 되돌리지 않는다" started.
􁁛 Test "입력 없음이 20% 를 넘으면 판정 불가 — 되돌리지 않는다" passed after 0.001 seconds.
􀟈 Test "확대 상한에 걸려 못 닿으면 원본 한계 — 되돌리지 않는다" started.
􁁛 Test "확대 상한에 걸려 못 닿으면 원본 한계 — 되돌리지 않는다" passed after 0.001 seconds.
􀟈 Test "확대 여력이 있는데 못 닿으면 진짜 실패 — 되돌린다" started.
􁁛 Test "확대 여력이 있는데 못 닿으면 진짜 실패 — 되돌린다" passed after 0.001 seconds.
􀟈 Test "충분히 큰 피사체는 통과한다" started.
􁁛 Test "충분히 큰 피사체는 통과한다" passed after 0.001 seconds.
􀟈 Test "크롭이 전체 높이를 쓰면 새로 자르지 않는다" started.
􁁛 Test "크롭이 전체 높이를 쓰면 새로 자르지 않는다" passed after 0.001 seconds.
􀟈 Test "확대가 머리를 자르면 G2 가 실패한다" started.
􁁛 Test "확대가 머리를 자르면 G2 가 실패한다" passed after 0.001 seconds.
􀟈 Test "원본에서 이미 잘린 쪽은 분모에서 뺀다" started.
􁁛 Test "원본에서 이미 잘린 쪽은 분모에서 뺀다" passed after 0.001 seconds.
􀟈 Test "원본이 위아래 다 잘려 있으면 통과가 아니라 판정 불가" started.
􁁛 Test "원본이 위아래 다 잘려 있으면 통과가 아니라 판정 불가" passed after 0.001 seconds.
􀟈 Test "좌우로 넘치는 건 G2 가 보지 않는다" started.
􁁛 Test "좌우로 넘치는 건 G2 가 보지 않는다" passed after 0.001 seconds.
􀟈 Test "auto 장면은 keyframes 로 바뀌고 JSON 왕복을 견딘다" started.
2026-09-26 01:49:51.714596+0900 xctest[575:103707370] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "auto 장면은 keyframes 로 바뀌고 JSON 왕복을 견딘다" passed after 0.001 seconds.
􀟈 Test "키프레임 시각은 장면 로컬 출력 초다 — 배속을 반영한다" started.
􁁛 Test "키프레임 시각은 장면 로컬 출력 초다 — 배속을 반영한다" passed after 0.001 seconds.
􁁛 Suite ReframePlannerTests passed after 0.006 seconds.
􀟈 Suite SilentSourceRenderTests started.
􀟈 Test "오디오 트랙이 없는 원본도 내보내진다" started.
Resolve Package Graph
2026-09-26 01:49:51.905891+0900 xctest[575:103707374] [ClientDonation] (+[PPSClientDonation isRegisteredSubsystem:category:]) Permission denied: CoreMedia / CM-EXPORT
2026-09-26 01:49:51.907819+0900 xctest[575:103707374] [ClientDonation] (+[PPSClientDonation isRegisteredSubsystem:category:]) Permission denied: CoreMedia / CM-ASSETCREATION
2026-09-26 01:49:51.909158+0900 xctest[575:103707374] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
2026-09-26 01:49:51.920102+0900 xctest[575:103707375] [] <<< URLAsset >>> signalled err=-12170 at <>:2348
2026-09-26 01:49:52.089295+0900 xctest[575:103707477] [render] 렌더 완료 silent
􁁛 Test "오디오 트랙이 없는 원본도 내보내진다" passed after 0.375 seconds.
􁁛 Suite SilentSourceRenderTests passed after 0.375 seconds.
􀟈 Suite StyleTests started.
􀟈 Test "기본 스타일이 번들에서 읽히고 검증을 통과한다" started.
2026-09-26 01:49:52.091145+0900 xctest[575:103707477] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "기본 스타일이 번들에서 읽히고 검증을 통과한다" passed after 0.001 seconds.
􀟈 Test "범위를 벗어난 값은 거절한다" started.
2026-09-26 01:49:52.091532+0900 xctest[575:103707477] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "범위를 벗어난 값은 거절한다" passed after 0.001 seconds.
􀟈 Test "보조 문구가 화면 밖으로 나가면 거절한다" started.
2026-09-26 01:49:52.092030+0900 xctest[575:103707476] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "보조 문구가 화면 밖으로 나가면 거절한다" passed after 0.001 seconds.
􀟈 Test "보조 문구는 본문이 움직이면 같이 움직인다" started.
2026-09-26 01:49:52.092363+0900 xctest[575:103707369] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "보조 문구는 본문이 움직이면 같이 움직인다" passed after 0.001 seconds.
􀟈 Test "색은 #RRGGBB 와 #RRGGBBAA 를 읽는다" started.
􁁛 Test "색은 #RRGGBB 와 #RRGGBBAA 를 읽는다" passed after 0.001 seconds.
􁁛 Suite StyleTests passed after 0.002 seconds.
􀟈 Suite CaptionGeometryTests started.
􀟈 Test "그려진 글자 높이가 스타일이 요구한 비율과 맞는다" started.
2026-09-26 01:49:52.093126+0900 xctest[575:103707476] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "그려진 글자 높이가 스타일이 요구한 비율과 맞는다" passed after 0.191 seconds.
􀟈 Test "글자 아래끝이 스타일이 요구한 위치에 온다" started.
2026-09-26 01:49:52.284815+0900 xctest[575:103707370] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "글자 아래끝이 스타일이 요구한 위치에 온다" passed after 0.184 seconds.
􀟈 Test "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
􀟈 Test case passing 1 argument slot → .upperBody to "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
2026-09-26 01:49:52.469406+0900 xctest[575:103707478] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
​􀟈 Test case passing 1 argument slot → .fullBody to "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
2026-09-26 01:49:52.651437+0900 xctest[575:103707479] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
​􀟈 Test case passing 1 argument slot → .lowerBody to "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
2026-09-26 01:49:52.837685+0900 xctest[575:103707376] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
Resolve Package Graph
​􁁛 Test "슬롯마다 자막이 스타일이 정한 높이에 온다" with 3 test cases passed after 0.554 seconds.
􀟈 Test "슬롯이 바뀌면 보조 문구도 본문을 따라 같이 움직인다" started.
2026-09-26 01:49:53.024120+0900 xctest[575:103707375] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "슬롯이 바뀌면 보조 문구도 본문을 따라 같이 움직인다" passed after 0.001 seconds.
􀟈 Test "자막 길이가 달라도 글자 크기는 고정이다" started.
2026-09-26 01:49:53.024783+0900 xctest[575:103707369] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "자막 길이가 달라도 글자 크기는 고정이다" passed after 0.536 seconds.
􀟈 Test "폰트 크기는 스타일 값이 아니라 글자 높이에서 역산된다" started.
2026-09-26 01:49:53.560995+0900 xctest[575:103707374] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "폰트 크기는 스타일 값이 아니라 글자 높이에서 역산된다" passed after 0.001 seconds.
􀟈 Test "어절 단위로만 줄을 바꾼다" started.
2026-09-26 01:49:53.561501+0900 xctest[575:103707475] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "어절 단위로만 줄을 바꾼다" passed after 0.001 seconds.
􀟈 Test "Pretendard 가 등록되고 wght 축이 실제로 먹는다" started.
􁁛 Test "Pretendard 가 등록되고 wght 축이 실제로 먹는다" passed after 0.002 seconds.
􁁛 Suite CaptionGeometryTests passed after 1.472 seconds.
􁁛 Test run with 72 tests in 7 suites passed after 1.894 seconds.
2026-09-26 01:49:53.835 xcodebuild[255:103706853] [MT] IDETestOperationsObserverDebug: 2.371 elapsed -- Testing started completed.
2026-09-26 01:49:53.835 xcodebuild[255:103706853] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-09-26 01:49:53.835 xcodebuild[255:103706853] [MT] IDETestOperationsObserverDebug: 2.371 sec, +2.371 sec -- end
Test session results, code coverage, and logs:
	/Users/kimeunjoong/orca/madi/build/Logs/Test/Test-Madi-2026.09.26_01-49-50-+0900.xcresult
** TEST SUCCEEDED **
Resolve Package Graph
Testing started
```
