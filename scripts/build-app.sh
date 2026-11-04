#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
configuration=release
if [[ "${1:-}" == "--debug" ]]; then configuration=debug; fi
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
application_directory="$project_root/build/Image-Eddie.app"
mkdir -p "$application_directory/Contents/MacOS" "$application_directory/Contents/Resources"
cp "$binary_directory/Image-Eddie" "$application_directory/Contents/MacOS/Image-Eddie"
cp Resources/Info.plist "$application_directory/Contents/Info.plist"
cp Resources/Sample.svg "$application_directory/Contents/Resources/Sample.svg"
cp Resources/Brand/EddieCharacter.png "$application_directory/Contents/Resources/EddieCharacter.png"
if [[ ! -f build/ImageEddie.icns || Resources/Brand/EddieIconMaster.png -nt build/ImageEddie.icns || scripts/make-icon.swift -nt build/ImageEddie.icns ]]; then
    swift scripts/make-icon.swift "$project_root/build"
    iconutil --convert icns build/ImageEddie.iconset --output build/ImageEddie.icns
fi
cp build/ImageEddie.icns "$application_directory/Contents/Resources/ImageEddie.icns"
codesign --force --deep --sign - "$application_directory"
print "Built: $application_directory"
print "Launch: open '$application_directory'"
