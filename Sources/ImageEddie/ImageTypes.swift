import AppKit
import UniformTypeIdentifiers

enum EditorTool: String, CaseIterable, Identifiable {
    case text = "Text", image = "Image", crop = "Crop", resize = "Resize", color = "Color"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .text: "textformat"
        case .image: "photo.on.rectangle"
        case .crop: "crop"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .color: "slider.horizontal.3"
        }
    }
}

enum ColorPreset: String, CaseIterable, Identifiable {
    case original = "Original", mono = "B&W", noir = "Noir", warm = "Warm", cool = "Cool", sepia = "Sepia"
    var id: String { rawValue }
}

enum CropRatio: String, CaseIterable, Identifiable {
    case free = "Free", square = "1:1", original = "Original", photo = "4:3", wide = "16:9"
    var id: String { rawValue }
    func value(original: CGFloat) -> CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .original: original
        case .photo: 4 / 3
        case .wide: 16 / 9
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG", svg = "SVG"
    var id: String { rawValue }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .svg: .svg
        }
    }
}

struct ExportSettings {
    var format: ExportFormat = .png
    var quality: Double = 0.9
    var background: String = "FFFFFF"
}

struct TextLayer: Equatable, Identifiable {
    var id = UUID()
    var text = "Your text"
    var x: CGFloat
    var y: CGFloat
    var fontSize: CGFloat
    var fontName = "System"
    var bold = true
    var whiteBox = true
    var color = "243D35"

    var font: NSFont {
        if fontName == "System" { return NSFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular) }
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        return bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
    }

    var lines: [String] { text.components(separatedBy: "\n") }
    var padding: CGFloat { whiteBox ? fontSize * 0.32 : 0 }
    var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }
    var rect: CGRect {
        let width = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return CGRect(x: x, y: y, width: max(width, fontSize * 0.3) + padding * 2,
                      height: CGFloat(lines.count) * lineHeight + padding * 2)
    }
}

struct ImageLayer: Equatable, Identifiable {
    let id: UUID
    let asset: ImageAsset
    var rect: CGRect
    var opacity: Double = 1

    init(asset: ImageAsset, rect: CGRect, opacity: Double = 1) {
        self.id = UUID()
        self.asset = asset
        self.rect = rect
        self.opacity = opacity
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.asset.image === rhs.asset.image && lhs.rect == rhs.rect && lhs.opacity == rhs.opacity
    }
}

struct EditState: Equatable {
    var crop: CGRect
    var width: Int
    var height: Int
    var preset: ColorPreset = .original
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var texts: [TextLayer] = []
    var images: [ImageLayer] = []
}

struct ImageAsset {
    let image: CGImage
    let name: String
    let fileURL: URL?
    let svg: String?
    let width: Int
    let height: Int
    let format: String
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    static func load(_ url: URL) throws -> ImageAsset {
        let data = try Data(contentsOf: url)
        guard data.count <= 150_000_000 else { throw ImageError.message("This file is too large. Choose an image under 150 MB.") }
        let isSVG = url.pathExtension.lowercased() == "svg"
        if isSVG {
            let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
            guard let root = document.rootElement(), root.localName == "svg" else {
                throw ImageError.message("This file doesn’t contain a valid SVG image.")
            }
            guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
                  image.size.width.isFinite, image.size.height.isFinite else { throw ImageError.cannotRead }
            let width = max(1, Int(image.size.width.rounded()))
            let height = max(1, Int(image.size.height.rounded()))
            try validateDimensions(width, height)
            // Keep vector geometry for export; the raster is only a working preview.
            if root.attribute(forName: "viewBox") == nil {
                root.addAttribute(XMLNode.attribute(withName: "viewBox", stringValue: "0 0 \(width) \(height)") as! XMLNode)
            }
            for (key, value) in [("width", String(width)), ("height", String(height)), ("x", "0"), ("y", "0")] {
                root.removeAttribute(forName: key)
                root.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
            }
            let previewScale = min(1, 4096 / CGFloat(max(width, height)))
            let bitmap = try rasterize(image, width: max(1, Int(CGFloat(width) * previewScale)), height: max(1, Int(CGFloat(height) * previewScale)))
            return ImageAsset(image: bitmap, name: url.lastPathComponent, fileURL: url,
                              svg: root.xmlString, width: width, height: height, format: "SVG")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              let type = UTType(sourceType as String), type.conforms(to: .png) || type.conforms(to: .jpeg) else {
            throw ImageError.message("Choose a PNG, JPEG, or SVG image.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        try validateDimensions(width, height)
        // ImageIO applies EXIF orientation so phone photos open the right way up.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ImageError.cannotRead }
        return ImageAsset(image: image, name: url.lastPathComponent, fileURL: url, svg: nil,
                          width: image.width, height: image.height, format: type.conforms(to: .png) ? "PNG" : "JPEG")
    }

    static func validateDimensions(_ width: Int, _ height: Int) throws {
        guard width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 64_000_000 else {
            throw ImageError.message("Use dimensions between 1 and 16,384 pixels, with at most 64 million pixels in total.")
        }
    }

    private static func rasterize(_ image: NSImage, width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImageError.cannotRender }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage() else { throw ImageError.cannotRender }
        return result
    }
}

enum ImageError: LocalizedError {
    case cannotRead, cannotRender, cannotExport, message(String)
    var errorDescription: String? {
        switch self {
        case .cannotRead: "This image couldn’t be opened. Try another PNG, JPEG, or SVG file."
        case .cannotRender: "The image couldn’t be rendered. Try a smaller image."
        case .cannotExport: "The image couldn’t be exported. Try a different format or smaller size."
        case .message(let message): message
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x243D35
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var hex: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

extension CGImage {
    /// Sample in an explicit sRGB context. NSBitmapImageRep.colorAt can return a
    /// calibrated color without retaining the CGImage's ICC color space.
    func sRGBColorAt(x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < width, y < height,
              let pixel = cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let divisor = max(1, CGFloat(bytes[3]))
        return NSColor(srgbRed: CGFloat(bytes[0]) / divisor, green: CGFloat(bytes[1]) / divisor,
                       blue: CGFloat(bytes[2]) / divisor, alpha: CGFloat(bytes[3]) / 255)
    }
}
