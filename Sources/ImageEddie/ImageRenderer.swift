import AppKit
import CoreImage
import ImageIO

enum ImageRenderer {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    static func filtered(_ image: CGImage, state: EditState) throws -> CGImage {
        var input = CIImage(cgImage: image)
        var saturation = state.saturation
        var contrast = state.contrast
        if state.preset == .mono || state.preset == .noir { saturation = 0 }
        if state.preset == .noir { contrast *= 1.35 }
        input = input.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation, kCIInputBrightnessKey: state.brightness,
            kCIInputContrastKey: contrast
        ])
        switch state.preset {
        case .warm:
            input = input.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.06, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.01, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.90, w: 0)
            ])
        case .cool:
            input = input.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.90, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.02, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.08, w: 0)
            ])
        case .sepia: input = input.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.8])
        default: break
        }
        guard let output = context.createCGImage(input, from: input.extent) else { throw ImageError.cannotRender }
        return output
    }

    static func render(asset: ImageAsset, state: EditState, maxDimension: Int? = nil,
                       background: String? = nil, filteredImage: CGImage? = nil) throws -> CGImage {
        var width = state.width, height = state.height
        if let maxDimension {
            let scale = min(1, Double(maxDimension) / Double(max(width, height)))
            width = max(1, Int(Double(width) * scale))
            height = max(1, Int(Double(height) * scale))
        }
        try ImageAsset.validateDimensions(width, height)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImageError.cannotRender }
        if let background {
            ctx.setFillColor(NSColor(hex: background).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.interpolationQuality = .high
        if let svg = asset.svg, maxDimension == nil {
            // Draw the vector at the final size before filtering. CoreSVG ignores SVG
            // filter elements, so applying them inside SVG would silently lose the edit.
            guard let vector = NSImage(data: Data(svg.utf8)),
                  let vectorContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImageError.cannotRender }
            transform(vectorContext, asset: asset, state: state, width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: vectorContext, flipped: false)
            vector.draw(in: asset.bounds, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            guard let raster = vectorContext.makeImage() else { throw ImageError.cannotRender }
            ctx.draw(try filtered(raster, state: state), in: CGRect(x: 0, y: 0, width: width, height: height))
            transform(ctx, asset: asset, state: state, width: width, height: height)
        } else {
            transform(ctx, asset: asset, state: state, width: width, height: height)
            ctx.draw(try filteredImage ?? filtered(asset.image, state: state), in: asset.bounds)
        }
        drawImages(state.images, sourceHeight: CGFloat(asset.height), in: ctx)
        drawText(state.texts, sourceHeight: CGFloat(asset.height), in: ctx)
        guard let result = ctx.makeImage() else { throw ImageError.cannotRender }
        return result
    }

    private static func transform(_ context: CGContext, asset: ImageAsset, state: EditState, width: Int, height: Int) {
        context.scaleBy(x: CGFloat(width) / state.crop.width, y: CGFloat(height) / state.crop.height)
        context.translateBy(x: -state.crop.minX, y: -(CGFloat(asset.height) - state.crop.maxY))
    }

    private static func drawText(_ layers: [TextLayer], sourceHeight: CGFloat, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for layer in layers {
            let rect = layer.rect
            if layer.whiteBox {
                NSColor.white.setFill()
                NSBezierPath(rect: CGRect(x: rect.minX, y: sourceHeight - rect.maxY,
                                         width: rect.width, height: rect.height)).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: layer.font, .foregroundColor: NSColor(hex: layer.color)]
            for (index, line) in layer.lines.enumerated() {
                let baseline = sourceHeight - layer.y - layer.padding - layer.font.ascender - CGFloat(index) * layer.lineHeight
                let attributed = NSAttributedString(string: line, attributes: attributes)
                let textLine = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: layer.x + layer.padding, y: baseline)
                CTLineDraw(textLine, context)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawImages(_ layers: [ImageLayer], sourceHeight: CGFloat, in context: CGContext) {
        for layer in layers {
            let rect = CGRect(x: layer.rect.minX, y: sourceHeight - layer.rect.maxY,
                              width: layer.rect.width, height: layer.rect.height)
            context.saveGState()
            if let svg = layer.asset.svg, let vector = NSImage(data: Data(svg.utf8)) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                vector.draw(in: rect, from: .zero, operation: .sourceOver, fraction: layer.opacity,
                            respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
                NSGraphicsContext.restoreGraphicsState()
            } else {
                context.setAlpha(layer.opacity)
                context.draw(layer.asset.image, in: rect)
            }
            context.restoreGState()
        }
    }

    static func export(asset: ImageAsset, state: EditState, settings: ExportSettings) throws -> Data {
        if settings.format == .svg { return try svgData(asset: asset, state: state) }
        let image = try render(asset: asset, state: state, background: settings.format == .jpeg ? settings.background : nil)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, settings.format.contentType.identifier as CFString, 1, nil) else {
            throw ImageError.cannotExport
        }
        let properties: [CFString: Any] = settings.format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: settings.quality] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.cannotExport }
        return data as Data
    }

    static func svgData(asset: ImageAsset, state: EditState) throws -> Data {
        let source: String
        if let svg = asset.svg {
            source = try SVGColors.recolor(svg, state: state)
        } else {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw ImageError.cannotExport }
            CGImageDestinationAddImage(destination, try filtered(asset.image, state: state), nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageError.cannotExport }
            source = "<image width=\"\(asset.width)\" height=\"\(asset.height)\" href=\"data:image/png;base64,\((data as Data).base64EncodedString())\"/>"
        }
        let crop = state.crop
        let images = try state.images.map { layer -> String in
            let source: String
            if let svg = layer.asset.svg {
                // A separate image document keeps SVG IDs and styles from colliding
                // with the main artwork or another copy of the same overlay.
                source = "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
            } else {
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw ImageError.cannotExport }
                CGImageDestinationAddImage(destination, layer.asset.image, nil)
                guard CGImageDestinationFinalize(destination) else { throw ImageError.cannotExport }
                source = "data:image/png;base64," + (data as Data).base64EncodedString()
            }
            return "<image x=\"\(n(layer.rect.minX))\" y=\"\(n(layer.rect.minY))\" width=\"\(n(layer.rect.width))\" height=\"\(n(layer.rect.height))\" opacity=\"\(layer.opacity)\" preserveAspectRatio=\"none\" href=\"\(source)\"/>"
        }.joined(separator: "\n")
        let text = state.texts.map { layer -> String in
            let rect = layer.rect
            let box = layer.whiteBox ? "<rect x=\"\(n(rect.minX))\" y=\"\(n(rect.minY))\" width=\"\(n(rect.width))\" height=\"\(n(rect.height))\" fill=\"white\"/>" : ""
            let spans = layer.lines.enumerated().map { index, line in
                "<tspan x=\"\(n(layer.x + layer.padding))\" y=\"\(n(layer.y + layer.padding + layer.font.ascender + CGFloat(index) * layer.lineHeight))\">\(escape(line))</tspan>"
            }.joined()
            let family = layer.fontName == "System" ? "-apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif" : layer.fontName
            return "\(box)<text font-family=\"\(escape(family))\" font-size=\"\(n(layer.fontSize))\" font-weight=\"\(layer.bold ? 600 : 400)\" fill=\"#\(layer.color)\" xml:space=\"preserve\">\(spans)</text>"
        }.joined(separator: "\n")
        // The outer viewBox performs the crop and resize without flattening vector paths.
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(state.width)" height="\(state.height)" viewBox="\(n(crop.minX)) \(n(crop.minY)) \(n(crop.width)) \(n(crop.height))" preserveAspectRatio="none">
          \(source)
          \(images)
          \(text)
        </svg>
        """
        guard let data = svg.data(using: .utf8) else { throw ImageError.cannotExport }
        return data
    }

    private static func n(_ number: CGFloat) -> String { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(number)) }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
