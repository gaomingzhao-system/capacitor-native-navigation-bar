from pathlib import Path
import re
import textwrap

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    source = target.read_text(encoding="utf-8")
    if old not in source:
        raise RuntimeError(f"{path}: required text not found: {old[:120]!r}")
    target.write_text(source.replace(old, textwrap.dedent(new).strip("\n"), 1), encoding="utf-8")


def replace_regex(path: str, pattern: str, replacement: str, count: int = 1) -> None:
    target = ROOT / path
    source = target.read_text(encoding="utf-8")
    updated, matches = re.subn(pattern, textwrap.dedent(replacement).strip("\n"), source, count=count, flags=re.S)
    if matches != count:
        raise RuntimeError(f"{path}: expected {count} matches for {pattern!r}, got {matches}")
    target.write_text(updated, encoding="utf-8")


def replace_optional(path: str, old: str, new: str) -> None:
    target = ROOT / path
    source = target.read_text(encoding="utf-8")
    if old in source:
        target.write_text(source.replace(old, textwrap.dedent(new).strip("\n"), 1), encoding="utf-8")


def insert_before(path: str, marker: str, content: str) -> None:
    target = ROOT / path
    source = target.read_text(encoding="utf-8")
    index = source.find(marker)
    if index < 0:
        raise RuntimeError(f"{path}: marker not found: {marker!r}")
    target.write_text(source[:index] + textwrap.dedent(content).strip("\n") + "\n\n" + source[index:], encoding="utf-8")


def insert_before_final(path: str, content: str) -> None:
    target = ROOT / path
    source = target.read_text(encoding="utf-8")
    marker = "\n}\n"
    index = source.rfind(marker)
    if index < 0:
        raise RuntimeError(f"{path}: final class marker not found")
    target.write_text(source[:index] + "\n" + textwrap.dedent(content).strip("\n") + source[index:], encoding="utf-8")


# Phase-one compatibility cleanups.
validation = read("src/validation.ts")
for unused in [
    "  NativeNavigationGlassOptions,\n",
    "  NativeNavigationIcon,\n",
    "  NativeNavigationRect,\n",
    "  NativeNavigationTabbarStyle,\n",
]:
    validation = validation.replace(unused, "")
(ROOT / "src/validation.ts").write_text(validation, encoding="utf-8")
replace_optional(
    "test/web.test.ts",
    "} as unknown as NativeNavigationTabbarOptions)",
    "} as never)",
)

# Public Android edge-to-edge ownership option.
replace_once(
    "src/definitions.ts",
    '''  /** Default native transition duration in milliseconds. */
  animationDuration?: number

  /** Shared color hints for native bars. */''',
    '''  /** Default native transition duration in milliseconds. */
  animationDuration?: number

  /**
   * Android only: allow the plugin to temporarily own the Activity's
   * edge-to-edge setting. Defaults to `false`; host applications normally
   * configure edge-to-edge through Capacitor itself.
   */
  manageEdgeToEdge?: boolean

  /** Shared color hints for native bars. */''',
)
replace_once(
    "src/validation.ts",
    '''const assertEnum = (
  value: unknown,''',
    '''const assertBoolean = (value: unknown, path: string): void => {
  if (value === undefined || value === null) return
  if (typeof value !== "boolean") throw new TypeError(`${path} must be a boolean`)
}

const assertEnum = (
  value: unknown,''',
)
replace_once(
    "src/validation.ts",
    '''  assertFiniteRange(runtime.animationDuration, "animationDuration", 0, NATIVE_NAVIGATION_MAX_DURATION_MS)
  validateGlass(runtime.glass, "glass")''',
    '''  assertFiniteRange(runtime.animationDuration, "animationDuration", 0, NATIVE_NAVIGATION_MAX_DURATION_MS)
  assertBoolean(runtime.manageEdgeToEdge, "manageEdgeToEdge")
  validateGlass(runtime.glass, "glass")''',
)

# iOS: retain view placement and restore lifted overlays/constraints.
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationChrome.swift",
    r'''final class NativeNavigationWeakView \{.*?private func nativeNavigationDeactivateParentConstraints\(in parent: UIView, involving view: UIView\) -> Bool \{.*?\n\}''',
    r'''
    final class NativeNavigationWeakView {
        weak var value: UIView?
        weak var originalSuperview: UIView?
        let originalIndex: Int
        let originalFrame: CGRect
        let originalAutoresizingMask: UIView.AutoresizingMask
        let originalTranslatesAutoresizingMaskIntoConstraints: Bool
        let originalConstraints: [NSLayoutConstraint]

        init(_ value: UIView) {
            self.value = value
            originalSuperview = value.superview
            originalIndex = value.superview?.subviews.firstIndex(of: value) ?? 0
            originalFrame = value.frame
            originalAutoresizingMask = value.autoresizingMask
            originalTranslatesAutoresizingMaskIntoConstraints = value.translatesAutoresizingMaskIntoConstraints
            originalConstraints = value.superview?.constraints.filter { constraint in
                constraint.firstItem === value || constraint.secondItem === value
            } ?? []
        }

        @discardableResult
        func restore() -> Bool {
            guard let value, let originalSuperview else {
                return false
            }
            NSLayoutConstraint.deactivate(originalConstraints)
            value.removeFromSuperview()
            originalSuperview.insertSubview(
                value,
                at: min(max(originalIndex, 0), originalSuperview.subviews.count)
            )
            value.translatesAutoresizingMaskIntoConstraints = originalTranslatesAutoresizingMaskIntoConstraints
            value.autoresizingMask = originalAutoresizingMask
            value.frame = originalFrame
            NSLayoutConstraint.activate(originalConstraints)
            return true
        }
    }

    func nativeNavigationLiftWebViewOverlaySubviews(
        from webView: UIView,
        to container: UIView,
        tracking liftedOverlays: inout [NativeNavigationWeakView],
        excluding excludedViews: [UIView?] = []
    ) {
        webView.subviews
            .filter { nativeNavigationShouldLiftWebViewOverlay($0, excluding: excludedViews) }
            .forEach { overlay in
                let placement = NativeNavigationWeakView(overlay)
                let frame = overlay.convert(overlay.bounds, to: container)
                NSLayoutConstraint.deactivate(placement.originalConstraints)
                overlay.removeFromSuperview()
                overlay.translatesAutoresizingMaskIntoConstraints = true
                overlay.frame = frame
                overlay.autoresizingMask = overlay.autoresizingMask.isEmpty
                    ? [.flexibleWidth, .flexibleHeight]
                    : overlay.autoresizingMask
                container.addSubview(overlay)
                liftedOverlays.append(placement)
            }

        liftedOverlays = liftedOverlays.filter { $0.value != nil }
        liftedOverlays
            .compactMap(\.value)
            .filter { $0.superview === container }
            .forEach { container.bringSubviewToFront($0) }
    }

    func nativeNavigationRestoreLiftedViews(_ liftedViews: inout [NativeNavigationWeakView]) {
        liftedViews.reversed().forEach { _ = $0.restore() }
        liftedViews.removeAll()
    }

    func nativeNavigationShouldLiftWebViewOverlay(_ view: UIView, excluding excludedViews: [UIView?] = []) -> Bool {
        if excludedViews.contains(where: { $0 === view }) {
            return false
        }

        if view is UIScrollView {
            return false
        }

        let className = NSStringFromClass(type(of: view))
        return !className.contains("WK")
    }
    ''',
)

# iOS plugin constants and placement state.
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    '''private let nativeNavigationMaximumLayoutDimension: CGFloat = 4_096
private let nativeNavigationMaximumDecodedSVGBytes''',
    '''private let nativeNavigationMaximumLayoutDimension: CGFloat = 4_096
private let nativeNavigationMaximumSnapshotPixels: CGFloat = 8_388_608
private let nativeNavigationMaximumDecodedSVGBytes''',
)
insert_before(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    "func nativeNavigationIsSafeTransitionRect",
    r'''
    func nativeNavigationSnapshotRendererScale(size: CGSize, displayScale: CGFloat) -> CGFloat {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return 1
        }
        let safeDisplayScale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        let pixels = size.width * safeDisplayScale * size.height * safeDisplayScale
        guard pixels > nativeNavigationMaximumSnapshotPixels else {
            return safeDisplayScale
        }
        let reduction = sqrt(nativeNavigationMaximumSnapshotPixels / pixels)
        return max(0.25, safeDisplayScale * reduction)
    }
    ''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    '''    private weak var originalWebViewSuperview: UIView?
    private var originalWebViewIndex: Int?
    private var originalWebViewAutoresizingMask: UIView.AutoresizingMask?
    private var liftedWebViewOverlays: [NativeNavigationWeakView] = []''',
    '''    private var originalWebViewPlacement: NativeNavigationWeakView?
    private var liftedWebViewOverlays: [NativeNavigationWeakView] = []
    private weak var systemTabHostParent: UIViewController?
    private var systemTabRootWasWrapped = false
    private var wrappedRootOriginalFrame: CGRect?
    private var wrappedRootOriginalAutoresizingMask: UIView.AutoresizingMask?''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    '''    deinit {
        NotificationCenter.default.removeObserver(self)
        activeTransitionSession?.watchdog?.cancel()''',
    '''    deinit {
        if Thread.isMainThread {
            teardownNativeChrome()
        } else {
            DispatchQueue.main.sync { [self] in
                teardownNativeChrome()
            }
        }
        NotificationCenter.default.removeObserver(self)
        activeTransitionSession?.watchdog?.cancel()''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    '''            let patch = call.options as? [String: Any] ?? [:]
            if let rawDuration = patch["animationDuration"]''',
    '''            let patch = call.options as? [String: Any] ?? [:]
            if (patch["platformStyle"] as? String)?.lowercased() == "android" {
                call.reject("platformStyle 'android' is not available on iOS")
                return
            }
            if let rawDuration = patch["animationDuration"]''',
)
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    r'''    private func captureOriginalWebViewPlacementIfNeeded\(_ webView: UIView\) \{.*?\n    \}''',
    r'''
        private func captureOriginalWebViewPlacementIfNeeded(_ webView: UIView) {
            guard originalWebViewPlacement == nil, webView.superview != nil else {
                return
            }
            originalWebViewPlacement = NativeNavigationWeakView(webView)
        }
    ''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    '''        if let originalWebViewSuperview = originalWebViewSuperview,
           originalWebViewSuperview === parentView {
            return min(originalWebViewIndex ?? parentView.subviews.count, parentView.subviews.count)
        }''',
    '''        if let placement = originalWebViewPlacement,
           placement.originalSuperview === parentView {
            return min(placement.originalIndex, parentView.subviews.count)
        }''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    '''        systemTabRootContainer = container
        originalWebViewSuperview = container
        originalWebViewIndex = 0
        originalWebViewAutoresizingMask = webView.autoresizingMask
        liftWebViewOverlaysAboveSystemTabs()
        return container''',
    '''        systemTabRootContainer = container
        systemTabHostParent = parent
        systemTabRootWasWrapped = true
        wrappedRootOriginalFrame = previousFrame
        wrappedRootOriginalAutoresizingMask = previousAutoresizingMask
        originalWebViewPlacement = NativeNavigationWeakView(webView)
        liftWebViewOverlaysAboveSystemTabs()
        return container''',
)
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    r'''    private func restoreWebViewFromSystemTabController\(\) \{.*?\n    \}\n\n    private func clearHostedWebViews''',
    r'''
        private func restoreWebViewFromSystemTabController() {
            guard let webView = webView else {
                return
            }

            if isWebViewHostedInSystemTabController {
                clearHostedWebViews(matching: webView)
                webView.removeFromSuperview()
                if originalWebViewPlacement?.restore() != true,
                   let container = systemTabRootContainer {
                    container.insertSubview(webView, at: 0)
                    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    webView.frame = container.bounds
                }
                isWebViewHostedInSystemTabController = false
            }

            nativeNavigationRestoreLiftedViews(&liftedWebViewOverlays)

            if systemTabRootWasWrapped,
               let parent = systemTabHostParent,
               let container = systemTabRootContainer {
                webView.removeFromSuperview()
                parent.view = webView
                webView.frame = wrappedRootOriginalFrame ?? container.frame
                webView.autoresizingMask = wrappedRootOriginalAutoresizingMask ?? [.flexibleWidth, .flexibleHeight]
                if let navContainer, navContainer.superview === container {
                    webView.addSubview(navContainer)
                }
                container.removeFromSuperview()
            }

            originalWebViewPlacement = nil
            systemTabRootContainer = nil
            systemTabHostParent = nil
            systemTabRootWasWrapped = false
            wrappedRootOriginalFrame = nil
            wrappedRootOriginalAutoresizingMask = nil
        }

        private func clearHostedWebViews''',
)
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    r'''    private func setTabBarBackgroundSubviewsHidden\(_ hidden: Bool, on tabBar: UITabBar\) \{.*?\n    \}''',
    r'''
        private func setTabBarBackgroundSubviewsHidden(_ hidden: Bool, on tabBar: UITabBar) {
            tabBar.isHidden = hidden
            tabBar.alpha = hidden ? 0 : 1
            tabBar.isUserInteractionEnabled = !hidden
        }
    ''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    '''    private func showFloatingTabBarChrome(_ tabBar: NativeNavigationFloatingTabBar) {
        restoreWebViewFromSystemTabController()
        tabBarController?.view.isHidden = true''',
    '''    private func showFloatingTabBarChrome(_ tabBar: NativeNavigationFloatingTabBar) {
        teardownSystemTabController()
        tabBarController?.view.isHidden = true''',
)
insert_before(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    "    private func makeBarButtonItems",
    r'''
        private func teardownSystemTabController() {
            restoreWebViewFromSystemTabController()
            guard let controller = tabBarController else {
                return
            }
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            tabViewControllers.removeAll()
            if tabBar === controller.tabBar {
                tabBar = nil
            }
            tabBarController = nil
        }

        private func teardownNativeChrome() {
            activeTransitionSession?.watchdog?.cancel()
            if let session = activeTransitionSession {
                session.snapshot?.removeFromSuperview()
                session.webView.alpha = 1
                session.webView.transform = .identity
                session.webView.layer.cornerRadius = 0
                session.webView.clipsToBounds = false
            }
            activeTransitionSession = nil
            restoreTransitionContainerBackground()
            teardownSystemTabController()
            nativeNavigationRestoreLiftedViews(&liftedWebViewOverlays)
            navContainer?.removeFromSuperview()
            tabContainer?.removeFromSuperview()
            floatingTabBar?.removeFromSuperview()
            navContainer = nil
            tabContainer = nil
            floatingTabBar = nil
        }
    ''',
)
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    r'''        let renderer = UIGraphicsImageRenderer\(bounds: webView.bounds\)\n        let image = renderer.image \{ _ in\n            webView.drawHierarchy\(in: webView.bounds, afterScreenUpdates: false\)\n        \}\n        let scale = image.scale\n        let scaledCropRect = CGRect\(.*?\n        let imageView = UIImageView\(image: UIImage\(cgImage: croppedImage, scale: scale, orientation: image.imageOrientation\)\)''',
    r'''
            let format = UIGraphicsImageRendererFormat()
            format.scale = nativeNavigationSnapshotRendererScale(
                size: cropRect.size,
                displayScale: webView.window?.screen.scale ?? UIScreen.main.scale
            )
            let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
            let image = renderer.image { _ in
                webView.drawHierarchy(
                    in: CGRect(
                        x: -cropRect.minX,
                        y: -cropRect.minY,
                        width: webView.bounds.width,
                        height: webView.bounds.height
                    ),
                    afterScreenUpdates: false
                )
            }

            let imageView = UIImageView(image: image)''',
)
# Animate custom floating-tab updates as requested by the public API.
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
    r'''            tabBar\.configure\(\n                items: items,\n                selectedIndex: resolvedSelectedIndex,\n                labelVisibilityMode: labelVisibilityMode,\n                icons: icons,\n                style: tabbarStyle\n            \)''',
    r'''
                let configureFloatingBar = {
                    tabBar.configure(
                        items: items,
                        selectedIndex: resolvedSelectedIndex,
                        labelVisibilityMode: labelVisibilityMode,
                        icons: icons,
                        style: self.tabbarStyle
                    )
                }
                if options.bool("animated", default: false) {
                    UIView.transition(
                        with: tabBar,
                        duration: 0.2,
                        options: [.transitionCrossDissolve, .allowUserInteraction],
                        animations: configureFloatingBar
                    )
                } else {
                    configureFloatingBar()
                }''',
)

# iOS SVG: preserve original colors and implement elliptical arcs.
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/SVGIconRenderer.swift",
    r'''struct SVGRenderStyle \{.*?\n\}\n\n// swiftlint:disable cyclomatic_complexity function_body_length''',
    r'''
    private func nativeNavigationSVGColor(_ value: String?, fallback: UIColor) -> UIColor {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return fallback
        }
        let value = rawValue.lowercased()
        if value == "currentcolor" || value == "none" {
            return fallback
        }
        let named: [String: UIColor] = [
            "black": .black,
            "white": .white,
            "red": .red,
            "green": .green,
            "blue": .blue,
            "gray": .gray,
            "grey": .gray,
            "yellow": .yellow,
            "orange": .orange,
            "purple": .purple,
            "clear": .clear
        ]
        if let color = named[value] {
            return color
        }
        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            let expanded: String
            if hex.count == 3 || hex.count == 4 {
                expanded = hex.map { "\($0)\($0)" }.joined()
            } else {
                expanded = hex
            }
            guard expanded.count == 6 || expanded.count == 8,
                  let number = UInt64(expanded, radix: 16) else {
                return fallback
            }
            let red = CGFloat((number >> (expanded.count == 8 ? 24 : 16)) & 0xFF) / 255
            let green = CGFloat((number >> (expanded.count == 8 ? 16 : 8)) & 0xFF) / 255
            let blue = CGFloat((number >> (expanded.count == 8 ? 8 : 0)) & 0xFF) / 255
            let alpha = expanded.count == 8 ? CGFloat(number & 0xFF) / 255 : 1
            return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        return fallback
    }

    struct SVGRenderStyle {
        var fill = true
        var stroke = false
        var fillColor = UIColor.black
        var strokeColor = UIColor.black
        var strokeWidth: CGFloat = 2
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var opacity: CGFloat = 1
        var fillOpacity: CGFloat = 1
        var strokeOpacity: CGFloat = 1

        mutating func apply(_ attributes: [String: String]) {
            if let fillValue = attributes["fill"] {
                fill = fillValue.lowercased() != "none"
                fillColor = nativeNavigationSVGColor(fillValue, fallback: fillColor)
            }
            if let strokeValue = attributes["stroke"] {
                stroke = strokeValue.lowercased() != "none"
                strokeColor = nativeNavigationSVGColor(strokeValue, fallback: strokeColor)
            }
            if let width = SVGIconRenderer.length(attributes["stroke-width"]) {
                strokeWidth = max(0, min(width, 1_024))
            }
            if let opacityValue = SVGIconRenderer.length(attributes["opacity"]) {
                opacity = max(0, min(opacityValue, 1))
            }
            if let opacityValue = SVGIconRenderer.length(attributes["fill-opacity"]) {
                fillOpacity = max(0, min(opacityValue, 1))
            }
            if let opacityValue = SVGIconRenderer.length(attributes["stroke-opacity"]) {
                strokeOpacity = max(0, min(opacityValue, 1))
            }
            if let cap = attributes["stroke-linecap"]?.lowercased() {
                switch cap {
                case "round": lineCap = .round
                case "square": lineCap = .square
                default: lineCap = .butt
                }
            }
            if let join = attributes["stroke-linejoin"]?.lowercased() {
                switch join {
                case "round": lineJoin = .round
                case "bevel": lineJoin = .bevel
                default: lineJoin = .miter
                }
            }
        }
    }

    // swiftlint:disable cyclomatic_complexity function_body_length''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/SVGIconRenderer.swift",
    '''        UIColor.black.withAlphaComponent(style.opacity).setFill()
        UIColor.black.withAlphaComponent(style.opacity).setStroke()''',
    '''        style.fillColor.withAlphaComponent(style.fillColor.cgColor.alpha * style.opacity * style.fillOpacity).setFill()
        style.strokeColor.withAlphaComponent(style.strokeColor.cgColor.alpha * style.opacity * style.strokeOpacity).setStroke()''',
)
replace_once(
    "ios/Sources/NativeNavigationBarPlugin/SVGIconRenderer.swift",
    '''        case "A":
            while let end = arcEndpoint(relative: relative) {
                path.addLine(to: end)
                current = end
            }
            resetControls()''',
    '''        case "A":
            while appendArc(relative: relative, to: path) {}
            resetControls()''',
)
replace_regex(
    "ios/Sources/NativeNavigationBarPlugin/SVGIconRenderer.swift",
    r'''    private func arcEndpoint\(relative: Bool\) -> CGPoint\? \{.*?\n    \}\n\n    private func number''',
    r'''
        private func appendArc(relative: Bool, to path: UIBezierPath) -> Bool {
            guard let rawRadiusX = number(),
                  let rawRadiusY = number(),
                  let rotationDegrees = number(),
                  let largeArcValue = number(),
                  let sweepValue = number(),
                  let rawX = number(),
                  let rawY = number() else {
                return false
            }

            let end = relative
                ? CGPoint(x: current.x + rawX, y: current.y + rawY)
                : CGPoint(x: rawX, y: rawY)
            var radiusX = abs(rawRadiusX)
            var radiusY = abs(rawRadiusY)
            guard radiusX > 0, radiusY > 0, end != current else {
                path.addLine(to: end)
                current = end
                return true
            }

            let rotation = rotationDegrees * .pi / 180
            let cosine = cos(rotation)
            let sine = sin(rotation)
            let deltaX = (current.x - end.x) / 2
            let deltaY = (current.y - end.y) / 2
            let transformedX = cosine * deltaX + sine * deltaY
            let transformedY = -sine * deltaX + cosine * deltaY

            let radiiScale = transformedX * transformedX / (radiusX * radiusX)
                + transformedY * transformedY / (radiusY * radiusY)
            if radiiScale > 1 {
                let scale = sqrt(radiiScale)
                radiusX *= scale
                radiusY *= scale
            }

            let numerator = max(
                0,
                radiusX * radiusX * radiusY * radiusY
                    - radiusX * radiusX * transformedY * transformedY
                    - radiusY * radiusY * transformedX * transformedX
            )
            let denominator = max(
                radiusX * radiusX * transformedY * transformedY
                    + radiusY * radiusY * transformedX * transformedX,
                .leastNonzeroMagnitude
            )
            let largeArc = largeArcValue != 0
            let sweep = sweepValue != 0
            let sign: CGFloat = largeArc == sweep ? -1 : 1
            let coefficient = sign * sqrt(numerator / denominator)
            let centerTransformedX = coefficient * radiusX * transformedY / radiusY
            let centerTransformedY = coefficient * -radiusY * transformedX / radiusX
            let center = CGPoint(
                x: cosine * centerTransformedX - sine * centerTransformedY + (current.x + end.x) / 2,
                y: sine * centerTransformedX + cosine * centerTransformedY + (current.y + end.y) / 2
            )

            let startVector = CGPoint(
                x: (transformedX - centerTransformedX) / radiusX,
                y: (transformedY - centerTransformedY) / radiusY
            )
            let endVector = CGPoint(
                x: (-transformedX - centerTransformedX) / radiusX,
                y: (-transformedY - centerTransformedY) / radiusY
            )
            let startAngle = atan2(startVector.y, startVector.x)
            var deltaAngle = vectorAngle(from: startVector, to: endVector)
            if !sweep, deltaAngle > 0 { deltaAngle -= .pi * 2 }
            if sweep, deltaAngle < 0 { deltaAngle += .pi * 2 }

            let segmentCount = max(1, Int(ceil(abs(deltaAngle) / (.pi / 2))))
            let segmentAngle = deltaAngle / CGFloat(segmentCount)
            for segment in 0..<segmentCount {
                let angle1 = startAngle + CGFloat(segment) * segmentAngle
                let angle2 = angle1 + segmentAngle
                let alpha = 4 / 3 * tan((angle2 - angle1) / 4)
                let point1 = ellipsePoint(center: center, radiusX: radiusX, radiusY: radiusY, rotation: rotation, angle: angle1)
                let point2 = ellipsePoint(center: center, radiusX: radiusX, radiusY: radiusY, rotation: rotation, angle: angle2)
                let derivative1 = ellipseDerivative(radiusX: radiusX, radiusY: radiusY, rotation: rotation, angle: angle1)
                let derivative2 = ellipseDerivative(radiusX: radiusX, radiusY: radiusY, rotation: rotation, angle: angle2)
                if segment == 0, hypot(path.currentPoint.x - point1.x, path.currentPoint.y - point1.y) > 0.01 {
                    path.addLine(to: point1)
                }
                path.addCurve(
                    to: point2,
                    controlPoint1: CGPoint(x: point1.x + alpha * derivative1.x, y: point1.y + alpha * derivative1.y),
                    controlPoint2: CGPoint(x: point2.x - alpha * derivative2.x, y: point2.y - alpha * derivative2.y)
                )
            }
            current = end
            return true
        }

        private func vectorAngle(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
            atan2(lhs.x * rhs.y - lhs.y * rhs.x, lhs.x * rhs.x + lhs.y * rhs.y)
        }

        private func ellipsePoint(
            center: CGPoint,
            radiusX: CGFloat,
            radiusY: CGFloat,
            rotation: CGFloat,
            angle: CGFloat
        ) -> CGPoint {
            let cosine = cos(rotation)
            let sine = sin(rotation)
            return CGPoint(
                x: center.x + radiusX * cos(angle) * cosine - radiusY * sin(angle) * sine,
                y: center.y + radiusX * cos(angle) * sine + radiusY * sin(angle) * cosine
            )
        }

        private func ellipseDerivative(
            radiusX: CGFloat,
            radiusY: CGFloat,
            rotation: CGFloat,
            angle: CGFloat
        ) -> CGPoint {
            let cosine = cos(rotation)
            let sine = sin(rotation)
            return CGPoint(
                x: -radiusX * sin(angle) * cosine - radiusY * cos(angle) * sine,
                y: -radiusX * sin(angle) * sine + radiusY * cos(angle) * cosine
            )
        }

        private func number''',
)

# Swift regression tests.
insert_before_final(
    "ios/Tests/NativeNavigationBarPluginTests/NativeNavigationTests.swift",
    r'''
        func testLiftedOverlayRestoresOriginalHierarchyAndConstraints() {
            let original = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            let destination = UIView(frame: original.frame)
            let overlay = UIView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            original.addSubview(overlay)
            let width = overlay.widthAnchor.constraint(equalToConstant: 100)
            let height = overlay.heightAnchor.constraint(equalToConstant: 80)
            NSLayoutConstraint.activate([width, height])
            var placements: [NativeNavigationWeakView] = []

            nativeNavigationLiftWebViewOverlaySubviews(
                from: original,
                to: destination,
                tracking: &placements
            )
            XCTAssertEqual(overlay.superview, destination)

            nativeNavigationRestoreLiftedViews(&placements)
            XCTAssertEqual(overlay.superview, original)
            XCTAssertFalse(overlay.translatesAutoresizingMaskIntoConstraints)
            XCTAssertTrue(width.isActive)
            XCTAssertTrue(height.isActive)
            XCTAssertTrue(placements.isEmpty)
        }

        func testSnapshotRendererScaleCapsLargeBitmapAllocations() {
            let fullScale = nativeNavigationSnapshotRendererScale(
                size: CGSize(width: 320, height: 640),
                displayScale: 3
            )
            let reducedScale = nativeNavigationSnapshotRendererScale(
                size: CGSize(width: 4_096, height: 4_096),
                displayScale: 3
            )

            XCTAssertEqual(fullScale, 3, accuracy: 0.001)
            XCTAssertLessThan(reducedScale, 1)
            XCTAssertGreaterThanOrEqual(reducedScale, 0.25)
        }

        func testSVGArcCommandProducesBezierCurves() {
            let path = SVGPathParser("M20 10 A10 10 0 0 1 10 20").parse()
            var curveCount = 0
            path.cgPath.applyWithBlock { element in
                if element.pointee.type == .addCurveToPoint {
                    curveCount += 1
                }
            }
            XCTAssertGreaterThan(curveCount, 0)
            XCTAssertEqual(path.currentPoint.x, 10, accuracy: 0.001)
            XCTAssertEqual(path.currentPoint.y, 20, accuracy: 0.001)
        }

        func testSVGStylePreservesOriginalFillAndStrokeColors() {
            var style = SVGRenderStyle()
            style.apply(["fill": "#ff0000", "stroke": "#0000ff"])
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(style.fillColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            XCTAssertEqual(red, 1, accuracy: 0.001)
            XCTAssertEqual(green, 0, accuracy: 0.001)
            XCTAssertEqual(blue, 0, accuracy: 0.001)
            XCTAssertTrue(style.strokeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            XCTAssertEqual(red, 0, accuracy: 0.001)
            XCTAssertEqual(blue, 1, accuracy: 0.001)
        }
    ''',
)

# Android shared Liquid Glass source snapshot.
write(
    "android/src/main/java/app/nativenavigationbar/capacitor/GlassBackdropView.java",
    r'''
    /* This Source Code Form is subject to the terms of the Mozilla Public
     * License, v. 2.0. If a copy of the MPL was not distributed with this
     * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

    package app.nativenavigationbar.capacitor;

    import android.content.Context;
    import android.graphics.Bitmap;
    import android.graphics.Canvas;
    import android.graphics.Color;
    import android.graphics.Paint;
    import android.graphics.Path;
    import android.graphics.RectF;
    import android.os.Build;
    import android.os.SystemClock;
    import android.view.View;
    import android.view.ViewTreeObserver;
    import androidx.annotation.RequiresApi;
    import java.util.Map;
    import java.util.WeakHashMap;

    /** Draws a shared, throttled WebView snapshot behind native glass surfaces. */
    final class GlassBackdropView extends View {

        interface PathProvider {
            Path path(int width, int height);
        }

        private static final long SOURCE_CONTENT_REFRESH_INTERVAL_MS = 250L;
        private static final int MAX_SHARED_SNAPSHOT_PIXELS = 8_388_608;
        private static final Map<View, SharedSourceFrame> SHARED_SOURCE_FRAMES = new WeakHashMap<>();

        private final Paint fallbackPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int[] sourceLocation = new int[2];
        private final int[] viewLocation = new int[2];
        private final ViewTreeObserver.OnScrollChangedListener sourceScrollListener = this::markDirty;
        private final ViewTreeObserver.OnPreDrawListener sourcePreDrawListener = () -> {
            markDirtyFromSourcePreDraw();
            return true;
        };
        private final View.OnLayoutChangeListener sourceLayoutListener = (
            view,
            left,
            top,
            right,
            bottom,
            oldLeft,
            oldTop,
            oldRight,
            oldBottom
        ) -> markDirty();
        private View source;
        private SharedSourceFrame sharedSourceFrame;
        private ViewTreeObserver observedTree;
        private boolean sourceObserversRegistered;
        private PathProvider clipPathProvider;
        private int fallbackColor = Color.TRANSPARENT;
        private boolean dirty;
        private boolean redrawPending;
        private long lastSourcePreDrawRefreshMs;

        GlassBackdropView(Context context) {
            super(context);
            setWillNotDraw(false);
        }

        void configure(View source, float blurRadiusPx, int fallbackColor) {
            this.fallbackColor = fallbackColor;
            attachSource(source);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Api31RenderEffects.setBlur(this, blurRadiusPx);
            }
            markDirty();
        }

        void clearEffect() {
            attachSource(null);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Api31RenderEffects.clear(this);
            }
            markDirty();
        }

        void setClipPathProvider(PathProvider clipPathProvider) {
            this.clipPathProvider = clipPathProvider;
            markDirty();
        }

        private void attachSource(View nextSource) {
            if (source == nextSource) {
                registerSourceObservers();
                return;
            }
            unregisterSourceObservers();
            releaseSharedFrame(source, sharedSourceFrame);
            source = nextSource;
            sharedSourceFrame = acquireSharedFrame(nextSource);
            registerSourceObservers();
            markDirty();
        }

        private static synchronized SharedSourceFrame acquireSharedFrame(View source) {
            if (source == null) {
                return null;
            }
            SharedSourceFrame frame = SHARED_SOURCE_FRAMES.get(source);
            if (frame == null) {
                frame = new SharedSourceFrame();
                SHARED_SOURCE_FRAMES.put(source, frame);
            }
            frame.references++;
            return frame;
        }

        private static synchronized void releaseSharedFrame(View source, SharedSourceFrame frame) {
            if (source == null || frame == null) {
                return;
            }
            frame.references = Math.max(0, frame.references - 1);
            if (frame.references == 0) {
                SHARED_SOURCE_FRAMES.remove(source);
                frame.recycle();
            }
        }

        static synchronized void clearSharedFramesForTests() {
            for (SharedSourceFrame frame : SHARED_SOURCE_FRAMES.values()) {
                frame.recycle();
            }
            SHARED_SOURCE_FRAMES.clear();
        }

        private void registerSourceObservers() {
            if (source == null || sourceObserversRegistered || !isAttachedToWindow()) {
                return;
            }
            source.addOnLayoutChangeListener(sourceLayoutListener);
            ViewTreeObserver observer = source.getViewTreeObserver();
            if (!observer.isAlive()) {
                source.removeOnLayoutChangeListener(sourceLayoutListener);
                return;
            }
            observer.addOnScrollChangedListener(sourceScrollListener);
            observer.addOnPreDrawListener(sourcePreDrawListener);
            observedTree = observer;
            sourceObserversRegistered = true;
        }

        private void unregisterSourceObservers() {
            if (source != null) {
                source.removeOnLayoutChangeListener(sourceLayoutListener);
            }
            if (observedTree != null && observedTree.isAlive()) {
                observedTree.removeOnScrollChangedListener(sourceScrollListener);
                observedTree.removeOnPreDrawListener(sourcePreDrawListener);
            }
            observedTree = null;
            sourceObserversRegistered = false;
        }

        @Override
        protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            registerSourceObservers();
        }

        @Override
        protected void onDetachedFromWindow() {
            unregisterSourceObservers();
            redrawPending = false;
            super.onDetachedFromWindow();
        }

        private void markDirty() {
            dirty = true;
            if (sharedSourceFrame != null) {
                sharedSourceFrame.dirty = true;
            }
            scheduleRedrawIfVisible();
        }

        private void markDirtyFromSourcePreDraw() {
            dirty = true;
            if (sharedSourceFrame != null) {
                sharedSourceFrame.dirty = true;
            }
            long now = SystemClock.uptimeMillis();
            if (now - lastSourcePreDrawRefreshMs < SOURCE_CONTENT_REFRESH_INTERVAL_MS) {
                return;
            }
            lastSourcePreDrawRefreshMs = now;
            scheduleRedrawIfVisible();
        }

        private void scheduleRedrawIfVisible() {
            if (redrawPending || getVisibility() != View.VISIBLE || !isShown()) {
                return;
            }
            redrawPending = true;
            postInvalidateOnAnimation();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            Path clipPath = clipPathProvider == null ? null : clipPathProvider.path(getWidth(), getHeight());
            if (clipPath == null) {
                drawSource(canvas);
            } else {
                int save = canvas.save();
                canvas.clipPath(clipPath);
                drawSource(canvas);
                canvas.restoreToCount(save);
            }
            dirty = false;
            redrawPending = false;
        }

        private void drawSource(Canvas canvas) {
            View currentSource = source;
            SharedSourceFrame currentFrame = sharedSourceFrame;
            if (currentSource == null || currentSource.getWidth() <= 0 || currentSource.getHeight() <= 0) {
                drawFallback(canvas);
                return;
            }
            if (currentFrame == null || !currentFrame.captureIfNeeded(currentSource)) {
                drawFallback(canvas);
                return;
            }
            currentSource.getLocationOnScreen(sourceLocation);
            getLocationOnScreen(viewLocation);
            float left = sourceLocation[0] - viewLocation[0];
            float top = sourceLocation[1] - viewLocation[1];
            RectF destination = new RectF(
                left,
                top,
                left + currentSource.getWidth(),
                top + currentSource.getHeight()
            );
            canvas.drawBitmap(currentFrame.bitmap, null, destination, currentFrame.paint);
        }

        private void drawFallback(Canvas canvas) {
            fallbackPaint.setColor(fallbackColor);
            canvas.drawRect(0, 0, getWidth(), getHeight(), fallbackPaint);
        }

        @Override
        protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
            super.onSizeChanged(width, height, oldWidth, oldHeight);
            if (width != oldWidth || height != oldHeight) {
                markDirty();
            }
        }

        @Override
        protected void onVisibilityChanged(View changedView, int visibility) {
            super.onVisibilityChanged(changedView, visibility);
            if (visibility != View.VISIBLE) {
                redrawPending = false;
                return;
            }
            if (dirty) {
                scheduleRedrawIfVisible();
            }
        }

        private static final class SharedSourceFrame {
            final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            Bitmap bitmap;
            boolean dirty = true;
            int references;
            int sourceWidth;
            int sourceHeight;

            boolean captureIfNeeded(View source) {
                if (!dirty && bitmap != null && !bitmap.isRecycled()
                    && sourceWidth == source.getWidth() && sourceHeight == source.getHeight()) {
                    return true;
                }
                int width = Math.max(1, source.getWidth());
                int height = Math.max(1, source.getHeight());
                long pixels = (long) width * height;
                float scale = pixels > MAX_SHARED_SNAPSHOT_PIXELS
                    ? (float) Math.sqrt(MAX_SHARED_SNAPSHOT_PIXELS / (double) pixels)
                    : 1f;
                int bitmapWidth = Math.max(1, Math.round(width * scale));
                int bitmapHeight = Math.max(1, Math.round(height * scale));
                try {
                    if (bitmap == null || bitmap.isRecycled()
                        || bitmap.getWidth() != bitmapWidth || bitmap.getHeight() != bitmapHeight) {
                        recycle();
                        bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
                    } else {
                        bitmap.eraseColor(Color.TRANSPARENT);
                    }
                    Canvas captureCanvas = new Canvas(bitmap);
                    captureCanvas.scale(scale, scale);
                    source.draw(captureCanvas);
                    sourceWidth = width;
                    sourceHeight = height;
                    dirty = false;
                    return true;
                } catch (OutOfMemoryError | RuntimeException ignored) {
                    recycle();
                    dirty = true;
                    return false;
                }
            }

            void recycle() {
                if (bitmap != null && !bitmap.isRecycled()) {
                    bitmap.recycle();
                }
                bitmap = null;
                sourceWidth = 0;
                sourceHeight = 0;
            }
        }

        @RequiresApi(Build.VERSION_CODES.S)
        private static final class Api31RenderEffects {
            static void setBlur(View view, float blurRadiusPx) {
                if (blurRadiusPx <= 0f) {
                    view.setRenderEffect(null);
                    return;
                }
                view.setRenderEffect(
                    android.graphics.RenderEffect.createBlurEffect(
                        blurRadiusPx,
                        blurRadiusPx,
                        android.graphics.Shader.TileMode.CLAMP
                    )
                );
            }

            static void clear(View view) {
                view.setRenderEffect(null);
            }
        }
    }
    ''',
)

write(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavbarActions.java",
    r'''
    package app.nativenavigationbar.capacitor;

    import android.content.Context;
    import android.graphics.drawable.Drawable;
    import android.view.Gravity;
    import android.view.View;
    import android.view.ViewGroup;
    import android.widget.TextView;
    import androidx.appcompat.widget.Toolbar;

    final class NativeNavbarActions {
        private NativeNavbarActions() {}

        static TextView addLeadingAction(
            Toolbar toolbar,
            String title,
            Drawable icon,
            boolean enabled,
            View.OnClickListener listener
        ) {
            Context context = toolbar.getContext();
            TextView action = new TextView(context);
            action.setGravity(Gravity.CENTER);
            action.setEnabled(enabled);
            action.setAlpha(enabled ? 1f : 0.38f);
            action.setMinWidth(dp(context, 48));
            action.setMinHeight(dp(context, 48));
            action.setPadding(dp(context, 10), 0, dp(context, 10), 0);
            action.setContentDescription(title);
            if (icon == null) {
                action.setText(title);
            } else {
                icon.setBounds(0, 0, dp(context, 24), dp(context, 24));
                action.setCompoundDrawablesRelative(icon, null, null, null);
            }
            action.setOnClickListener(listener);
            toolbar.addView(action, leadingLayoutParams());
            return action;
        }

        static Toolbar.LayoutParams leadingLayoutParams() {
            return new Toolbar.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.START | Gravity.CENTER_VERTICAL
            );
        }

        private static int dp(Context context, int value) {
            return Math.round(value * context.getResources().getDisplayMetrics().density);
        }
    }
    ''',
)

# Android plugin imports, fields and lifecycle.
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''import android.os.Build;''',
    '''import android.os.Build;
import android.os.Handler;
import android.os.Looper;''',
)
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''        .put("contentInsetMode", "css")
        .put("platformStyle", "auto");''',
    '''        .put("contentInsetMode", "css")
        .put("platformStyle", "auto")
        .put("manageEdgeToEdge", false);''',
)
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''    private final Map<Integer, Boolean> menuActionTemplates = new HashMap<>();''',
    '''    private final Map<Integer, Boolean> menuActionTemplates = new HashMap<>();
    private final List<View> navbarLeadingActionViews = new ArrayList<>();
    private final Map<View, Boolean> navbarLeadingActionTemplates = new HashMap<>();
    private boolean edgeToEdgeManaged;''',
)
replace_regex(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    r'''    @Override\n    public void load\(\) \{.*?\n    \}''',
    r'''
        @Override
        public void load() {
            runOnUiThread(this::observeContentRoot);
        }
    ''',
)
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''        runOnUiThread(() -> {
            Double requestedDuration = call.getDouble("animationDuration");''',
    '''        runOnUiThread(() -> {
            String requestedPlatformStyle = call.getString(
                "platformStyle",
                configState.optString("platformStyle", "auto")
            );
            if ("ios".equalsIgnoreCase(requestedPlatformStyle)) {
                call.reject("platformStyle 'ios' is not available on Android");
                return;
            }
            Double requestedDuration = call.getDouble("animationDuration");''',
)
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''            enabled = configState.optBoolean("enabled", true);
            contentInsetMode = "none".equals(configState.optString("contentInsetMode", "css")) ? "none" : "css";''',
    '''            enabled = configState.optBoolean("enabled", true);
            contentInsetMode = "none".equals(configState.optString("contentInsetMode", "css")) ? "none" : "css";
            updateManagedEdgeToEdge();''',
)
replace_regex(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    r'''            nativeToolbar\.getMenu\(\)\.clear\(\);.*?addToolbarItems\(nativeToolbar, arrayOrEmpty\(navbarState, "rightItems"\), "right"\);''',
    r'''
                nativeToolbar.getMenu().clear();
                clearToolbarLeadingItems(nativeToolbar);
                menuActionIds.clear();
                menuActionTitles.clear();
                menuActionPlacements.clear();
                menuActionTemplates.clear();

                JSONObject backButton = navbarState.optJSONObject("backButton");
                if (backButton != null && backButton.optBoolean("visible", false)) {
                    nativeToolbar.setNavigationIcon(androidx.appcompat.R.drawable.abc_ic_ab_back_material);
                    nativeToolbar.setNavigationContentDescription(backButton.optString("title", "Back"));
                    nativeToolbar.setNavigationOnClickListener(
                        view -> emitEvent("navbarBack", new JSObject().put("source", "navbar"))
                    );
                } else {
                    nativeToolbar.setNavigationIcon(null);
                    nativeToolbar.setNavigationOnClickListener(null);
                }
                addToolbarLeadingItems(nativeToolbar, arrayOrEmpty(navbarState, "leftItems"));
                addToolbarItems(nativeToolbar, arrayOrEmpty(navbarState, "rightItems"), "right");''',
)
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''        applyToolbarColors(nativeToolbar, colors);
        navbarContainer.setVisibility(View.VISIBLE);''',
    '''        applyToolbarColors(nativeToolbar, colors);
        applyToolbarLeadingTint();
        if (navbarState.optBoolean("transparent", false) && !navbarGlassOptions.isLiquidGlass()) {
            hideGlassBackground(navbarGlassBackdrop, navbarGlassSurface);
            navbarContainer.setBackgroundColor(Color.TRANSPARENT);
        }
        setChromeVisibility(
            navbarContainer,
            true,
            navbarState.optBoolean("animated", false)
        );''',
)
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''                navbarContainer.setVisibility(View.GONE);''',
    '''                setChromeVisibility(
                    navbarContainer,
                    false,
                    navbarState.optBoolean("animated", false)
                );''',
)
insert_before(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    "    private void addToolbarItems",
    r'''
        private void clearToolbarLeadingItems(Toolbar nativeToolbar) {
            for (View view : navbarLeadingActionViews) {
                nativeToolbar.removeView(view);
            }
            navbarLeadingActionViews.clear();
            navbarLeadingActionTemplates.clear();
        }

        private void addToolbarLeadingItems(Toolbar nativeToolbar, JSONArray rawItems) {
            for (int index = 0; index < rawItems.length(); index++) {
                JSONObject rawItem = rawItems.optJSONObject(index);
                if (rawItem == null) {
                    continue;
                }
                String id = rawItem.optString("id", "left-item-" + index);
                String title = rawItem.optString("title", "");
                JSONObject iconDescriptor = rawItem.optJSONObject("icon");
                Drawable icon = iconFrom(iconDescriptor);
                TextView action = NativeNavbarActions.addLeadingAction(
                    nativeToolbar,
                    title,
                    icon,
                    rawItem.optBoolean("enabled", true),
                    view -> {
                        JSObject event = new JSObject();
                        event.put("id", id);
                        event.put("title", title);
                        event.put("placement", "left");
                        emitEvent("navbarItemTap", event);
                    }
                );
                navbarLeadingActionViews.add(action);
                navbarLeadingActionTemplates.put(action, iconTemplate(iconDescriptor));
            }
        }

        private void applyToolbarLeadingTint() {
            for (View actionView : navbarLeadingActionViews) {
                if (!(actionView instanceof TextView)) {
                    continue;
                }
                TextView action = (TextView) actionView;
                action.setTextColor(tintColor);
                if (!Boolean.TRUE.equals(navbarLeadingActionTemplates.get(actionView))) {
                    continue;
                }
                for (Drawable drawable : action.getCompoundDrawablesRelative()) {
                    if (drawable != null) {
                        drawable.mutate().setTint(tintColor);
                    }
                }
            }
        }

        private void setChromeVisibility(View view, boolean visible, boolean animated) {
            if (view == null) {
                return;
            }
            view.animate().cancel();
            if (!animated) {
                view.setAlpha(1f);
                view.setVisibility(visible ? View.VISIBLE : View.GONE);
                return;
            }
            if (visible) {
                view.setAlpha(0f);
                view.setVisibility(View.VISIBLE);
                view.animate().alpha(1f).setDuration(180L).start();
            } else if (view.getVisibility() == View.VISIBLE) {
                view.animate().alpha(0f).setDuration(180L).withEndAction(() -> {
                    view.setVisibility(View.GONE);
                    view.setAlpha(1f);
                }).start();
            }
        }
    ''',
)
# Animate the main tab container on hide/show without touching child state.
replace_optional(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''                tabbarContainer.setVisibility(View.GONE);''',
    '''                setChromeVisibility(
                    tabbarContainer,
                    false,
                    tabbarState.optBoolean("animated", false)
                );''',
)
replace_optional(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''            tabbarContainer.setVisibility(View.VISIBLE);''',
    '''            setChromeVisibility(
                tabbarContainer,
                true,
                tabbarState.optBoolean("animated", false)
            );''',
)
# Replace UI-thread fallback and add edge-to-edge ownership helpers.
replace_regex(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    r'''    private void runOnUiThread\(Runnable runnable\) \{.*?\n    \}\n\}''',
    r'''
        private void updateManagedEdgeToEdge() {
            boolean shouldManage = enabled && configState.optBoolean("manageEdgeToEdge", false);
            if (shouldManage == edgeToEdgeManaged) {
                return;
            }
            Activity activity = getActivity();
            if (activity == null) {
                return;
            }
            activity.getWindow().setDecorFitsSystemWindows(!shouldManage);
            edgeToEdgeManaged = shouldManage;
        }

        private void restoreManagedEdgeToEdge() {
            if (!edgeToEdgeManaged) {
                return;
            }
            Activity activity = getActivity();
            if (activity != null) {
                activity.getWindow().setDecorFitsSystemWindows(true);
            }
            edgeToEdgeManaged = false;
        }

        private void runOnUiThread(Runnable runnable) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                runnable.run();
                return;
            }
            new Handler(Looper.getMainLooper()).post(runnable);
        }
    }
    ''',
)
replace_once(
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java",
    '''        hasReceivedWindowInsets = false;
        lastSystemInsets = Insets.NONE;''',
    '''        hasReceivedWindowInsets = false;
        lastSystemInsets = Insets.NONE;
        restoreManagedEdgeToEdge();''',
)

# Android instrumentation regressions.
write(
    "android/src/androidTest/java/app/nativenavigationbar/capacitor/NativeChromeInstrumentedTest.java",
    r'''
    package app.nativenavigationbar.capacitor;

    import static org.junit.Assert.assertEquals;
    import static org.junit.Assert.assertSame;
    import static org.junit.Assert.assertTrue;

    import android.content.Context;
    import android.graphics.Bitmap;
    import android.graphics.Canvas;
    import android.graphics.Color;
    import android.view.Gravity;
    import android.view.View;
    import android.widget.TextView;
    import androidx.appcompat.widget.Toolbar;
    import androidx.test.ext.junit.runners.AndroidJUnit4;
    import androidx.test.platform.app.InstrumentationRegistry;
    import org.junit.After;
    import org.junit.Test;
    import org.junit.runner.RunWith;

    @RunWith(AndroidJUnit4.class)
    public class NativeChromeInstrumentedTest {

        @After
        public void tearDown() {
            GlassBackdropView.clearSharedFramesForTests();
        }

        @Test
        public void leadingNavbarActionsUseTheToolbarStartSlot() {
            Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
            Toolbar toolbar = new Toolbar(context);
            TextView action = NativeNavbarActions.addLeadingAction(
                toolbar,
                "Leading",
                null,
                true,
                view -> {}
            );

            assertSame(toolbar, action.getParent());
            Toolbar.LayoutParams params = (Toolbar.LayoutParams) action.getLayoutParams();
            assertEquals(Gravity.START, params.gravity & Gravity.HORIZONTAL_GRAVITY_MASK);
            assertTrue(action.getMinimumWidth() > 0);
        }

        @Test
        public void twoGlassSurfacesReuseOneWebViewDrawForTheSameFrame() {
            Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
            CountingView source = new CountingView(context);
            source.layout(0, 0, 320, 640);
            GlassBackdropView first = new GlassBackdropView(context);
            GlassBackdropView second = new GlassBackdropView(context);
            first.layout(0, 0, 320, 80);
            second.layout(0, 0, 320, 80);
            first.configure(source, 0f, Color.WHITE);
            second.configure(source, 0f, Color.WHITE);

            Bitmap firstBitmap = Bitmap.createBitmap(320, 80, Bitmap.Config.ARGB_8888);
            Bitmap secondBitmap = Bitmap.createBitmap(320, 80, Bitmap.Config.ARGB_8888);
            first.draw(new Canvas(firstBitmap));
            second.draw(new Canvas(secondBitmap));

            assertEquals(1, source.drawCount);
            first.clearEffect();
            second.clearEffect();
            firstBitmap.recycle();
            secondBitmap.recycle();
        }

        private static final class CountingView extends View {
            int drawCount;

            CountingView(Context context) {
                super(context);
            }

            @Override
            public void draw(Canvas canvas) {
                drawCount++;
                super.draw(canvas);
            }
        }
    }
    ''',
)

# Documentation for the global Android behavior and custom-element errors.
replace_optional(
    "README.md",
    "- `load()` calls `Window.setDecorFitsSystemWindows(false)` so the native bars\n  can draw into the system bar areas. This applies to the whole activity.",
    "- The plugin no longer changes the Activity's edge-to-edge mode during `load()`. Configure edge-to-edge in the host app, or explicitly set `manageEdgeToEdge: true` when the plugin should temporarily own that global Window setting.",
)
replace_optional(
    "README.ja.md",
    "- `load()` calls `Window.setDecorFitsSystemWindows(false)` so the native bars\n  can draw into the system bar areas. This applies to the whole activity.",
    "- プラグインは `load()` 時に Activity 全体の edge-to-edge 設定を変更しません。ホストアプリ側で設定するか、プラグインに一時的な管理を任せる場合だけ `manageEdgeToEdge: true` を指定してください。",
)
replace_optional(
    "README.md",
    "Attribute writes made in the same task are coalesced into one native call.",
    "Attribute writes made in the same task are coalesced into one native call. Invalid JSON or rejected native updates preserve the last applied state and dispatch `nativeNavigationError` on the element plus `capNativeNavigation:error` on `window`.",
)

# CI: CocoaPods validation and real Android instrumentation on API 30.
replace_once(
    ".github/workflows/ci.yml",
    '''      - name: Build (generic iOS destination)
        run: xcodebuild -scheme CapacitorNativeNavigationBar -destination "generic/platform=iOS" build''',
    '''      - name: Validate CocoaPods integration
        run: pod lib lint CapacitorNativeNavigationBar.podspec --allow-warnings --skip-import-validation
      - name: Build (generic iOS destination)
        run: xcodebuild -scheme CapacitorNativeNavigationBar -destination "generic/platform=iOS" build''',
)
with (ROOT / ".github/workflows/ci.yml").open("a", encoding="utf-8") as handle:
    handle.write(textwrap.dedent(r'''

      android-instrumentation:
        name: Android API 30 instrumentation
        runs-on: ubuntu-latest
        timeout-minutes: 30
        steps:
          - uses: actions/checkout@v7
          - uses: pnpm/action-setup@v6
            with:
              version: 11.9.0
          - uses: actions/setup-node@v7
            with:
              node-version-file: ".node-version"
              cache: pnpm
          - run: pnpm install --frozen-lockfile
          - uses: actions/setup-java@v5
            with:
              distribution: temurin
              java-version: "21"
          - uses: reactivecircus/android-emulator-runner@v2
            with:
              api-level: 30
              arch: x86_64
              disable-animations: true
              script: |
                cd android
                echo "sdk.dir=$ANDROID_HOME" > local.properties
                chmod +x gradlew
                ./gradlew connectedDebugAndroidTest --no-daemon
    '''))

print("phase 2 native transformations completed")
