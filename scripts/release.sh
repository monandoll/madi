#!/bin/bash
# 배포용 .dmg 만들기 — 서명 · 공증 · 스테이플 (AGENTS.md §2 배포, docs/stage-6.spec.md 3번).
#
#   scripts/release.sh [--no-notarize]
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
NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

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
echo "== $DMG"
