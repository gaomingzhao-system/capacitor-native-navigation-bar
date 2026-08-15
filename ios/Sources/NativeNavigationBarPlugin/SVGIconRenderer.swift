/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details.
 *
 * Minimal SVG rasterizer for icon descriptors. Supports the shape subset the
 * public API documents: path, line, polyline, polygon, circle and rect. */

import UIKit

private let nativeNavigationMaximumSVGIconDimension: CGFloat = 512
private let nativeNavigationMaximumSVGInputBytes = 256 * 1_024
private let nativeNavigationMaximumSVGElementCount = 2_048
private let nativeNavigationMaximumSVGDepth = 64

func nativeNavigationIsValidSVGIconSize(_ size: CGSize) -> Bool {
    size.width.isFinite
        && size.height.isFinite
        && size.width >= 1
        && size.height >= 1
        && size.width <= nativeNavigationMaximumSVGIconDimension
        && size.height <= nativeNavigationMaximumSVGIconDimension
}

struct SVGRenderStyle {
    var fill = true
    var stroke = false
    var strokeWidth: CGFloat = 2
    var lineCap: CGLineCap = .butt
    var lineJoin: CGLineJoin = .miter
    var opacity: CGFloat = 1

    mutating func apply(_ attributes: [String: String]) {
        if let fillValue = attributes["fill"] {
            fill = fillValue.lowercased() != "none"
        }
        if let strokeValue = attributes["stroke"] {
            stroke = strokeValue.lowercased() != "none"
        }
        if let width = SVGIconRenderer.length(attributes["stroke-width"]) {
            strokeWidth = width
        }
        if let opacityValue = SVGIconRenderer.length(attributes["opacity"]) {
            opacity = max(0, min(opacityValue, 1))
        }
        if let cap = attributes["stroke-linecap"]?.lowercased() {
            switch cap {
            case "round":
                lineCap = .round
            case "square":
                lineCap = .square
            default:
                lineCap = .butt
            }
        }
        if let join = attributes["stroke-linejoin"]?.lowercased() {
            switch join {
            case "round":
                lineJoin = .round
            case "bevel":
                lineJoin = .bevel
            default:
                lineJoin = .miter
            }
        }
    }
}

// swiftlint:disable cyclomatic_complexity function_body_length
final class SVGIconRenderer: NSObject, XMLParserDelegate {
    private let context: CGContext
    private var styleStack = [SVGRenderStyle()]
    private var elementCount = 0
    private var elementDepth = 0
    private(set) var exceededSafetyLimits = false

    init(context: CGContext) {
        self.context = context
    }

    static func render(svg: String, size: CGSize) -> UIImage? {
        guard nativeNavigationIsValidSVGIconSize(size),
              svg.utf8.count <= nativeNavigationMaximumSVGInputBytes,
              svg.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              svg.range(of: "<!ENTITY", options: .caseInsensitive) == nil,
              let data = svg.data(using: .utf8) else {
            return nil
        }

        let viewBox = viewBox(in: svg) ?? CGRect(origin: .zero, size: size)
        guard viewBox.minX.isFinite,
              viewBox.minY.isFinite,
              viewBox.width.isFinite,
              viewBox.height.isFinite,
              viewBox.width > 0,
              viewBox.height > 0 else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        var parseSucceeded = false
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.saveGState()
            context.scaleBy(x: size.width / max(viewBox.width, 1), y: size.height / max(viewBox.height, 1))
            context.translateBy(x: -viewBox.minX, y: -viewBox.minY)

            let parser = XMLParser(data: data)
            let delegate = SVGIconRenderer(context: context)
            parser.delegate = delegate
            parser.shouldResolveExternalEntities = false
            parseSucceeded = parser.parse() && !delegate.exceededSafetyLimits
            context.restoreGState()
        }
        return parseSucceeded ? image : nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        elementCount += 1
        elementDepth += 1
        guard elementCount <= nativeNavigationMaximumSVGElementCount,
              elementDepth <= nativeNavigationMaximumSVGDepth else {
            exceededSafetyLimits = true
            parser.abortParsing()
            return
        }

        var style = styleStack.last ?? SVGRenderStyle()
        style.apply(attributeDict)
        styleStack.append(style)

        switch elementName.lowercased() {
        case "path":
            guard let pathData = attributeDict["d"] else {
                return
            }
            draw(SVGPathParser(pathData).parse(), style: style)
        case "line":
            let path = UIBezierPath()
            path.move(to: CGPoint(x: Self.length(attributeDict["x1"]) ?? 0, y: Self.length(attributeDict["y1"]) ?? 0))
            path.addLine(to: CGPoint(x: Self.length(attributeDict["x2"]) ?? 0, y: Self.length(attributeDict["y2"]) ?? 0))
            draw(path, style: style)
        case "polyline", "polygon":
            let points = Self.points(attributeDict["points"])
            guard let first = points.first else {
                return
            }
            let path = UIBezierPath()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            if elementName.lowercased() == "polygon" {
                path.close()
            }
            draw(path, style: style)
        case "circle":
            let cx = Self.length(attributeDict["cx"]) ?? 0
            let cy = Self.length(attributeDict["cy"]) ?? 0
            let radius = Self.length(attributeDict["r"]) ?? 0
            draw(
                UIBezierPath(ovalIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)),
                style: style
            )
        case "rect":
            let rect = CGRect(
                x: Self.length(attributeDict["x"]) ?? 0,
                y: Self.length(attributeDict["y"]) ?? 0,
                width: Self.length(attributeDict["width"]) ?? 0,
                height: Self.length(attributeDict["height"]) ?? 0
            )
            let radius = Self.length(attributeDict["rx"]) ?? Self.length(attributeDict["ry"]) ?? 0
            let path = radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius) : UIBezierPath(rect: rect)
            draw(path, style: style)
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if styleStack.count > 1 {
            styleStack.removeLast()
        }
        elementDepth = max(0, elementDepth - 1)
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        exceededSafetyLimits = true
        parser.abortParsing()
        return nil
    }

    private func draw(_ path: UIBezierPath, style: SVGRenderStyle) {
        context.saveGState()
        path.lineWidth = style.strokeWidth
        path.lineCapStyle = style.lineCap
        path.lineJoinStyle = style.lineJoin
        UIColor.black.withAlphaComponent(style.opacity).setFill()
        UIColor.black.withAlphaComponent(style.opacity).setStroke()
        if style.fill {
            path.fill()
        }
        if style.stroke {
            path.stroke()
        }
        context.restoreGState()
    }

    static func length(_ value: String?) -> CGFloat? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "-+.0123456789eE")
        let prefix = String(value.unicodeScalars.prefix { allowed.contains($0) })
        guard let double = Double(prefix), double.isFinite else {
            return nil
        }
        return CGFloat(double)
    }

    static func points(_ value: String?) -> [CGPoint] {
        let numbers = numbers(in: value ?? "")
        var points: [CGPoint] = []
        var index = 0
        while index + 1 < numbers.count {
            points.append(CGPoint(x: numbers[index], y: numbers[index + 1]))
            index += 2
        }
        return points
    }

    private static func viewBox(in svg: String) -> CGRect? {
        if let rawViewBox = attribute("viewBox", in: svg) {
            let values = numbers(in: rawViewBox)
            if values.count >= 4 {
                return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            }
        }
        guard let width = length(attribute("width", in: svg)),
              let height = length(attribute("height", in: svg)) else {
            return nil
        }
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    private static func attribute(_ name: String, in svg: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(svg.startIndex..<svg.endIndex, in: svg)
        guard let match = expression.firstMatch(in: svg, range: range),
              let valueRange = Range(match.range(at: 1), in: svg) else {
            return nil
        }
        return String(svg[valueRange])
    }

    private static func numbers(in value: String) -> [CGFloat] {
        let pattern = "[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var values: [CGFloat] = []
        for match in expression.matches(in: value, range: range) {
            if let valueRange = Range(match.range, in: value),
               let double = Double(value[valueRange]),
               double.isFinite {
                values.append(CGFloat(double))
            }
        }
        return values
    }
}

final class SVGPathParser {
    private let tokens: [String]
    private var index = 0
    private var command: Character?
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    private var lastCubicControl: CGPoint?
    private var lastQuadControl: CGPoint?

    init(_ data: String) {
        tokens = Self.tokenize(data)
    }

    func parse() -> UIBezierPath {
        let path = UIBezierPath()
        while index < tokens.count {
            if let nextCommand = commandToken() {
                command = nextCommand
                index += 1
            }
            guard let command = command else {
                break
            }
            let consumeStart = index
            consume(command, into: path)
            if index == consumeStart {
                self.command = nil
                if index < tokens.count, commandToken() == nil {
                    index += 1
                }
            }
        }
        return path
    }

    private func consume(_ command: Character, into path: UIBezierPath) {
        let relative = command.isLowercase
        switch command.uppercased() {
        case "M":
            guard let firstPoint = point(relative: relative) else {
                return
            }
            path.move(to: firstPoint)
            current = firstPoint
            subpathStart = firstPoint
            while let nextPoint = point(relative: relative) {
                path.addLine(to: nextPoint)
                current = nextPoint
            }
            resetControls()
        case "L":
            while let nextPoint = point(relative: relative) {
                path.addLine(to: nextPoint)
                current = nextPoint
            }
            resetControls()
        case "H":
            while let value = number() {
                current = CGPoint(x: relative ? current.x + value : value, y: current.y)
                path.addLine(to: current)
            }
            resetControls()
        case "V":
            while let value = number() {
                current = CGPoint(x: current.x, y: relative ? current.y + value : value)
                path.addLine(to: current)
            }
            resetControls()
        case "C":
            while let control1 = point(relative: relative),
                  let control2 = point(relative: relative),
                  let end = point(relative: relative) {
                path.addCurve(to: end, controlPoint1: control1, controlPoint2: control2)
                current = end
                lastCubicControl = control2
                lastQuadControl = nil
            }
        case "S":
            while let control2 = point(relative: relative),
                  let end = point(relative: relative) {
                let control1 = reflected(lastCubicControl)
                path.addCurve(to: end, controlPoint1: control1, controlPoint2: control2)
                current = end
                lastCubicControl = control2
                lastQuadControl = nil
            }
        case "Q":
            while let control = point(relative: relative),
                  let end = point(relative: relative) {
                path.addQuadCurve(to: end, controlPoint: control)
                current = end
                lastQuadControl = control
                lastCubicControl = nil
            }
        case "T":
            while let end = point(relative: relative) {
                let control = reflected(lastQuadControl)
                path.addQuadCurve(to: end, controlPoint: control)
                current = end
                lastQuadControl = control
                lastCubicControl = nil
            }
        case "A":
            while let end = arcEndpoint(relative: relative) {
                path.addLine(to: end)
                current = end
            }
            resetControls()
        case "Z":
            path.close()
            current = subpathStart
            resetControls()
        default:
            index += 1
        }
    }

    private func point(relative: Bool) -> CGPoint? {
        guard let x = number(),
              let y = number() else {
            return nil
        }
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    private func arcEndpoint(relative: Bool) -> CGPoint? {
        guard number() != nil,
              number() != nil,
              number() != nil,
              number() != nil,
              number() != nil,
              let x = number(),
              let y = number() else {
            return nil
        }
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    private func number() -> CGFloat? {
        guard index < tokens.count,
              commandToken() == nil,
              let value = Double(tokens[index]),
              value.isFinite else {
            return nil
        }
        index += 1
        return CGFloat(value)
    }

    private func commandToken() -> Character? {
        guard index < tokens.count,
              tokens[index].count == 1,
              let character = tokens[index].first,
              character.isLetter else {
            return nil
        }
        return character
    }

    private func reflected(_ point: CGPoint?) -> CGPoint {
        guard let point = point else {
            return current
        }
        return CGPoint(x: current.x * 2 - point.x, y: current.y * 2 - point.y)
    }

    private func resetControls() {
        lastCubicControl = nil
        lastQuadControl = nil
    }

    private static func tokenize(_ data: String) -> [String] {
        var tokens: [String] = []
        var index = data.startIndex
        while index < data.endIndex {
            let character = data[index]
            if character.isWhitespace || character == "," {
                index = data.index(after: index)
                continue
            }
            if character.isLetter {
                tokens.append(String(character))
                index = data.index(after: index)
                continue
            }

            let start = index
            var end = index
            var hasDigits = false

            if data[end] == "-" || data[end] == "+" {
                end = data.index(after: end)
            }

            while end < data.endIndex, data[end].isNumber {
                hasDigits = true
                end = data.index(after: end)
            }

            if end < data.endIndex, data[end] == "." {
                end = data.index(after: end)
                while end < data.endIndex, data[end].isNumber {
                    hasDigits = true
                    end = data.index(after: end)
                }
            }

            if hasDigits, end < data.endIndex, data[end] == "e" || data[end] == "E" {
                let exponentStart = end
                var exponentEnd = data.index(after: end)
                if exponentEnd < data.endIndex, data[exponentEnd] == "-" || data[exponentEnd] == "+" {
                    exponentEnd = data.index(after: exponentEnd)
                }
                var hasExponentDigits = false
                while exponentEnd < data.endIndex, data[exponentEnd].isNumber {
                    hasExponentDigits = true
                    exponentEnd = data.index(after: exponentEnd)
                }
                if hasExponentDigits {
                    end = exponentEnd
                } else {
                    end = exponentStart
                }
            }

            if hasDigits, end > start {
                tokens.append(String(data[start..<end]))
                index = end
            } else {
                index = data.index(after: index)
            }
        }
        return tokens
    }
}
// swiftlint:enable cyclomatic_complexity function_body_length

extension UIColor {
    convenience init?(nativeNavigationHexString hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        var hex: UInt64 = 0
        guard Scanner(string: value).scanHexInt64(&hex) else {
            return nil
        }

        switch value.count {
        case 6:
            self.init(
                red: CGFloat((hex & 0xFF0000) >> 16) / 255,
                green: CGFloat((hex & 0x00FF00) >> 8) / 255,
                blue: CGFloat(hex & 0x0000FF) / 255,
                alpha: 1
            )
        case 8:
            self.init(
                red: CGFloat((hex & 0x00FF0000) >> 16) / 255,
                green: CGFloat((hex & 0x0000FF00) >> 8) / 255,
                blue: CGFloat(hex & 0x000000FF) / 255,
                alpha: CGFloat((hex & 0xFF000000) >> 24) / 255
            )
        default:
            return nil
        }
    }
}
