#!/bin/bash
# Universal 2 앱 만들기 (AGENTS.md §3 · §17, docs/stage-3.spec.md 결정 ③ A).
#
# 한 번에 `ARCHS="arm64 x86_64"` 로 빌드하면 WhisperKit 이 x86_64 모듈을 내놓지 못해 깨진다
# (docs/findings/2026-09-26-whisperkit.md §2). 아키텍처마다 **따로** 빌드하면 둘 다 된다.
# 그래서 따로 빌드해 앱 안의 Mach-O 를 하나씩 `lipo` 로 합친다. `.dmg` 는 하나다 — 크리에이터가 기종을 고르지 않는다 (§1-9).
#
#   scripts/build-universal.sh [출력 디렉토리]     기본 out/universal
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/out/universal}"
WORK="$OUT/work"
rm -rf "$OUT"; mkdir -p "$WORK"

for arch in arm64 x86_64; do
  echo "== $arch 빌드"
  xcodebuild -project "$ROOT/Madi.xcodeproj" -scheme Madi -configuration Release \
    -derivedDataPath "$WORK/$arch" ARCHS="$arch" ONLY_ACTIVE_ARCH=NO build -quiet
done

A="$WORK/arm64/Build/Products/Release/Madi.app"
X="$WORK/x86_64/Build/Products/Release/Madi.app"
U="$OUT/Madi.app"
cp -R "$A" "$U"

# 앱 안의 Mach-O 전부를 합친다 (실행 파일 · 프레임워크 · dylib). 한쪽에만 있으면 멈춘다.
merged=0
while IFS= read -r -d '' f; do
  rel="${f#$A/}"
  if file -b "$f" | grep -q "Mach-O"; then
    [ -f "$X/$rel" ] || { echo "x86_64 빌드에 없다: $rel" >&2; exit 1; }
    lipo -create "$f" "$X/$rel" -output "$U/$rel"
    merged=$((merged + 1))
  fi
done < <(find "$A" -type f -print0)

# 확인 — 합친 Mach-O 가 전부 두 아키텍처를 갖는가.
bad=0
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q "Mach-O"; then
    archs=$(lipo -archs "$f")
    [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "한쪽뿐: ${f#$U/} ($archs)" >&2; bad=1; }
  fi
done < <(find "$U" -type f -print0)
[ "$bad" -eq 0 ] || exit 1

# lipo 로 바꾼 파일은 서명이 깨진다 — 임시 서명을 다시 건다 (공증은 판매 시점, §2 배포).
codesign --force --deep --sign - "$U"
echo "== Mach-O $merged 개 합침 · $(lipo -archs "$U/Contents/MacOS/Madi") · $U"
