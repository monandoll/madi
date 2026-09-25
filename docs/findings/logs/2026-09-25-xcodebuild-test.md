# xcodebuild test 전체 로그

실행: 2026-09-25 23:00
머신: macOS 27.0 · arm64
Xcode: Xcode 27.0 · Swift: swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)

```
$ xcodebuild -project Madi.xcodeproj -scheme Madi -configuration Debug test
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Madi.xcodeproj -scheme Madi -configuration Debug test -derivedDataPath build
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
note: Target dependency graph (4 targets)
    Target 'MadiTests' in project 'Madi'
        ➜ Explicit dependency on target 'MadiKit' in project 'Madi'
    Target 'MadiSpike' in project 'Madi'
        ➜ Explicit dependency on target 'MadiKit' in project 'Madi'
    Target 'Madi' in project 'Madi'
        ➜ Explicit dependency on target 'MadiKit' in project 'Madi'
    Target 'MadiKit' in project 'Madi' (no dependencies)
GatherProvisioningInputs
CreateBuildDescription
ClangStatCache /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk /Users/kimeunjoong/orca/madi/build/SDKStatCaches.noindex/macosx27.0-26A425-7231f6df4def33e022ae2eb8f782df1a.sdkstatcache
    cd /Users/kimeunjoong/orca/madi/Madi.xcodeproj
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -o /Users/kimeunjoong/orca/madi/build/SDKStatCaches.noindex/macosx27.0-26A425-7231f6df4def33e022ae2eb8f782df1a.sdkstatcache
ProcessInfoPlistFile /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/MadiKit.framework/Versions/A/Resources/Info.plist /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiKit.build/empty-MadiKit.plist (in target 'MadiKit' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-infoPlistUtility /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiKit.build/empty-MadiKit.plist -producttype com.apple.product-type.framework -expandbuildsettings -platform macosx -o /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/MadiKit.framework/Versions/A/Resources/Info.plist
ProcessProductPackaging "" /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiSpike.build/madi-spike.xcent (in target 'MadiSpike' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    
    Entitlements:
    
    {
    "com.apple.application-identifier" = "app.madi.MadiSpike";
    "com.apple.security.get-task-allow" = 1;
}
    
    builtin-productPackagingUtility -entitlements -format xml -o /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiSpike.build/madi-spike.xcent
ProcessProductPackagingDER /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiSpike.build/madi-spike.xcent /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiSpike.build/madi-spike.xcent.der (in target 'MadiSpike' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    /usr/bin/derq query -f xml -i /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiSpike.build/madi-spike.xcent -o /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiSpike.build/madi-spike.xcent.der --raw
CodeSign /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/madi-spike (in target 'MadiSpike' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --entitlements /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/MadiSpike.build/madi-spike.xcent --timestamp\=none --generate-entitlement-der /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/madi-spike
/Users/kimeunjoong/orca/madi/build/Build/Products/Debug/madi-spike: replacing existing signature
PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules
PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/SDKExplicitPrecompiledModules
PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/ExplicitPrecompiledModules
2026-09-25 23:00:02.001 xcodebuild[28897:103024908]  DVTAssertions: Warning in IDEFrameworks/IDEFoundation/Execution/LaunchSystem/IDELaunchSession.m:395
Details:  setRunnablePIDWithDiagnostics:logSection:andCompletionHandler: called without a completion handler - blocking until diagnostics setup completes. Callers should migrate to using a completion handler for better performance.
Object:   <IDELaunchSession: 0x760d6d1680>
Method:   -setRunnablePIDWithDiagnostics:logSection:andCompletionHandler:
Thread:   <NSThread: 0x76107ef3c0>{number = 6, name = (null)}
Please file a bug at https://feedbackassistant.apple.com with this warning message and any useful information you can provide.
Test Suite 'All tests' started at 2026-09-25 23:00:02.195.
Test Suite 'All tests' passed at 2026-09-25 23:00:02.195.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
􀟈 Test run started.
􀄵 Testing Library Version: 2084
􀄵 Target Platform: arm64e-apple-macos14.0
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
􁁛 Suite CompositionTests passed after 0.012 seconds.
􀟈 Suite ReframeLimitsTests started.
􀟈 Test "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
􀟈 Test case passing 2 arguments source → (2160.0, 3840.0), expected → 2160.0 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􀟈 Test case passing 2 arguments source → (1080.0, 1920.0), expected → 1080.0 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􀟈 Test case passing 2 arguments source → (3840.0, 2160.0), expected → 1215.0 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􀟈 Test case passing 2 arguments source → (1920.0, 1080.0), expected → 607.5 to "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" started.
​􁁛 Test "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다" with 4 test cases passed after 0.001 seconds.
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
2026-09-25 23:00:02.216767+0900 xctest[28970:103025141] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "스타일이 상한을 정한다 — 코드에 박혀 있지 않다" passed after 0.001 seconds.
􁁛 Suite ReframeLimitsTests passed after 0.005 seconds.
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
2026-09-25 23:00:02.223732+0900 xctest[28970:103025144] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "auto 장면은 keyframes 로 바뀌고 JSON 왕복을 견딘다" passed after 0.001 seconds.
􀟈 Test "키프레임 시각은 장면 로컬 출력 초다 — 배속을 반영한다" started.
􁁛 Test "키프레임 시각은 장면 로컬 출력 초다 — 배속을 반영한다" passed after 0.001 seconds.
􁁛 Suite ReframePlannerTests passed after 0.007 seconds.
􀟈 Suite StyleTests started.
􀟈 Test "기본 스타일이 번들에서 읽히고 검증을 통과한다" started.
2026-09-25 23:00:02.224916+0900 xctest[28970:103025144] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "기본 스타일이 번들에서 읽히고 검증을 통과한다" passed after 0.001 seconds.
􀟈 Test "범위를 벗어난 값은 거절한다" started.
2026-09-25 23:00:02.225321+0900 xctest[28970:103025144] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "범위를 벗어난 값은 거절한다" passed after 0.001 seconds.
􀟈 Test "보조 문구가 화면 밖으로 나가면 거절한다" started.
2026-09-25 23:00:02.225807+0900 xctest[28970:103025144] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "보조 문구가 화면 밖으로 나가면 거절한다" passed after 0.001 seconds.
􀟈 Test "보조 문구는 본문이 움직이면 같이 움직인다" started.
2026-09-25 23:00:02.227316+0900 xctest[28970:103025144] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "보조 문구는 본문이 움직이면 같이 움직인다" passed after 0.015 seconds.
􀟈 Test "색은 #RRGGBB 와 #RRGGBBAA 를 읽는다" started.
􁁛 Test "색은 #RRGGBB 와 #RRGGBBAA 를 읽는다" passed after 0.001 seconds.
􁁛 Suite StyleTests passed after 0.018 seconds.
􀟈 Suite CaptionGeometryTests started.
􀟈 Test "그려진 글자 높이가 스타일이 요구한 비율과 맞는다" started.
2026-09-25 23:00:02.243431+0900 xctest[28970:103025138] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "그려진 글자 높이가 스타일이 요구한 비율과 맞는다" passed after 0.194 seconds.
􀟈 Test "글자 아래끝이 스타일이 요구한 위치에 온다" started.
2026-09-25 23:00:02.438042+0900 xctest[28970:103025143] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "글자 아래끝이 스타일이 요구한 위치에 온다" passed after 0.184 seconds.
􀟈 Test "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
􀟈 Test case passing 1 argument slot → .upperBody to "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
2026-09-25 23:00:02.622491+0900 xctest[28970:103025145] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
​􀟈 Test case passing 1 argument slot → .fullBody to "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
2026-09-25 23:00:02.805874+0900 xctest[28970:103025141] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
​􀟈 Test case passing 1 argument slot → .lowerBody to "슬롯마다 자막이 스타일이 정한 높이에 온다" started.
2026-09-25 23:00:02.987484+0900 xctest[28970:103025138] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
​􁁛 Test "슬롯마다 자막이 스타일이 정한 높이에 온다" with 3 test cases passed after 0.547 seconds.
􀟈 Test "슬롯이 바뀌면 보조 문구도 본문을 따라 같이 움직인다" started.
2026-09-25 23:00:03.169655+0900 xctest[28970:103025139] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "슬롯이 바뀌면 보조 문구도 본문을 따라 같이 움직인다" passed after 0.001 seconds.
􀟈 Test "자막 길이가 달라도 글자 크기는 고정이다" started.
2026-09-25 23:00:03.170409+0900 xctest[28970:103025139] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "자막 길이가 달라도 글자 크기는 고정이다" passed after 0.530 seconds.
􀟈 Test "폰트 크기는 스타일 값이 아니라 글자 높이에서 역산된다" started.
2026-09-25 23:00:03.701308+0900 xctest[28970:103025143] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "폰트 크기는 스타일 값이 아니라 글자 높이에서 역산된다" passed after 0.001 seconds.
􀟈 Test "어절 단위로만 줄을 바꾼다" started.
2026-09-25 23:00:03.701825+0900 xctest[28970:103025139] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "어절 단위로만 줄을 바꾼다" passed after 0.004 seconds.
􀟈 Test "Pretendard 가 등록되고 wght 축이 실제로 먹는다" started.
􁁛 Test "Pretendard 가 등록되고 wght 축이 실제로 먹는다" passed after 0.002 seconds.
􁁛 Suite CaptionGeometryTests passed after 1.466 seconds.
􁁛 Test run with 58 tests in 5 suites passed after 1.510 seconds.
2026-09-25 23:00:03.987 xcodebuild[28897:103024848] [MT] IDETestOperationsObserverDebug: 2.027 elapsed -- Testing started completed.
2026-09-25 23:00:03.987 xcodebuild[28897:103024848] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-09-25 23:00:03.987 xcodebuild[28897:103024848] [MT] IDETestOperationsObserverDebug: 2.027 sec, +2.027 sec -- end
Test session results, code coverage, and logs:
	/Users/kimeunjoong/orca/madi/build/Logs/Test/Test-Madi-2026.09.25_23-00-01-+0900.xcresult
** TEST SUCCEEDED **
Testing started
```
