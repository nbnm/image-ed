#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build
swiftc -swift-version 5 -parse-as-library \
    Sources/Still/ImageTypes.swift \
    Sources/Still/ImageRenderer.swift \
    Sources/Still/SVGColors.swift \
    Sources/Still/EditorModel.swift \
    Tests/StillTests/ImageEngineTests.swift \
    -o build/StillChecks
build/StillChecks
