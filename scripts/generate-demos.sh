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
    Sources/ImageEddie/ImageTypes.swift Sources/ImageEddie/ImageRenderer.swift \
    Sources/ImageEddie/SVGColors.swift Sources/ImageEddie/EditorModel.swift \
    Sources/ImageEddie/Theme.swift Sources/ImageEddie/CanvasView.swift \
    Sources/ImageEddie/ImageOverlayViews.swift Sources/ImageEddie/InspectorView.swift \
    Sources/ImageEddie/ExportView.swift Sources/ImageEddie/EditorView.swift \
    Sources/ImageEddie/WindowSetup.swift scripts/capture-demos.swift \
    -o build/CaptureDemos
build/CaptureDemos
for demo in text overlays crop-color export; do
    ffmpeg -hide_banner -loglevel warning -y \
        -f concat -safe 0 -i "build/docs-capture/$demo.ffconcat" \
        -filter_complex 'fps=10,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' \
        -loop 0 "docs/media/$demo.gif"
done
print "Updated README GIFs in docs/media/"
