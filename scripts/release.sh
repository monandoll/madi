#!/bin/bash
# 배포용 .dmg 만들기 — 서명 · 공증 · 스테이플 (AGENTS.md §2 배포, docs/stage-6.spec.md 3번).
#
#   scripts/release.sh [--no-notarize] [--publish]
#
#   --publish  GitHub 릴리스 v<판> 을 만들어 .dmg · appcast.xml 을 올린다 (공개로 나간다 — 확인하고 쓴다)
#
# 1. Universal 앱 (scripts/build-universal.sh — 아키텍처마다 빌드해 lipo)
# 2. Developer ID 로 안쪽부터 서명 — 프레임워크 · dylib · madi-mcp → 앱. Hardened Runtime + 타임스탬프
# 3. .dmg (앱 + /Applications 바로가기) → 서명
# 4. 공증(notarytool) → 스테이플 → Gatekeeper 확인
#
# 공증 자격 증명은 키체인 프로필 `madi-notary` 에 한 번 저장해 둔다 (사람이 한다 — Apple ID · 앱 전용 암호):
#   xcrun notarytool store-credentials madi-notary --apple-id <Apple ID> --team-id 64YK8W88M5
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/release"
IDENTITY="${MADI_SIGN_IDENTITY:-Developer ID Application: eunjoong kim (64YK8W88M5)}"
PROFILE="${MADI_NOTARY_PROFILE:-madi-notary}"
ENTITLEMENTS="$ROOT/Madi/App/Madi.entitlements"
# Sparkle 도구(generate_appcast)가 있는 곳 — Sparkle 배포본(2.10.0)의 bin/. 앱에는 들어가지 않는 개발 도구다.
SPARKLE_BIN="${MADI_SPARKLE_BIN:-}"
# 업데이트 전용 공개 레포 — 소스 레포에는 전작 v0.2 릴리스가 Latest 로 있다
REPO="monandoll/madi-releases"
NOTARIZE=1
PUBLISH=0
for a in "$@"; do
  case "$a" in
    --no-notarize) NOTARIZE=0 ;;
    --publish) PUBLISH=1 ;;
  esac
done
[[ $PUBLISH -eq 1 && $NOTARIZE -eq 0 ]] && { echo "공증하지 않은 판은 올리지 않는다" >&2; exit 1; }

"$ROOT/scripts/build-universal.sh" "$OUT"
APP="$OUT/Madi.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "== Madi $VERSION ($BUILD)"

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# 안쪽부터. --deep 은 쓰지 않는다 — 안쪽 코드마다 옵션(엔타이틀먼트)이 다르다.
echo "== 서명"
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q "Mach-O" && sign "$f"
done < <(find "$APP/Contents/Frameworks" -type f -print0)
# 번들 안의 번들(Sparkle 의 XPC 서비스 · Updater.app)은 파일 다음, 프레임워크 앞에 — 깊은 것부터.
while IFS= read -r b; do
  sign --preserve-metadata=entitlements "$b"
done < <(find "$APP/Contents/Frameworks" \( -name "*.xpc" -o -name "*.app" \) -type d | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
for fw in "$APP"/Contents/Frameworks/*.framework; do sign "$fw"; done
sign "$APP/Contents/MacOS/madi-mcp"
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== .dmg"
DMG="$OUT/Madi-$VERSION.dmg"
STAGE="$OUT/dmg"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "마디" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
rm -rf "$STAGE"
sign "$DMG"

if [[ $NOTARIZE -eq 1 ]]; then
  echo "== 공증 (몇 분 걸린다)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vvv -t open --context context:primary-signature "$DMG"
fi
# Sparkle 새 판 목록. 판마다 .dmg 에 EdDSA 서명을 붙인다 (비밀 키는 키체인 계정 madi).
if [[ $NOTARIZE -eq 1 && -n "$SPARKLE_BIN" ]]; then
  echo "== appcast"
  UPDATES="$OUT/updates"
  rm -rf "$UPDATES"; mkdir -p "$UPDATES"
  cp "$DMG" "$UPDATES/"
  "$SPARKLE_BIN/generate_appcast" --account madi \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" "$UPDATES"
  grep -q "sparkle:edSignature" "$UPDATES/appcast.xml" || { echo "appcast 에 서명이 없다" >&2; exit 1; }
fi

if [[ $PUBLISH -eq 1 ]]; then
  [[ -f "$OUT/updates/appcast.xml" ]] || { echo "appcast 가 없다 — MADI_SPARKLE_BIN 을 준다" >&2; exit 1; }
  echo "== GitHub 릴리스 v$VERSION"
  gh release create "v$VERSION" "$DMG" "$OUT/updates/appcast.xml" -R "$REPO" \
    --title "마디 $VERSION" --notes "마디 $VERSION ($BUILD)"
fi
echo "== $DMG"
