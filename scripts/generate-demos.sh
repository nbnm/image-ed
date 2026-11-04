#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
if ! command -v ffmpeg >/dev/null; then
    print -u2 "FFmpeg is required to generate the README GIFs."
    exit 1
fi
mkdir -p build/docs-capture docs/media
swiftc -swift-version 5 -parse-as-library \
    Sources/Still/ImageTypes.swift Sources/Still/ImageRenderer.swift \
    Sources/Still/SVGColors.swift Sources/Still/EditorModel.swift \
    Sources/Still/Theme.swift Sources/Still/CanvasView.swift \
    Sources/Still/ImageOverlayViews.swift Sources/Still/InspectorView.swift \
    Sources/Still/ExportView.swift Sources/Still/EditorView.swift \
    Sources/Still/WindowSetup.swift scripts/capture-demos.swift \
    -o build/CaptureDemos
build/CaptureDemos
for demo in text overlays crop-color export; do
    ffmpeg -hide_banner -loglevel warning -y \
        -f concat -safe 0 -i "build/docs-capture/$demo.ffconcat" \
        -filter_complex 'fps=10,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' \
        -loop 0 "docs/media/$demo.gif"
done
print "Updated README GIFs in docs/media/"
