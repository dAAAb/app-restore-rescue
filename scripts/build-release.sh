#!/bin/bash
set -euo pipefail

# Developer/CI build script. The distributed app never runs this script.
# Use only on a Mac with an already-installed Swift/Xcode toolchain.
version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'Usage: bash scripts/build-release.sh MAJOR.MINOR.PATCH' >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'A macOS build host with an existing Swift toolchain is required.' >&2
  exit 2
fi
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
python3 scripts/privacy_audit.py

for architecture in arm64 x86_64; do
  swift build --configuration release --arch "$architecture" \
    -Xswiftc -debug-prefix-map -Xswiftc "$project_root=."
done
arm_binary="$(swift build --configuration release --arch arm64 --show-bin-path)/AppRestoreRescue"
intel_binary="$(swift build --configuration release --arch x86_64 --show-bin-path)/AppRestoreRescue"
stage="$project_root/.build/release-package"
output="$project_root/dist"
if [[ -e "$stage" ]]; then
  rm -rf "$stage"
fi
mkdir -p "$stage/AppRestoreRescue.app/Contents/MacOS" "$stage/AppRestoreRescue.app/Contents/Resources" "$output"
app="$stage/AppRestoreRescue.app"
/usr/bin/lipo -create "$arm_binary" "$intel_binary" -output "$app/Contents/MacOS/AppRestoreRescue"
/usr/bin/strip -S "$app/Contents/MacOS/AppRestoreRescue"
chmod 755 "$app/Contents/MacOS/AppRestoreRescue"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>AppRestoreRescue</string>
<key>CFBundleIdentifier</key><string>com.daaab.AppRestoreRescue</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>App Restore Rescue</string>
<key>CFBundleDisplayName</key><string>App Restore Rescue</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
printf 'APPL????' > "$app/Contents/PkgInfo"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$project_root/.build/AppIcon.iconset"
/usr/bin/iconutil --convert icns "$project_root/.build/AppIcon.iconset" --output "$app/Contents/Resources/AppIcon.icns"
# Ad-hoc signature provides bundle integrity only; it is not a Developer ID identity.
/usr/bin/codesign --force --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$app"
/usr/bin/lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/AppRestoreRescue"

cp README.md README.zh-TW.md LICENSE PRIVACY.md "$stage/"
commit="${GITHUB_SHA:-local-build}"
if [[ "$commit" != local-build && ! "$commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
  printf '%s\n' 'Unexpected source revision format.' >&2
  exit 2
fi
cat > "$stage/BUILD-INFO.txt" <<INFO
App Restore Rescue $version
Source: https://github.com/dAAAb/app-restore-rescue
Revision: $commit
Architectures: arm64, x86_64
Minimum macOS: 13.0
Signature: ad-hoc; not Developer ID signed and not notarized
External dependency: ideviceinstaller 1.2 or newer (not bundled)
INFO
filename="AppRestoreRescue-v${version}-macOS-universal.zip"
python3 scripts/package_zip.py "$stage" "$output/$filename"
(
  cd "$output"
  /usr/bin/shasum -a 256 "$filename" > SHA256SUMS.txt
)
printf 'Built dist/%s and dist/SHA256SUMS.txt\n' "$filename"
