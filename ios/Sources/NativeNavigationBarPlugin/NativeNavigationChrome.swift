/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details.
 *
 * Native chrome primitives: the floating/curve tab bar, its background
 * geometry, the hit-slop containers and the tab-hosting view controllers used
 * by the system Liquid Glass path. Split out of the single upstream file so the
 * plugin entry point stays readable; the behavior is unchanged. */

import UIKit

// MARK: - Tabbar model

struct NativeNavigationFloatingTabItem {
    let id: String
    let title: String
    let accessibilityTitle: String
    let image: UIImage?
    let selectedImage: UIImage?
    let badge: String?
    let enabled: Bool
    let isDetachedTrailing: Bool
    let sourceIndex: Int
}

enum NativeNavigationTabbarShape {
    case floating
    case curve
}

struct NativeNavigationTabbarStyleConfig {
    var shape: NativeNavigationTabbarShape = .floating
    var height: CGFloat = 64
    var horizontalMargin: CGFloat = 24
    var maxWidth: CGFloat = 430
    var bottomGap: CGFloat = 10
    var cornerRadius: CGFloat = 32
    var centerItemId: String?
    var centerButtonDiameter: CGFloat = 56
    var centerButtonLift: CGFloat = 28
    var centerButtonColor: UIColor?
    var centerButtonIconColor: UIColor = .white

    var barTop: CGFloat {
        shape == .curve ? centerButtonLift : 0
    }

    var totalHeight: CGFloat {
        height + barTop
    }
}

struct NativeNavigationFloatingTabStyle {
    let selected: Bool
    let labels: Bool
    let icons: Bool
    let isCenter: Bool
    let isDetachedTrailing: Bool
    let selectedTint: UIColor
    let inactiveTint: UIColor
    let centerButtonColor: UIColor
    let centerButtonIconColor: UIColor
    let badgeBackgroundColor: UIColor
    let badgeTextColor: UIColor
}


// MARK: - Background geometry

enum NativeNavigationTabbarBackgroundPath {
    static func path(in bounds: CGRect, style: NativeNavigationTabbarStyleConfig) -> UIBezierPath {
        guard style.shape == .curve else {
            return UIBezierPath(roundedRect: bounds, cornerRadius: style.cornerRadius)
        }

        let barRect = CGRect(x: 0, y: style.barTop, width: bounds.width, height: max(style.height, 1))
        let cornerRadius = min(style.cornerRadius, barRect.height / 2)
        let centerX = bounds.midX
        let centerRadius = style.centerButtonDiameter / 2
        let centerTop = max(0, barRect.minY - style.centerButtonLift)
        let centerY = centerTop + centerRadius
        let dyToBarTop = barRect.minY - centerY
        let shoulderWidth = sqrt(max(0, centerRadius * centerRadius - dyToBarTop * dyToBarTop))
        let leftShoulder = max(barRect.minX + cornerRadius, centerX - shoulderWidth)
        let startAngle = atan2(dyToBarTop, -shoulderWidth)
        var endAngle = atan2(dyToBarTop, shoulderWidth)
        if endAngle <= startAngle {
            endAngle += .pi * 2
        }
        let path = UIBezierPath()

        path.move(to: CGPoint(x: barRect.minX + cornerRadius, y: barRect.minY))
        path.addLine(to: CGPoint(x: leftShoulder, y: barRect.minY))
        if shoulderWidth > 0 {
            path.addArc(
                withCenter: CGPoint(x: centerX, y: centerY),
                radius: centerRadius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
        }
        path.addLine(to: CGPoint(x: barRect.maxX - cornerRadius, y: barRect.minY))
        path.addQuadCurve(
            to: CGPoint(x: barRect.maxX, y: barRect.minY + cornerRadius),
            controlPoint: CGPoint(x: barRect.maxX, y: barRect.minY)
        )
        path.addLine(to: CGPoint(x: barRect.maxX, y: barRect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: barRect.maxX - cornerRadius, y: barRect.maxY),
            controlPoint: CGPoint(x: barRect.maxX, y: barRect.maxY)
        )
        path.addLine(to: CGPoint(x: barRect.minX + cornerRadius, y: barRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: barRect.minX, y: barRect.maxY - cornerRadius),
            controlPoint: CGPoint(x: barRect.minX, y: barRect.maxY)
        )
        path.addLine(to: CGPoint(x: barRect.minX, y: barRect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: barRect.minX + cornerRadius, y: barRect.minY),
            controlPoint: CGPoint(x: barRect.minX, y: barRect.minY)
        )
        path.close()
        return path
    }
}

final class NativeNavigationTabbarBackgroundView: UIView {
    var style = NativeNavigationTabbarStyleConfig() {
        didSet { setNeedsDisplay() }
    }
    var fillColor = UIColor.systemBackground.withAlphaComponent(0.46) {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        fillColor.setFill()
        NativeNavigationTabbarBackgroundPath.path(in: bounds, style: style).fill()
    }
}

// MARK: - Floating tab bar

final class NativeNavigationFloatingTabBar: UIView {
    private var items: [NativeNavigationFloatingTabItem] = []
    private var buttons: [NativeNavigationFloatingTabButton] = []
    private var labelVisibilityMode = "labeled"
    private var iconsVisible = true
    private let backgroundShapeView = NativeNavigationTabbarBackgroundView()
    private var tabbarStyle = NativeNavigationTabbarStyleConfig()

    var selectedIndex = 0
    var selectedTintColor = UIColor.systemBlue {
        didSet { updateButtons() }
    }
    var inactiveTintColor = UIColor.secondaryLabel {
        didSet { updateButtons() }
    }
    var badgeBackgroundColor = UIColor.systemRed {
        didSet { updateButtons() }
    }
    var badgeTextColor = UIColor.white {
        didSet { updateButtons() }
    }
    var backgroundFillColor = UIColor.systemBackground.withAlphaComponent(0.46) {
        didSet {
            backgroundShapeView.fillColor = backgroundFillColor
        }
    }
    var onSelect: ((Int, NativeNavigationFloatingTabItem) -> Void)?

    var hasDetachedTrailing: Bool {
        tabbarStyle.shape == .floating && items.contains(where: \.isDetachedTrailing)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundShapeView.isUserInteractionEnabled = false
        backgroundShapeView.fillColor = backgroundFillColor
        addSubview(backgroundShapeView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        items: [NativeNavigationFloatingTabItem],
        selectedIndex: Int,
        labelVisibilityMode: String,
        icons: Bool,
        style: NativeNavigationTabbarStyleConfig
    ) {
        self.items = items
        self.labelVisibilityMode = labelVisibilityMode
        self.iconsVisible = icons
        self.tabbarStyle = style
        self.selectedIndex = items.indices.contains(selectedIndex) ? selectedIndex : 0
        backgroundShapeView.style = style
        rebuildButtons()
        setNeedsLayout()
    }

    func capsuleBounds(in bounds: CGRect) -> CGRect {
        guard hasDetachedTrailing else {
            return bounds
        }
        let trailingGap: CGFloat = 10
        let trailingDiameter = tabbarStyle.height
        let capsuleWidth = max(0, bounds.width - trailingDiameter - trailingGap)
        return CGRect(x: bounds.minX, y: bounds.minY, width: capsuleWidth, height: bounds.height)
    }

    func trailingActionBounds(in bounds: CGRect) -> CGRect? {
        guard hasDetachedTrailing else {
            return nil
        }
        let trailingDiameter = tabbarStyle.height
        return CGRect(
            x: bounds.maxX - trailingDiameter,
            y: bounds.minY + (bounds.height - trailingDiameter) / 2,
            width: trailingDiameter,
            height: trailingDiameter
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let capsule = capsuleBounds(in: bounds)
        backgroundShapeView.frame = capsule
        guard !buttons.isEmpty else {
            return
        }

        if let centerIndex = centerButtonIndex(), buttons.indices.contains(centerIndex) {
            let buttonDiameter = tabbarStyle.centerButtonDiameter
            let centerGap = min(buttonDiameter + 4, bounds.width * 0.34)
            let barFrame = CGRect(x: 0, y: tabbarStyle.barTop, width: bounds.width, height: tabbarStyle.height)
            let leftWidth = max(0, bounds.midX - centerGap / 2)
            let rightX = min(bounds.width, bounds.midX + centerGap / 2)
            let centerFrame = CGRect(
                x: bounds.midX - buttonDiameter / 2,
                y: max(0, tabbarStyle.barTop - tabbarStyle.centerButtonLift),
                width: buttonDiameter,
                height: buttonDiameter
            )

            buttons[centerIndex].frame = centerFrame
            layoutButtons(Array(0..<centerIndex), in: CGRect(x: 0, y: barFrame.minY, width: leftWidth, height: barFrame.height))
            layoutButtons(
                Array((centerIndex + 1)..<buttons.count),
                in: CGRect(x: rightX, y: barFrame.minY, width: bounds.width - rightX, height: barFrame.height)
            )
            return
        }

        if let trailingIndex = detachedTrailingIndex(),
           buttons.indices.contains(trailingIndex),
           let trailingBounds = trailingActionBounds(in: bounds) {
            buttons[trailingIndex].frame = trailingBounds
            let mainIndices = buttons.indices.filter { $0 != trailingIndex }
            layoutButtons(mainIndices, in: capsule)
            return
        }

        layoutButtons(Array(buttons.indices), in: bounds)
    }

    private func layoutButtons(_ indices: [Int], in rect: CGRect) {
        guard !indices.isEmpty else {
            return
        }
        let itemWidth = rect.width / CGFloat(indices.count)
        for (position, index) in indices.enumerated() where buttons.indices.contains(index) {
            buttons[index].frame = CGRect(
                x: rect.minX + CGFloat(position) * itemWidth,
                y: rect.minY,
                width: itemWidth,
                height: rect.height
            )
        }
    }

    private func centerButtonIndex() -> Int? {
        guard tabbarStyle.shape == .curve, !items.isEmpty else {
            return nil
        }
        if let centerItemId = tabbarStyle.centerItemId,
           let index = items.firstIndex(where: { $0.id == centerItemId }) {
            return index
        }
        return items.count / 2
    }

    private func detachedTrailingIndex() -> Int? {
        guard tabbarStyle.shape == .floating else {
            return nil
        }
        return items.lastIndex(where: \.isDetachedTrailing)
    }

    private func rebuildButtons() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = items.enumerated().map { index, item in
            let button = NativeNavigationFloatingTabButton()
            button.tag = index
            button.configure(
                item: item,
                style: style(for: index)
            )
            button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
            addSubview(button)
            return button
        }
    }

    private func updateButtons() {
        for (index, button) in buttons.enumerated() {
            guard items.indices.contains(index) else {
                continue
            }
            button.configure(
                item: items[index],
                style: style(for: index)
            )
        }
    }

    private func style(for index: Int) -> NativeNavigationFloatingTabStyle {
        let isCenter = centerButtonIndex() == index
        let isDetachedTrailing = detachedTrailingIndex() == index
        // Detached actions stay icon-only when icons are available; fall back to
        // a label when icons are disabled so the control remains discoverable.
        let detachedShowsLabel = isDetachedTrailing && !iconsVisible && showsLabel(for: index)
        return NativeNavigationFloatingTabStyle(
            selected: index == selectedIndex,
            labels: isDetachedTrailing ? detachedShowsLabel : showsLabel(for: index),
            icons: iconsVisible,
            isCenter: isCenter,
            isDetachedTrailing: isDetachedTrailing,
            selectedTint: selectedTintColor,
            inactiveTint: inactiveTintColor,
            centerButtonColor: tabbarStyle.centerButtonColor ?? selectedTintColor,
            centerButtonIconColor: tabbarStyle.centerButtonIconColor,
            badgeBackgroundColor: badgeBackgroundColor,
            badgeTextColor: badgeTextColor
        )
    }

    private func showsLabel(for index: Int) -> Bool {
        switch labelVisibilityMode {
        case "unlabeled":
            return false
        case "selected":
            return index == selectedIndex
        case "auto":
            let compact = traitCollection.horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone
            return !compact || index == selectedIndex
        default:
            return true
        }
    }

    @objc private func handleTap(_ sender: NativeNavigationFloatingTabButton) {
        let index = sender.tag
        guard items.indices.contains(index), items[index].enabled else {
            return
        }
        selectedIndex = index
        updateButtons()
        onSelect?(index, items[index])
    }
}

final class NativeNavigationFloatingTabButton: UIControl {
    private let selectedView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let badgeLabel = UILabel()
    private var hasIcon = true
    private var hasLabel = true
    private var isCenterButton = false
    private var badgeText: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true

        selectedView.isUserInteractionEnabled = false
        selectedView.alpha = 0
        addSubview(selectedView)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        badgeLabel.textAlignment = .center
        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .systemRed
        badgeLabel.layer.masksToBounds = true
        badgeLabel.isUserInteractionEnabled = false
        addSubview(badgeLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        item: NativeNavigationFloatingTabItem,
        style: NativeNavigationFloatingTabStyle
    ) {
        isEnabled = item.enabled
        alpha = item.enabled ? 1 : 0.38
        isCenterButton = style.isCenter
        let isDetachedTrailing = style.isDetachedTrailing
        hasIcon = style.icons && (item.image != nil || item.selectedImage != nil)
        hasLabel = isDetachedTrailing
            ? (!hasIcon && style.labels && !item.title.isEmpty)
            : (style.isCenter ? (!hasIcon && !item.title.isEmpty) : (style.labels && !item.title.isEmpty))
        badgeText = item.badge

        let color = style.isCenter
            ? style.centerButtonIconColor
            : (style.selected ? style.selectedTint : style.inactiveTint)
        selectedView.backgroundColor = style.isCenter
            ? style.centerButtonColor
            : style.selectedTint.withAlphaComponent(style.selected && !isDetachedTrailing ? 0.16 : 0)
        selectedView.alpha = style.isCenter || (style.selected && !isDetachedTrailing) ? 1 : 0

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = style.isCenter ? 0.2 : 0
        layer.shadowRadius = style.isCenter ? 14 : 0
        layer.shadowOffset = CGSize(width: 0, height: 8)

        let image = style.selected ? (item.selectedImage ?? item.image) : item.image
        imageView.image = image
        imageView.tintColor = color
        imageView.isHidden = !hasIcon

        titleLabel.text = item.title
        titleLabel.textColor = color
        titleLabel.font = .systemFont(ofSize: style.isCenter ? 12 : 11, weight: style.selected ? .bold : .semibold)
        titleLabel.isHidden = !hasLabel

        badgeLabel.text = item.badge
        badgeLabel.textColor = style.badgeTextColor
        badgeLabel.backgroundColor = style.badgeBackgroundColor
        badgeLabel.isHidden = item.badge == nil || item.badge == "0"
        accessibilityLabel = item.accessibilityTitle
        accessibilityTraits = style.selected ? [.button, .selected] : .button
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isCenterButton {
            selectedView.frame = bounds
        } else {
            let selectedSize: CGFloat = 58
            selectedView.frame = CGRect(
                x: (bounds.width - selectedSize) / 2,
                y: (bounds.height - selectedSize) / 2,
                width: selectedSize,
                height: selectedSize
            )
        }
        selectedView.layer.cornerRadius = selectedView.bounds.height / 2

        let iconSize: CGFloat = isCenterButton ? 32 : 23
        if isCenterButton || (!hasLabel && hasIcon && bounds.width <= bounds.height + 1) {
            if hasIcon {
                imageView.frame = CGRect(
                    x: (bounds.width - iconSize) / 2,
                    y: (bounds.height - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
                titleLabel.frame = .zero
            } else {
                imageView.frame = .zero
                titleLabel.frame = CGRect(x: 8, y: (bounds.height - 18) / 2, width: bounds.width - 16, height: 18)
            }
        } else if hasIcon && hasLabel {
            imageView.frame = CGRect(x: (bounds.width - iconSize) / 2, y: 10, width: iconSize, height: iconSize)
            titleLabel.frame = CGRect(x: 5, y: bounds.height - 23, width: bounds.width - 10, height: 15)
        } else if hasIcon {
            imageView.frame = CGRect(
                x: (bounds.width - iconSize) / 2,
                y: (bounds.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            titleLabel.frame = .zero
        } else {
            imageView.frame = .zero
            titleLabel.frame = CGRect(x: 5, y: (bounds.height - 18) / 2, width: bounds.width - 10, height: 18)
        }

        let badgeHeight: CGFloat = 18
        let badgeWidth = max(badgeHeight, CGFloat((badgeText ?? "").count * 7 + 11))
        let anchor = hasIcon ? imageView.frame : CGRect(x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20)
        badgeLabel.frame = CGRect(
            x: min(bounds.width - badgeWidth - 8, anchor.midX + 7),
            y: max(6, anchor.minY - 6),
            width: badgeWidth,
            height: badgeHeight
        )
        badgeLabel.layer.cornerRadius = badgeHeight / 2
    }
}

// MARK: - Hit-slop containers

final class NativeNavigationChromeContainer: UIView {
    var hitSlop = UIEdgeInsets.zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.inset(by: UIEdgeInsets(
            top: -hitSlop.top,
            left: -hitSlop.left,
            bottom: -hitSlop.bottom,
            right: -hitSlop.right
        ))
        return expandedBounds.contains(point)
    }
}

final class NativeNavigationBar: UINavigationBar {
    var hitSlop = UIEdgeInsets.zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.inset(by: UIEdgeInsets(
            top: -hitSlop.top,
            left: -hitSlop.left,
            bottom: -hitSlop.bottom,
            right: -hitSlop.right
        ))
        return expandedBounds.contains(point)
    }
}

// MARK: - WebView overlay lifting

final class NativeNavigationWeakView {
    weak var value: UIView?

    init(_ value: UIView) {
        self.value = value
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
            let frame = overlay.convert(overlay.bounds, to: container)
            let hadParentConstraints = nativeNavigationDeactivateParentConstraints(in: webView, involving: overlay)
            overlay.removeFromSuperview()
            overlay.frame = frame
            if hadParentConstraints {
                overlay.translatesAutoresizingMaskIntoConstraints = true
            }
            overlay.autoresizingMask = overlay.autoresizingMask.isEmpty
                ? [.flexibleWidth, .flexibleHeight]
                : overlay.autoresizingMask
            container.addSubview(overlay)
            liftedOverlays.append(NativeNavigationWeakView(overlay))
        }

    liftedOverlays = liftedOverlays.filter { $0.value != nil }
    liftedOverlays
        .compactMap(\.value)
        .filter { $0.superview === container }
        .forEach { container.bringSubviewToFront($0) }
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

private func nativeNavigationDeactivateParentConstraints(in parent: UIView, involving view: UIView) -> Bool {
    let constraints = parent.constraints.filter { constraint in
        constraint.firstItem === view || constraint.secondItem === view
    }
    NSLayoutConstraint.deactivate(constraints)
    return !constraints.isEmpty
}

// MARK: - System tab hosting

final class NativeNavigationTabController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.isOpaque = true
        tabBar.isTranslucent = !UIAccessibility.isReduceTransparencyEnabled
    }
}

final class NativeNavigationTabContentController: UIViewController {
    private weak var hostedWebView: UIView?
    private var snapshotPlaceholder: UIView?

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.isOpaque = true
        self.view = view
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard hostedWebView?.superview === view else {
            hostedWebView = nil
            return
        }
        hostedWebView?.frame = view.bounds
    }

    func clearHostedWebView(ifMatching webView: UIView? = nil, preservingSnapshot: Bool = false) {
        guard webView == nil || hostedWebView === webView else {
            return
        }

        if preservingSnapshot, let hostedWebView = hostedWebView, hostedWebView.superview === view {
            let placeholder = hostedWebView.snapshotView(afterScreenUpdates: false)
                ?? nativeNavigationSnapshotPlaceholder(for: hostedWebView)
            placeholder.frame = hostedWebView.frame
            placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshotPlaceholder?.removeFromSuperview()
            view.insertSubview(placeholder, belowSubview: hostedWebView)
            snapshotPlaceholder = placeholder
        }

        hostedWebView = nil
    }

    @discardableResult
    func host(webView: UIView) -> Bool {
        guard view !== webView, !view.isDescendant(of: webView) else {
            hostedWebView = nil
            return false
        }

        snapshotPlaceholder?.removeFromSuperview()
        snapshotPlaceholder = nil
        hostedWebView = webView
        if webView.superview !== view {
            webView.removeFromSuperview()
            view.addSubview(webView)
        }
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.frame = view.bounds
        return true
    }
}

// MARK: - Transition helpers

func nativeNavigationFallbackBackground(for view: UIView) -> UIColor {
    if let color = view.backgroundColor,
       color.cgColor.alpha > 0 {
        return color.withAlphaComponent(1)
    }
    return UIColor.systemBackground.withAlphaComponent(1.0)
}

func nativeNavigationUsesStationaryTransitionCrossfade(direction: String) -> Bool {
    direction == "tab" || direction == "root" || direction == "none"
}

func nativeNavigationNeedsTransitionSurface(_ color: UIColor?) -> Bool {
    guard let color else {
        return true
    }
    return color.cgColor.alpha < 1
}

func nativeNavigationSnapshotPlaceholder(for view: UIView) -> UIView {
    let placeholder = UIView(frame: view.frame)
    placeholder.backgroundColor = nativeNavigationFallbackBackground(for: view)
    placeholder.isOpaque = true
    return placeholder
}
