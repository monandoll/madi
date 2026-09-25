# xcodebuild test 전체 로그

실행: 2026-09-25 13:58
머신: macOS 27.0 · arm64 · Apple M1 Max
Xcode: Xcode 27.0
Swift: swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)

```
$ xcodebuild -project Madi.xcodeproj -scheme Madi -configuration Debug test
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --entitlements /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/Madi.build/Debug/Madi.build/Madi.app.xcent --timestamp\=none --generate-entitlement-der /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app

Validate /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-validationUtility /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app -no-validate-extension -infoplist-subpath Contents/Info.plist

RegisterWithLaunchServices /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app (in target 'Madi' from project 'Madi')
    cd /Users/kimeunjoong/orca/madi
    builtin-lsregisterurl --record-path /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/XCBuildData/registered-launchservices.txt -- /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Users/kimeunjoong/orca/madi/build/Build/Products/Debug/Madi.app

PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/SDKExplicitPrecompiledModules

PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules

PruneExplicitPrecompiledModules /Users/kimeunjoong/orca/madi/build/Build/Intermediates.noindex/ExplicitPrecompiledModules

2026-09-25 13:58:38.254 xcodebuild[89986:97637715]  DVTAssertions: Warning in IDEFrameworks/IDEFoundation/Execution/LaunchSystem/IDELaunchSession.m:395
Details:  setRunnablePIDWithDiagnostics:logSection:andCompletionHandler: called without a completion handler - blocking until diagnostics setup completes. Callers should migrate to using a completion handler for better performance.
Object:   <IDELaunchSession: 0x74936e9980>
Method:   -setRunnablePIDWithDiagnostics:logSection:andCompletionHandler:
Thread:   <NSThread: 0x749662d800>{number = 16, name = (null)}
Please file a bug at https://feedbackassistant.apple.com with this warning message and any useful information you can provide.
Test Suite 'All tests' started at 2026-09-25 13:58:39.554.
Test Suite 'All tests' passed at 2026-09-25 13:58:39.554.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
􀟈 Test run started.
􀄵 Testing Library Version: 2084
􀄵 Target Platform: arm64e-apple-macos14.0
􀟈 Suite CompositionTests started.
􀟈 Test "최소 JSON 이 기본값과 함께 파싱된다" started.
􁁛 Test "최소 JSON 이 기본값과 함께 파싱된다" passed after 0.001 seconds.
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
􁁛 Test "강조 구간이 텍스트 밖이면 거절한다" passed after 0.003 seconds.
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
􁁛 Suite CompositionTests passed after 0.010 seconds.
􀟈 Suite StyleTests started.
􀟈 Test "기본 스타일이 번들에서 읽히고 검증을 통과한다" started.
2026-09-25 13:58:39.570456+0900 xctest[90244:97638772] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "기본 스타일이 번들에서 읽히고 검증을 통과한다" passed after 0.001 seconds.
􀟈 Test "범위를 벗어난 값은 거절한다" started.
2026-09-25 13:58:39.570918+0900 xctest[90244:97638772] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "범위를 벗어난 값은 거절한다" passed after 0.001 seconds.
􀟈 Test "보조 문구가 본문보다 위로 올라가면 거절한다" started.
2026-09-25 13:58:39.571362+0900 xctest[90244:97638772] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "보조 문구가 본문보다 위로 올라가면 거절한다" passed after 0.001 seconds.
􀟈 Test "색은 #RRGGBB 와 #RRGGBBAA 를 읽는다" started.
􁁛 Test "색은 #RRGGBB 와 #RRGGBBAA 를 읽는다" passed after 0.001 seconds.
􁁛 Suite StyleTests passed after 0.006 seconds.
􀟈 Suite CaptionGeometryTests started.
􀟈 Test "그려진 글자 높이가 스타일이 요구한 비율과 맞는다" started.
2026-09-25 13:58:39.572951+0900 xctest[90244:97638772] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "그려진 글자 높이가 스타일이 요구한 비율과 맞는다" passed after 0.200 seconds.
􀟈 Test "글자 아래끝이 스타일이 요구한 위치에 온다" started.
2026-09-25 13:58:39.773201+0900 xctest[90244:97638783] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "글자 아래끝이 스타일이 요구한 위치에 온다" passed after 0.184 seconds.
􀟈 Test "자막 길이가 달라도 글자 크기는 고정이다" started.
2026-09-25 13:58:39.958252+0900 xctest[90244:97638781] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "자막 길이가 달라도 글자 크기는 고정이다" passed after 0.537 seconds.
􀟈 Test "폰트 크기는 스타일 값이 아니라 글자 높이에서 역산된다" started.
2026-09-25 13:58:40.496403+0900 xctest[90244:97638783] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "폰트 크기는 스타일 값이 아니라 글자 높이에서 역산된다" passed after 0.002 seconds.
􀟈 Test "어절 단위로만 줄을 바꾼다" started.
2026-09-25 13:58:40.498395+0900 xctest[90244:97638677] [style] 스타일 short.v1 은 아직 확정값이 아닙니다. 공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
􁁛 Test "어절 단위로만 줄을 바꾼다" passed after 0.001 seconds.
􀟈 Test "Pretendard 가 등록되고 wght 축이 실제로 먹는다" started.
􁁛 Test "Pretendard 가 등록되고 wght 축이 실제로 먹는다" passed after 0.003 seconds.
􁁛 Suite CaptionGeometryTests passed after 0.930 seconds.
􁁛 Test run with 29 tests in 3 suites passed after 0.947 seconds.
2026-09-25 13:58:40.769 xcodebuild[89986:97637602] [MT] IDETestOperationsObserverDebug: 2.551 elapsed -- Testing started completed.
2026-09-25 13:58:40.769 xcodebuild[89986:97637602] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-09-25 13:58:40.769 xcodebuild[89986:97637602] [MT] IDETestOperationsObserverDebug: 2.551 sec, +2.551 sec -- end

Test session results, code coverage, and logs:
	/Users/kimeunjoong/orca/madi/build/Logs/Test/Test-Madi-2026.09.25_13-58-33-+0900.xcresult

** TEST SUCCEEDED **

Testing started
```
