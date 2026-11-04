import AppKit

@MainActor
final class ImageEngineTests {
    private var temporary: URL!
    func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("StillTests-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }

    private func fixture(width: Int = 120, height: Int = 80, transparent: Bool = false) throws -> ImageAsset {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !transparent {
            context.setFillColor(NSColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(NSColor.blue.cgColor)
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        let image = context.makeImage()!
        return ImageAsset(image: image, name: "fixture.png", fileURL: nil, svg: nil, width: width, height: height, format: "PNG")
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try unwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    private func color(_ image: CGImage, _ x: Int, _ y: Int) -> NSColor {
        image.sRGBColorAt(x: x, y: y)!
    }
    private func svgFixture() throws -> ImageAsset {
        let url = temporary.appendingPathComponent("vector.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120\" height=\"80\" viewBox=\"0 0 120 80\"><rect width=\"60\" height=\"80\" fill=\"red\"/><rect x=\"60\" width=\"60\" height=\"80\" fill=\"blue\"/></svg>".write(to: url, atomically: true, encoding: .utf8)
        return try ImageAsset.load(url)
    }

    func testPNGExportPreservesTransparencyAndSize() throws {
        let asset = try fixture(transparent: true)
        let state = EditState(crop: asset.bounds, width: 60, height: 40)
        let data = try ImageRenderer.export(asset: asset, state: state, settings: ExportSettings())
        let image = try decode(data)
        equal(image.width, 60); equal(image.height, 40)
        equal(color(image, 10, 10).alphaComponent, 0, accuracy: 0.01)
        let url = temporary.appendingPathComponent("roundtrip.png")
        try data.write(to: url)
        equal(try ImageAsset.load(url).width, 60)
    }

    func testJPEGUsesChosenBackgroundAndQuality() throws {
        let asset = try fixture(transparent: true)
        let state = EditState(crop: asset.bounds, width: 120, height: 80)
        let settings = ExportSettings(format: .jpeg, quality: 0.8, background: "00FF00")
        let data = try ImageRenderer.export(asset: asset, state: state, settings: settings)
        let pixel = color(try decode(data), 20, 20)
        greater(pixel.greenComponent, 0.95)
        less(pixel.redComponent, 0.05)
        equal(pixel.alphaComponent, 1, accuracy: 0.01)
        let url = temporary.appendingPathComponent("roundtrip.jpg")
        try data.write(to: url)
        equal(try ImageAsset.load(url).format, "JPEG")
    }

    func testCropCoordinatesAndResize() throws {
        let asset = try fixture()
        let state = EditState(crop: CGRect(x: 60, y: 0, width: 60, height: 80), width: 30, height: 40)
        let image = try ImageRenderer.render(asset: asset, state: state)
        equal(image.width, 30); equal(image.height, 40)
        let pixel = color(image, 10, 10)
        greater(pixel.blueComponent, 0.95); less(pixel.redComponent, 0.05)
    }

    func testTopLeftCropAndTextCoordinates() throws {
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        let asset = ImageAsset(image: context.makeImage()!, name: "vertical.png", fileURL: nil, svg: nil, width: 100, height: 100, format: "PNG")
        let state = EditState(crop: CGRect(x: 0, y: 0, width: 100, height: 50), width: 100, height: 50)
        let image = try ImageRenderer.render(asset: asset, state: state)
        greater(color(image, 20, 20).redComponent, 0.95)
        var textState = EditState(crop: asset.bounds, width: 100, height: 100)
        textState.texts = [TextLayer(text: "X", x: 10, y: 10, fontSize: 20)]
        let withText = try ImageRenderer.render(asset: asset, state: textState)
        greater(color(withText, 11, 11).greenComponent, 0.95, "Text background belongs near the top left")
        greater(color(withText, 11, 80).blueComponent, 0.95)
        less(color(withText, 11, 80).redComponent, 0.05)
    }

    func testBlackAndWhiteAndEveryPreset() throws {
        let asset = try fixture()
        for preset in ColorPreset.allCases {
            let state = EditState(crop: asset.bounds, width: 120, height: 80, preset: preset)
            let image = try ImageRenderer.render(asset: asset, state: state)
            equal(image.width, 120)
            if preset == .mono || preset == .noir {
                let pixel = color(image, 20, 20)
                equal(pixel.redComponent, pixel.greenComponent, accuracy: 0.02)
                equal(pixel.greenComponent, pixel.blueComponent, accuracy: 0.02)
            }
        }
    }

    func testSVGExportPreservesPathsTextAndCrop() throws {
        let asset = try svgFixture()
        var state = EditState(crop: CGRect(x: 20, y: 10, width: 80, height: 60), width: 800, height: 600, preset: .mono)
        state.texts = [TextLayer(text: "A < B & C\nSecond line", x: 30, y: 20, fontSize: 10)]
        let data = try ImageRenderer.export(asset: asset, state: state, settings: ExportSettings(format: .svg))
        let document = try XMLDocument(data: data)
        let root = try unwrap(document.rootElement())
        equal(root.attribute(forName: "width")?.stringValue, "800")
        equal(root.attribute(forName: "viewBox")?.stringValue, "20.0000 10.0000 80.0000 60.0000")
        let svg = try unwrap(String(data: data, encoding: .utf8))
        isTrue(svg.contains("<rect")); isTrue(svg.contains("<text"))
        isTrue(svg.contains("A &lt; B &amp; C")); isFalse(svg.contains("base64"))
        notNil(NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testSVGRasterExportAppliesFilterAtRequestedResolution() throws {
        let asset = try svgFixture()
        let state = EditState(crop: asset.bounds, width: 600, height: 400, preset: .mono)
        let image = try decode(ImageRenderer.export(asset: asset, state: state, settings: ExportSettings()))
        equal(image.width, 600); equal(image.height, 400)
        let pixel = color(image, 100, 100)
        equal(pixel.redComponent, pixel.greenComponent, accuracy: 0.03)
        equal(pixel.greenComponent, pixel.blueComponent, accuracy: 0.03)
        greater(pixel.alphaComponent, 0.9)
    }

    func testRasterToSVGEmbedsImageAndRoundTrips() throws {
        let asset = try fixture()
        let state = EditState(crop: asset.bounds, width: 120, height: 80)
        let data = try ImageRenderer.export(asset: asset, state: state, settings: ExportSettings(format: .svg))
        isTrue(String(data: data, encoding: .utf8)!.contains("data:image/png;base64,"))
        let url = temporary.appendingPathComponent("embedded.svg")
        try data.write(to: url)
        let reopened = try ImageAsset.load(url)
        equal(reopened.width, 120)
        let pixel = color(reopened.image, 20, 20)
        greater(pixel.redComponent, 0.95)
    }

    func testInvalidFilesAndDimensionsAreRejected() throws {
        let url = temporary.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: url)
        throwsError(try ImageAsset.load(url))
        throwsError(try ImageAsset.validateDimensions(0, 80))
        throwsError(try ImageAsset.validateDimensions(16385, 1))
        throwsError(try ImageAsset.validateDimensions(10000, 10000))
    }

    func testJPEGQualityChangesFileSize() throws {
        let size = 128
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                pixels[offset] = UInt8((x * 73 + y * 41) % 256)
                pixels[offset + 1] = UInt8((x * 17 + y * 97) % 256)
                pixels[offset + 2] = UInt8((x * 53 + y * 23) % 256)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let asset = ImageAsset(image: image, name: "noise.png", fileURL: nil, svg: nil, width: size, height: size, format: "PNG")
        let state = EditState(crop: asset.bounds, width: size, height: size)
        let low = try ImageRenderer.export(asset: asset, state: state, settings: ExportSettings(format: .jpeg, quality: 0.1))
        let high = try ImageRenderer.export(asset: asset, state: state, settings: ExportSettings(format: .jpeg, quality: 1))
        isTrue(high.count > low.count * 2)
    }

    func testPhotoOrientationIsApplied() throws {
        let asset = try fixture()
        let data = NSMutableData()
        let target = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(target, asset.image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        isTrue(CGImageDestinationFinalize(target))
        let url = temporary.appendingPathComponent("rotated.jpg")
        try (data as Data).write(to: url)
        let loaded = try ImageAsset.load(url)
        equal(loaded.width, 80); equal(loaded.height, 120)
    }

    func testRecoloredSVGReopensWithItsColorPreserved() throws {
        let asset = try svgFixture()
        for preset in ColorPreset.allCases {
            let state = EditState(crop: asset.bounds, width: 120, height: 80, preset: preset)
            let data = try ImageRenderer.export(asset: asset, state: state, settings: ExportSettings(format: .svg))
            let url = temporary.appendingPathComponent("\(preset.rawValue).svg")
            try data.write(to: url)
            let reopened = try ImageAsset.load(url)
            let expected = color(try ImageRenderer.render(asset: asset, state: state), 20, 20)
            let actual = color(reopened.image, 20, 20)
            equal(actual.redComponent, expected.redComponent, accuracy: 0.03)
            equal(actual.greenComponent, expected.greenComponent, accuracy: 0.03)
            equal(actual.blueComponent, expected.blueComponent, accuracy: 0.03)
        }
    }

    func testSVGGradientCSSAndDefaultPaintAreRecolored() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">
          <defs><linearGradient id="g"><stop stop-color="red"/><stop offset="1" style="stop-color:blue"/></linearGradient></defs>
          <style>.paint { fill: lime !important; }</style>
          <rect width="40" height="80" fill="url(#g)"/>
          <rect x="40" width="40" height="80" class="paint"/>
          <rect x="80" width="40" height="80"/>
        </svg>
        """
        let url = temporary.appendingPathComponent("styles.svg")
        try svg.write(to: url, atomically: true, encoding: .utf8)
        let asset = try ImageAsset.load(url)
        let state = EditState(crop: asset.bounds, width: 120, height: 80, preset: .mono, brightness: 0.2)
        let data = try ImageRenderer.export(asset: asset, state: state, settings: ExportSettings(format: .svg))
        try data.write(to: url)
        let image = try ImageAsset.load(url).image
        for x in [10, 60, 100] {
            let pixel = color(image, x, 40)
            equal(pixel.redComponent, pixel.greenComponent, accuracy: 0.03)
            equal(pixel.greenComponent, pixel.blueComponent, accuracy: 0.03)
            greater(pixel.redComponent, 0.1)
        }
    }

    private func solidAsset(_ color: NSColor, transparentRightHalf: Bool = false) throws -> ImageAsset {
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: transparentRightHalf ? 10 : 20, height: 20))
        return ImageAsset(image: context.makeImage()!, name: "overlay.png", fileURL: nil, svg: nil, width: 20, height: 20, format: "PNG")
    }

    func testImageOverlayPositionTransparencyAndOpacity() throws {
        let base = try fixture(transparent: true)
        let overlay = try solidAsset(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), transparentRightHalf: true)
        var state = EditState(crop: base.bounds, width: 120, height: 80)
        state.images = [ImageLayer(asset: overlay, rect: CGRect(x: 10, y: 5, width: 40, height: 20), opacity: 0.5)]
        let png = try decode(ImageRenderer.export(asset: base, state: state, settings: ExportSettings()))
        equal(color(png, 15, 10).greenComponent, 1, accuracy: 0.02)
        equal(color(png, 15, 10).alphaComponent, 0.5, accuracy: 0.02)
        equal(color(png, 40, 10).alphaComponent, 0, accuracy: 0.01)
        equal(color(png, 5, 10).alphaComponent, 0, accuracy: 0.01)
        equal(color(png, 15, 70).alphaComponent, 0, accuracy: 0.01)
        let jpeg = try decode(ImageRenderer.export(asset: base, state: state, settings: ExportSettings(format: .jpeg, quality: 1, background: "FF0000")))
        greater(color(jpeg, 15, 10).greenComponent, 0.4)
        greater(color(jpeg, 15, 10).redComponent, 0.4)
        greater(color(jpeg, 40, 10).redComponent, 0.95)
        let svgURL = temporary.appendingPathComponent("transparent-overlay.svg")
        try ImageRenderer.export(asset: base, state: state, settings: ExportSettings(format: .svg)).write(to: svgURL)
        let roundTrip = try ImageAsset.load(svgURL)
        equal(color(roundTrip.image, 15, 10).alphaComponent, 0.5, accuracy: 0.02)
        equal(color(roundTrip.image, 40, 10).alphaComponent, 0, accuracy: 0.01)
    }

    func testOverlayCropResizeAndStacking() throws {
        let base = try fixture()
        let green = try solidAsset(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        let red = try solidAsset(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        var state = EditState(crop: CGRect(x: 60, y: 0, width: 60, height: 80), width: 30, height: 40)
        let rect = CGRect(x: 50, y: 10, width: 40, height: 20)
        state.images = [ImageLayer(asset: green, rect: rect), ImageLayer(asset: red, rect: rect)]
        let image = try ImageRenderer.render(asset: base, state: state)
        greater(color(image, 2, 7).redComponent, 0.95)
        less(color(image, 2, 7).greenComponent, 0.05)
        greater(color(image, 20, 7).blueComponent, 0.95)
        state.images.swapAt(0, 1)
        let reordered = try ImageRenderer.render(asset: base, state: state)
        greater(color(reordered, 2, 7).greenComponent, 0.95)
        let url = temporary.appendingPathComponent("cropped-overlays.svg")
        try ImageRenderer.export(asset: base, state: state, settings: ExportSettings(format: .svg)).write(to: url)
        let roundTrip = try ImageAsset.load(url)
        equal(roundTrip.width, 30); equal(roundTrip.height, 40)
        greater(color(roundTrip.image, 2, 7).greenComponent, 0.95)
        greater(color(roundTrip.image, 20, 7).blueComponent, 0.95)
    }

    func testSVGOverlaysPreserveVectorsAndIsolateStyles() throws {
        func vector(_ color: String, name: String) throws -> ImageAsset {
            let source = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120\" height=\"80\"><defs><linearGradient id=\"same\"><stop stop-color=\"\(color)\"/><stop offset=\"1\" stop-color=\"\(color)\"/></linearGradient></defs><path fill=\"url(#same)\" d=\"M0 0h120v80H0z\"/></svg>"
            let url = temporary.appendingPathComponent(name)
            try source.write(to: url, atomically: true, encoding: .utf8)
            return try ImageAsset.load(url)
        }
        let base = try vector("#00FF00", name: "base.svg")
        let overlay = try vector("#FF0000", name: "overlay.svg")
        var state = EditState(crop: base.bounds, width: 120, height: 80, preset: .mono)
        state.images = [ImageLayer(asset: overlay, rect: CGRect(x: 10, y: 10, width: 60, height: 40))]
        let data = try ImageRenderer.export(asset: base, state: state, settings: ExportSettings(format: .svg))
        let document = try XMLDocument(data: data)
        let imageNode = try unwrap(document.rootElement()?.elements(forName: "image").first)
        let href = try unwrap(imageNode.attribute(forName: "href")?.stringValue)
        isTrue(href.hasPrefix("data:image/svg+xml;base64,"))
        let embedded = try unwrap(Data(base64Encoded: String(href.split(separator: ",", maxSplits: 1)[1])))
        isTrue(String(data: embedded, encoding: .utf8)!.contains("<path"))
        let url = temporary.appendingPathComponent("vector-overlay-export.svg")
        try data.write(to: url)
        let roundTrip = try ImageAsset.load(url)
        let raster = try ImageRenderer.render(asset: base, state: state)
        let originalOverlay = color(overlay.image, 20, 20)
        for image in [raster, roundTrip.image] {
            equal(color(image, 20, 20).redComponent, originalOverlay.redComponent, accuracy: 0.02)
            equal(color(image, 20, 20).greenComponent, originalOverlay.greenComponent, accuracy: 0.02)
            let background = color(image, 90, 60)
            equal(background.redComponent, background.greenComponent, accuracy: 0.03)
        }
        state.images[0].opacity = 0.5
        let faded = try ImageRenderer.render(asset: base, state: state)
        let fadedURL = temporary.appendingPathComponent("faded.svg")
        try ImageRenderer.export(asset: base, state: state, settings: ExportSettings(format: .svg)).write(to: fadedURL)
        let fadedSVG = try ImageAsset.load(fadedURL).image
        equal(color(faded, 20, 20).redComponent, color(fadedSVG, 20, 20).redComponent, accuracy: 0.04)
        equal(color(faded, 20, 20).greenComponent, color(fadedSVG, 20, 20).greenComponent, accuracy: 0.04)
    }

    func testTextRendersAboveImageOverlays() throws {
        let base = try fixture(transparent: true)
        let overlay = try solidAsset(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        var state = EditState(crop: base.bounds, width: 120, height: 80)
        state.images = [ImageLayer(asset: overlay, rect: base.bounds)]
        state.texts = [TextLayer(text: "Top", x: 10, y: 10, fontSize: 12)]
        let raster = try ImageRenderer.render(asset: base, state: state)
        let url = temporary.appendingPathComponent("text-over-overlay.svg")
        try ImageRenderer.export(asset: base, state: state, settings: ExportSettings(format: .svg)).write(to: url)
        let roundTrip = try ImageAsset.load(url)
        for image in [raster, roundTrip.image] {
            greater(color(image, 11, 11).greenComponent, 0.95)
            less(color(image, 5, 5).greenComponent, 0.05)
        }
    }

    func testImageOverlayUndoReorderAndRemoval() async throws {
        let base = try svgFixture()
        let model = EditorModel()
        model.open(try unwrap(base.fileURL))
        while model.isLoading { await Task.yield() }
        let first = try fixture(), second = try solidAsset(.white)
        model.addImages([first, second])
        equal(model.tool, .image); equal(model.state?.images.count, 2)
        equal(model.currentImage?.asset.name, second.name)
        let added = try unwrap(model.currentImage)
        isTrue(model.canMoveImageBackward); isFalse(model.canMoveImageForward)
        equal(added.rect.width / added.rect.height, 1, accuracy: 0.001)
        isTrue(model.state!.crop.contains(added.rect))
        model.moveImage(forward: false)
        equal(model.state?.images.first?.id, added.id)
        model.undo(); equal(model.state?.images.last?.id, added.id)
        let count = model.undoStack.count
        model.beginTransaction("Resize image overlay")
        model.setImageWidth(30); model.setImageWidth(40)
        model.endTransaction()
        equal(model.undoStack.count, count + 1)
        equal(model.currentImage?.rect.width, 40)
        model.undo(); equal(model.currentImage?.rect, added.rect)
        model.redo(); equal(model.currentImage?.rect.width, 40)
        model.removeImage(); equal(model.state?.images.count, 1)
        model.undo(); equal(model.state?.images.count, 2)
        isTrue(model.state!.images.contains { $0.id == added.id && $0.rect.width == 40 })
        model.resetAll(); equal(model.state?.images.count, 0)
        model.undo(); equal(model.state?.images.count, 2)
    }

    @MainActor
    func testUndoRedoResizeCropAndTextTransactions() async throws {
        let asset = try svgFixture()
        let url = try unwrap(asset.fileURL)
        let model = EditorModel()
        model.open(url)
        while model.isLoading { await Task.yield() }
        isFalse(model.isDirty)
        model.addText()
        equal(model.state?.texts.count, 1)
        model.beginTransaction("Move text")
        model.updateText { $0.x = 10 }
        model.updateText { $0.x = 20 }
        model.endTransaction()
        equal(model.undoStack.count, 2)
        model.undo(); notEqual(model.currentText?.x, 20)
        model.redo(); equal(model.currentText?.x, 20)
        model.resize(width: 240, height: 160)
        model.undo(); equal(model.state?.width, 120)
        model.cropSelection = CGRect(x: 60, y: 0, width: 60, height: 80)
        model.applyCrop(); equal(model.state?.width, 60)
        model.undo(); equal(model.state?.crop, asset.bounds)
        model.undo(); model.undo(); isFalse(model.isDirty)
    }
}


// This runner works with Apple's Command Line Tools; full Xcode is not required.
@MainActor
private var failures: [String] = []
@MainActor
private func record(_ success: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    if !success { failures.append("\(file):\(line): \(message)") }
}
@MainActor
private func equal<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    record(a == b, "Expected \(b), got \(a)", file: file, line: line)
}
@MainActor
private func equal(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(abs(a - b) <= accuracy, "Expected \(b) ± \(accuracy), got \(a). \(message)", file: file, line: line)
}
@MainActor
private func greater(_ a: CGFloat, _ b: CGFloat, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { record(a > b, "Expected \(a) > \(b). \(message)", file: file, line: line) }
@MainActor
private func less(_ a: CGFloat, _ b: CGFloat, file: StaticString = #filePath, line: UInt = #line) { record(a < b, "Expected \(a) < \(b)", file: file, line: line) }
@MainActor
private func isTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { record(value, "Expected true", file: file, line: line) }
@MainActor
private func isFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { record(!value, "Expected false", file: file, line: line) }
@MainActor
private func notNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { record(value != nil, "Unexpected nil", file: file, line: line) }
@MainActor
private func notEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { record(a != b, "Unexpected equality", file: file, line: line) }
private struct CheckError: Error { let message: String }
private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckError(message: "Unexpected nil") }
    return value
}
@MainActor
private func throwsError<T>(_ action: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try action(); record(false, "Expected an error", file: file, line: line) } catch {}
}

@main
@MainActor
struct StillChecks {
    static func main() async {
        _ = NSApplication.shared
        let checks = ImageEngineTests()
        let tests: [(String, () async throws -> Void)] = [
            ("PNG transparency and round trip", checks.testPNGExportPreservesTransparencyAndSize),
            ("JPEG background and round trip", checks.testJPEGUsesChosenBackgroundAndQuality),
            ("Crop coordinates and resize", checks.testCropCoordinatesAndResize),
            ("Top-left crop and text positioning", checks.testTopLeftCropAndTextCoordinates),
            ("All color presets", checks.testBlackAndWhiteAndEveryPreset),
            ("SVG vectors, text escaping, and crop", checks.testSVGExportPreservesPathsTextAndCrop),
            ("SVG raster export resolution and color", checks.testSVGRasterExportAppliesFilterAtRequestedResolution),
            ("Raster to SVG round trip", checks.testRasterToSVGEmbedsImageAndRoundTrips),
            ("Invalid input and dimension limits", checks.testInvalidFilesAndDimensionsAreRejected),
            ("JPEG quality affects size", checks.testJPEGQualityChangesFileSize),
            ("EXIF photo orientation", checks.testPhotoOrientationIsApplied),
            ("Recolored SVG round trips", checks.testRecoloredSVGReopensWithItsColorPreserved),
            ("SVG gradients, CSS, and default fill", checks.testSVGGradientCSSAndDefaultPaintAreRecolored),
            ("Overlay position, PNG alpha, opacity, and JPEG", checks.testImageOverlayPositionTransparencyAndOpacity),
            ("Overlay crop, resize, and stacking", checks.testOverlayCropResizeAndStacking),
            ("SVG overlay vectors and isolated styles", checks.testSVGOverlaysPreserveVectorsAndIsolateStyles),
            ("Text above image overlays", checks.testTextRendersAboveImageOverlays),
            ("Overlay undo, reorder, resize, and removal", checks.testImageOverlayUndoReorderAndRemoval),
            ("Undo, redo, and grouped edits", checks.testUndoRedoResizeCropAndTextTransactions)
        ]
        for (name, test) in tests {
            let previous = failures.count
            do { try checks.setUpWithError(); try await test(); try checks.tearDownWithError() }
            catch { failures.append("\(name): \(error)") }
            print("\(failures.count == previous ? "PASS" : "FAIL")  \(name)")
        }
        for failure in failures { print(failure) }
        print("\(tests.count) checks, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}
