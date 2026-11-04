#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build
swiftc -swift-version 5 -parse-as-library \
    Sources/ImageEddie/ImageTypes.swift \
    Sources/ImageEddie/ImageRenderer.swift \
    Sources/ImageEddie/SVGColors.swift \
    Sources/ImageEddie/EditorModel.swift \
    Tests/ImageEddieTests/ImageEngineTests.swift \
    -o build/ImageEddieChecks
build/ImageEddieChecks
