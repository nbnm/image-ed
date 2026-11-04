#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
configuration=release
if [[ "${1:-}" == "--debug" ]]; then configuration=debug; fi
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
application_directory="$project_root/build/Still.app"
mkdir -p "$application_directory/Contents/MacOS" "$application_directory/Contents/Resources"
cp "$binary_directory/Still" "$application_directory/Contents/MacOS/Still"
cp Resources/Info.plist "$application_directory/Contents/Info.plist"
cp Resources/Sample.svg "$application_directory/Contents/Resources/Sample.svg"
cp Resources/Brand/EddieCharacter.png "$application_directory/Contents/Resources/EddieCharacter.png"
if [[ ! -f build/StillEddie.icns || Resources/Brand/EddieIconMaster.png -nt build/StillEddie.icns || scripts/make-icon.swift -nt build/StillEddie.icns ]]; then
    swift scripts/make-icon.swift "$project_root/build"
    iconutil --convert icns build/StillEddie.iconset --output build/StillEddie.icns
fi
cp build/StillEddie.icns "$application_directory/Contents/Resources/StillEddie.icns"
codesign --force --deep --sign - "$application_directory"
print "Built: $application_directory"
print "Launch: open '$application_directory'"
