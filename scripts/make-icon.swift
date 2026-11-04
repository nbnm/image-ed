import AppKit

// Package the generated square master into macOS's ten standard icon sizes.
// The rounded mask gives every size the same clean alpha edge.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = projectRoot.appendingPathComponent("Resources/Brand/EddieIconMaster.png")
guard let artwork = NSImage(contentsOf: source) else {
    fputs("Missing Eddie icon master: \(source.path)\n", stderr)
    exit(1)
}
let folder = destination.appendingPathComponent("ImageEddie.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fputs("Could not allocate icon bitmap.\n", stderr)
            exit(1)
        }
        let s = CGFloat(pixels)
        let inset = s * 0.045
        let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current?.imageInterpolation = .high
        context.saveGState()
        NSBezierPath(roundedRect: tile, xRadius: s * 0.205, yRadius: s * 0.205).addClip()
        artwork.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fputs("Could not encode icon PNG.\n", stderr)
            exit(1)
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
