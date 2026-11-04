import AppKit
import ImageIO

/// Writes ordinary SVG paint colors rather than filter elements, which Apple's
/// SVG decoder does not implement. Geometry and text remain editable vectors.
enum SVGColors {
    static func recolor(_ source: String, state: EditState) throws -> String {
        guard state.preset != .original || state.brightness != 0 || state.contrast != 1 || state.saturation != 1 else { return source }
        let document = try XMLDocument(xmlString: source, options: [.nodeLoadExternalEntitiesNever])
        guard let root = document.rootElement() else { throw ImageError.cannotExport }
        let paintAttributes = ["fill", "stroke", "color", "stop-color", "flood-color", "lighting-color"]
        let declarations = try NSRegularExpression(pattern: "(?i)(?<![\\w-])(fill|stroke|color|stop-color|flood-color|lighting-color)\\s*:\\s*([^;}]+)")
        var cache: [String: String] = [:]

        func paint(_ value: String) throws -> String {
            let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cached = cache[input] { return cached }
            let lower = input.lowercased()
            let reserved = ["none", "currentcolor", "inherit", "initial", "unset", "context-fill", "context-stroke", "transparent"]
            guard !reserved.contains(lower), !lower.contains("url("), !lower.contains("var("), !input.isEmpty else { return value }
            let snippet = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"><rect width=\"1\" height=\"1\" fill=\"\(xmlEscape(input))\"/></svg>"
            guard let image = NSImage(data: Data(snippet.utf8)),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return value }
            let filtered = try ImageRenderer.filtered(cgImage, state: state)
            guard let color = filtered.sRGBColorAt(x: 0, y: 0) else { return value }
            let alpha = Int((color.alphaComponent * 255).rounded())
            let output = "#" + color.hex + (alpha < 255 ? String(format: "%02X", alpha) : "")
            cache[input] = output
            return output
        }

        func css(_ value: String) throws -> String {
            var output = value
            for match in declarations.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range(at: 2), in: output) else { continue }
                let original = String(output[range])
                let important = original.range(of: "!important", options: .caseInsensitive)
                let raw = important.map { String(original[..<$0.lowerBound]) } ?? original
                let replacement = try paint(raw) + (important == nil ? "" : " !important")
                output.replaceSubrange(range, with: replacement)
            }
            return output
        }

        func visit(_ element: XMLElement, inheritedFill: String, inheritedColor: String) throws {
            let name = element.localName ?? element.name ?? ""
            // Recoloring a mask would change its luminance and therefore its opacity.
            if name == "mask" || name == "clipPath" || name == "filter" {
                for (key, value) in [("fill", inheritedFill), ("color", inheritedColor)] where element.attribute(forName: key) == nil {
                    element.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
                }
                return
            }
            let fill = element.attribute(forName: "fill")?.stringValue ?? inheritedFill
            let color = element.attribute(forName: "color")?.stringValue ?? inheritedColor
            for attribute in element.attributes ?? [] {
                guard let name = attribute.name, let value = attribute.stringValue else { continue }
                if paintAttributes.contains(name) { attribute.stringValue = try paint(value) }
                if name == "style" { attribute.stringValue = try css(value) }
                if (name == "href" || name == "xlink:href"), value.hasPrefix("data:image/"),
                   let comma = value.firstIndex(of: ","), value[..<comma].contains(";base64"),
                   let data = Data(base64Encoded: String(value[value.index(after: comma)...])),
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    let png = NSMutableData()
                    if let target = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(target, try ImageRenderer.filtered(image, state: state), nil)
                        if CGImageDestinationFinalize(target) {
                            attribute.stringValue = "data:image/png;base64," + (png as Data).base64EncodedString()
                        }
                    }
                }
            }
            if name == "style", let value = element.stringValue { element.stringValue = try css(value) }
            for child in element.children ?? [] {
                if let child = child as? XMLElement { try visit(child, inheritedFill: fill, inheritedColor: color) }
            }
        }
        let defaultFill = root.attribute(forName: "fill") == nil
        let defaultColor = root.attribute(forName: "color") == nil
        try visit(root, inheritedFill: "black", inheritedColor: "black")
        if defaultFill { root.addAttribute(XMLNode.attribute(withName: "fill", stringValue: try paint("black")) as! XMLNode) }
        if defaultColor { root.addAttribute(XMLNode.attribute(withName: "color", stringValue: try paint("black")) as! XMLNode) }
        return root.xmlString
    }

    private static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
