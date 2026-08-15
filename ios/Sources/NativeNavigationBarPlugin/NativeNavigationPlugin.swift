/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

// swiftlint:disable file_length

import Capacitor
import CoreFoundation
import Foundation
import ObjectiveC
import UIKit

private let nativeNavigationMaximumDurationMilliseconds = 60_000.0
private let nativeNavigationMaximumLayoutDimension: CGFloat = 4_096
private let nativeNavigationMaximumDecodedSVGBytes = 256 * 1_024
private let nativeNavigationMaximumBase64SVGCharacters =
    ((nativeNavigationMaximumDecodedSVGBytes + 2) / 3) * 4 + 4
private let nativeNavigationMaximumPercentEncodedSVGCharacters =
    nativeNavigationMaximumDecodedSVGBytes * 3

func nativeNavigationMeasuredNavigationBarHeight(_ navBar: UINavigationBar, width: CGFloat) -> CGFloat {
    let safeWidth = width.isFinite && width > 0 ? min(width, nativeNavigationMaximumLayoutDimension) : 320
    if navBar.frame.width != safeWidth {
        navBar.frame.size.width = safeWidth
    }
    navBar.setNeedsLayout()
    navBar.layoutIfNeeded()
    let fittingHeight = navBar.sizeThatFits(
        CGSize(width: safeWidth, height: UIView.layoutFittingCompressedSize.height)
    ).height
    let autoLayoutHeight = navBar.systemLayoutSizeFitting(
        CGSize(width: safeWidth, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
    ).height
    let intrinsicHeight = max(navBar.intrinsicContentSize.height, 0)
    let measuredHeight = [fittingHeight, autoLayoutHeight, intrinsicHeight]
        .filter { $0.isFinite && $0 > 0 }
        .max() ?? 44
    return min(max(ceil(measuredHeight), 44), nativeNavigationMaximumLayoutDimension)
}

func nativeNavigationIsSafeTransitionRect(_ rect: CGRect) -> Bool {
    rect.origin.x.isFinite
        && rect.origin.y.isFinite
        && rect.width.isFinite
        && rect.height.isFinite
        && abs(rect.origin.x) <= nativeNavigationMaximumLayoutDimension
        && abs(rect.origin.y) <= nativeNavigationMaximumLayoutDimension
        && rect.width > 0
        && rect.height > 0
        && rect.width <= nativeNavigationMaximumLayoutDimension
        && rect.height <= nativeNavigationMaximumLayoutDimension
}

func nativeNavigationFiniteDouble(_ value: Any?) -> Double? {
    if let value = value as? NSNumber {
        guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
            return nil
        }
        let number = value.doubleValue
        return number.isFinite ? number : nil
    }
    if let value = value as? String,
       let number = Double(value),
       number.isFinite {
        return number
    }
    return nil
}

func nativeNavigationDurationMilliseconds(_ value: Any?, fallback: Double) -> Int? {
    let duration = value == nil ? fallback : nativeNavigationFiniteDouble(value)
    guard let duration,
          duration.isFinite,
          duration >= 0,
          duration <= nativeNavigationMaximumDurationMilliseconds else {
        return nil
    }
    return Int(duration.rounded())
}

func nativeNavigationTransitionIdentifier(
    explicitId: String?,
    timestampMilliseconds: Int64,
    generation: UInt64
) -> String {
    explicitId ?? "transition-\(timestampMilliseconds)-\(generation)"
}

func nativeNavigationClampedUnitInterval(_ value: Any?, fallback: CGFloat) -> CGFloat {
    let safeFallback = fallback.isFinite ? fallback : 0.62
    guard let value = nativeNavigationFiniteDouble(value) else {
        return min(max(safeFallback, 0), 1)
    }
    return CGFloat(min(max(value, 0), 1))
}

func nativeNavigationMergeOptions(
    current: [String: Any],
    patch: [String: Any],
    nestedKeys: Set<String>
) -> [String: Any] {
    var result = current
    for (key, value) in patch {
        if value is NSNull {
            result.removeValue(forKey: key)
            continue
        }
        if nestedKeys.contains(key),
           let next = value as? [String: Any] {
            let previous = result[key] as? [String: Any] ?? [:]
            result[key] = nativeNavigationMergeOptions(current: previous, patch: next, nestedKeys: [])
        } else {
            result[key] = value
        }
    }
    return result
}

func nativeNavigationEffectiveBarOptions(
    configure: [String: Any],
    bar: [String: Any]
) -> [String: Any] {
    var result = bar
    for key in ["colors", "glass"] {
        let shared = configure[key] as? [String: Any] ?? [:]
        let override = bar[key] as? [String: Any] ?? [:]
        if !shared.isEmpty || !override.isEmpty {
            result[key] = nativeNavigationMergeOptions(current: shared, patch: override, nestedKeys: [])
        }
    }
    return result
}

private struct NativeNavigationOptions {
    let values: [String: Any]

    func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        if let value = values[key] as? Bool {
            return value
        }
        if let value = values[key] as? NSNumber {
            return value.boolValue
        }
        return defaultValue
    }

    func string(_ key: String) -> String? {
        values[key] as? String
    }

    func object(_ key: String) -> [String: Any]? {
        values[key] as? [String: Any]
    }

    func array(_ key: String) -> [[String: Any]]? {
        values[key] as? [[String: Any]]
    }
}

private final class NativeNavigationTransitionSession {
    let generation: UInt64
    let id: String
    let webView: UIView
    var direction: String
    var durationMs: Int
    var snapshot: UIView?
    var zoomSourceFrame: CGRect?
    var cornerRadius: CGFloat
    var watchdog: DispatchWorkItem?
    var watchdogGeneration: UInt64 = 0
    var finishResolver: (([String: Any]) -> Void)?
    var isFinishing = false
    var didEmitEnd = false
    var didResolveFinish = false

    init(
        generation: UInt64,
        id: String,
        direction: String,
        durationMs: Int,
        webView: UIView,
        snapshot: UIView?,
        zoomSourceFrame: CGRect?,
        cornerRadius: CGFloat
    ) {
        self.generation = generation
        self.id = id
        self.direction = direction
        self.durationMs = durationMs
        self.webView = webView
        self.snapshot = snapshot
        self.zoomSourceFrame = zoomSourceFrame
        self.cornerRadius = cornerRadius
    }
}

private struct NativeNavigationTransitionContext {
    let session: NativeNavigationTransitionSession
    let webView: UIView
    let snapshot: UIView?
    let id: String
    let direction: String
    let duration: TimeInterval
    let durationMs: Int
}

private struct NativeNavigationZoomTransitionContext {
    let transition: NativeNavigationTransitionContext
    let sourceFrame: CGRect?
    let targetFrame: CGRect?
    let cornerRadius: CGFloat
}

// swiftlint:disable type_body_length
@objc(NativeNavigationPlugin)
public class NativeNavigationPlugin: CAPPlugin, CAPBridgedPlugin, UITabBarControllerDelegate, UITabBarDelegate {
    public let identifier = "NativeNavigationPlugin"
    public let jsName = "NativeNavigation"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "configure", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setNavbar", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTabbar", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "beginTransition", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "finishTransition", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]

    private let implementation = NativeNavigation()
    private var navContainer: UIView?
    private var navBlurView: UIVisualEffectView?
    private var navBar: UINavigationBar?
    private var tabContainer: UIView?
    private var tabEffectView: UIVisualEffectView?
    private var trailingTabEffectView: UIVisualEffectView?
    private var tabBar: UITabBar?
    private var floatingTabBar: NativeNavigationFloatingTabBar?
    private var tabbarStyle = NativeNavigationTabbarStyleConfig()
    private var tabBarController: NativeNavigationTabController?
    private var tabViewControllers: [UIViewController] = []
    private weak var systemTabRootContainer: UIView?
    private weak var originalWebViewSuperview: UIView?
    private var originalWebViewIndex: Int?
    private var originalWebViewAutoresizingMask: UIView.AutoresizingMask?
    private var liftedWebViewOverlays: [NativeNavigationWeakView] = []
    private var isWebViewHostedInSystemTabController = false
    private var navbarHeight: CGFloat = 44
    private var tabbarHeight: CGFloat = NativeNavigationTabbarStyleConfig().totalHeight
    private var navbarVisible = false
    private var tabbarVisible = false
    private var contentInsetMode = "css"
    private var isEnabled = true
    private var defaultTransitionDuration: TimeInterval = 0.35
    private var navbarItemPlacement: [String: String] = [:]
    private var navbarItemTitle: [String: String] = [:]
    private var tabIds: [String] = []
    private var tabTitles: [String] = []
    private var tabDisplayTitles: [String?] = []
    private var tabBaseImages: [UIImage?] = []
    private var tabSelectedImages: [UIImage?] = []
    private var suppressTabSelectEvent = false
    private var configureState: [String: Any] = [
        "enabled": true,
        "contentInsetMode": "css"
    ]
    private var navbarState: [String: Any] = [:]
    private var tabbarState: [String: Any] = [:]
    private var hasNavbarState = false
    private var hasTabbarState = false
    private var navbarUsesLiquidGlass = false
    private var isUsingSystemTabBar = false
    private var transitionGeneration: UInt64 = 0
    private var activeTransitionSession: NativeNavigationTransitionSession?
    private weak var activeTransitionContainer: UIView?
    private var activeTransitionContainerBackgroundColor: UIColor?
    private var activeTransitionContainerWasOpaque = false
    private var activeTransitionContainerBackgroundCaptured = false
    private var generatesOrientationNotifications = false
    private var usesSystemLiquidGlass: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    override public func load() {
        // `UIDevice.orientationDidChangeNotification` is only posted while the
        // device is generating orientation notifications. UIKit usually turns
        // that on for us, but it is not contractual, so take an explicit
        // interest and give it back in `deinit`. begin/end are reference
        // counted, so this is taken unconditionally: skipping it when someone
        // else already holds a reference would leave this plugin without one,
        // and rotation would stop being delivered the moment they release it.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        generatesOrientationNotifications = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleLayoutChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleKeyboardFrameChange),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleKeyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleReduceTransparencyChange),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        // If the app is backgrounded mid-transition, nothing the user is
        // watching matters anymore, so force-complete it immediately rather
        // than leaving the WebView at alpha 0.01 for whenever the process
        // happens to resume.
        center.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        activeTransitionSession?.watchdog?.cancel()
        guard generatesOrientationNotifications else {
            return
        }
        if Thread.isMainThread {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        } else {
            DispatchQueue.main.async {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }
    }

    @objc func configure(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let patch = call.options as? [String: Any] ?? [:]
            if let rawDuration = patch["animationDuration"], !(rawDuration is NSNull) {
                guard let durationMs = nativeNavigationDurationMilliseconds(
                    rawDuration,
                    fallback: self.defaultTransitionDuration * 1_000
                ) else {
                    call.reject("animationDuration must be a finite value between 0 and 60000 milliseconds")
                    return
                }
                self.defaultTransitionDuration = TimeInterval(durationMs) / 1_000
            }

            self.configureState = nativeNavigationMergeOptions(
                current: self.configureState,
                patch: patch,
                nestedKeys: ["colors", "glass"]
            )
            let options = NativeNavigationOptions(values: self.configureState)
            self.isEnabled = options.bool("enabled", default: true)
            self.contentInsetMode = options.string("contentInsetMode") ?? "css"

            if !self.isEnabled {
                self.navContainer?.isHidden = true
                self.restoreWebViewFromSystemTabController()
                self.hideSystemTabBarChromeCompletely()
                self.tabContainer?.isHidden = true
                self.floatingTabBar?.isHidden = true
            } else {
                if self.hasNavbarState {
                    self.applyNavbarState()
                }
                if self.hasTabbarState {
                    self.applyTabbarState()
                }
            }

            self.updateInsetsAndNotify()
            call.resolve(self.insetsResult())
        }
    }

    @objc func setNavbar(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.navbarState = nativeNavigationMergeOptions(
                current: self.navbarState,
                patch: call.options as? [String: Any] ?? [:],
                nestedKeys: ["colors", "glass"]
            )
            self.hasNavbarState = true
            if self.isEnabled {
                self.applyNavbarState()
            } else {
                self.navContainer?.isHidden = true
            }
            self.updateInsetsAndNotify()
            call.resolve(self.insetsResult())
        }
    }

    @objc func setTabbar(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.tabbarState = nativeNavigationMergeOptions(
                current: self.tabbarState,
                patch: call.options as? [String: Any] ?? [:],
                nestedKeys: ["colors", "glass", "style"]
            )
            self.hasTabbarState = true
            if self.isEnabled {
                self.applyTabbarState()
            } else {
                self.restoreWebViewFromSystemTabController()
                self.hideSystemTabBarChromeCompletely()
                self.tabContainer?.isHidden = true
                self.floatingTabBar?.isHidden = true
            }
            self.updateInsetsAndNotify()
            call.resolve(self.insetsResult())
        }
    }

    private func effectiveBarOptions(_ barState: [String: Any]) -> NativeNavigationOptions {
        NativeNavigationOptions(values: nativeNavigationEffectiveBarOptions(configure: configureState, bar: barState))
    }

    private func applyNavbarState() {
        let options = effectiveBarOptions(navbarState)
        let hidden = options.bool("hidden", default: false)
        navbarVisible = !hidden
        guard !hidden else {
            navContainer?.isHidden = true
            return
        }

        let navBar = ensureNavBar()
        let large = options.bool("large", default: false)
        navbarUsesLiquidGlass = usesSystemLiquidGlass && glassIsEnabled(options)
        let navItem = UINavigationItem(title: options.string("title") ?? "")
        navItem.prompt = options.string("subtitle")
        navBar.prefersLargeTitles = large
        navItem.largeTitleDisplayMode = large ? .always : .never

        navbarItemPlacement.removeAll()
        navbarItemTitle.removeAll()
        if let backButton = options.object("backButton"), backButton["visible"] as? Bool == true {
            let title = backButton["title"] as? String
            let item = UIBarButtonItem(
                title: title ?? "Back",
                style: .plain,
                target: self,
                action: #selector(handleNavbarBack)
            )
            configureGlassBarButtonItem(item, id: "back")
            navItem.leftBarButtonItem = item
        } else {
            navItem.leftBarButtonItems = makeBarButtonItems(options.array("leftItems") ?? [], placement: "left")
        }
        navItem.rightBarButtonItems = makeBarButtonItems(options.array("rightItems") ?? [], placement: "right")
        navBar.setItems([navItem], animated: options.bool("animated", default: false))
        applyNavBarAppearance(navBar: navBar, options: options)
        navContainer?.isHidden = false
        layoutChrome()
    }

    private func applyTabbarState() {
        let options = effectiveBarOptions(tabbarState)
        let hidden = options.bool("hidden", default: false)
        tabbarVisible = !hidden
        guard !hidden else {
            hideTabBarChrome()
            return
        }

        tabbarStyle = makeTabbarStyle(from: options)
        tabbarHeight = tabbarStyle.totalHeight
        let tabs = options.array("tabs") ?? []
        let selectedId = options.string("selectedId")
        let labels = options.bool("labels", default: true)
        let labelVisibilityMode = options.string("labelVisibilityMode") ?? (labels ? "labeled" : "unlabeled")
        let icons = options.bool("icons", default: true)
        isUsingSystemTabBar = usesSystemLiquidGlass
            && tabbarStyle.shape != .curve
            && glassIsEnabled(options)

        if isUsingSystemTabBar {
            let tabBar = ensureTabBar()
            let (items, selectedIndex) = makeTabBarItems(
                tabs,
                selectedId: selectedId,
                labelVisibilityMode: labelVisibilityMode,
                icons: icons
            )
            floatingTabBar?.isHidden = true
            tabContainer?.isHidden = true
            applySystemTabBarItems(
                items,
                selectedIndex: selectedIndex,
                animated: options.bool("animated", default: false)
            )
            applyTabBarAppearance(tabBar: tabBar, options: options)
            if items.isEmpty {
                tabbarVisible = false
                hideSystemTabBarChromeCompletely()
            } else {
                showTabBarChrome(tabBar)
            }
        } else {
            restoreWebViewFromSystemTabController()
            setSystemTabBarHidden(true)
            tabBarController?.view.isHidden = true
            let tabBar = ensureFloatingTabBar()
            let (items, selectedIndex) = makeFloatingTabBarItems(tabs, selectedId: selectedId, icons: icons)
            if items.isEmpty {
                tabbarVisible = false
                tabBar.configure(
                    items: [],
                    selectedIndex: 0,
                    labelVisibilityMode: labelVisibilityMode,
                    icons: icons,
                    style: tabbarStyle
                )
                tabContainer?.isHidden = true
                tabBar.isHidden = true
            } else {
                applyFloatingTabBarAppearance(tabBar: tabBar, options: options)
                let resolvedSelectedIndex = selectedIndex
                    ?? (items.indices.contains(tabBar.selectedIndex) ? tabBar.selectedIndex : 0)
                tabBar.configure(
                    items: items,
                    selectedIndex: resolvedSelectedIndex,
                    labelVisibilityMode: labelVisibilityMode,
                    icons: icons,
                    style: tabbarStyle
                )
                tabBar.onSelect = { [weak self] _, item in
                    guard let self else { return }
                    self.tabbarState["selectedId"] = item.id
                    self.emitPluginEvent("tabSelect", data: [
                        "id": item.id,
                        "index": item.sourceIndex,
                        "title": item.title
                    ])
                }
                showFloatingTabBarChrome(tabBar)
            }
        }
        layoutChrome()
    }

    @objc func beginTransition(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let webView = self.webView,
                  let transitionContainer = webView.superview else {
                call.reject("WebView unavailable")
                return
            }
            let callOptions = call.options as? [String: Any] ?? [:]

            guard let durationMs = nativeNavigationDurationMilliseconds(
                callOptions["duration"],
                fallback: self.defaultTransitionDuration * 1_000
            ) else {
                call.reject("duration must be a finite value between 0 and 60000 milliseconds")
                return
            }
            guard let cornerRadius = self.transitionCornerRadius(
                callOptions["cornerRadius"],
                fallback: 0
            ) else {
                call.reject("cornerRadius must be a finite value between 0 and 4096")
                return
            }

            if let previousSession = self.activeTransitionSession {
                self.completeTransition(previousSession, durationMs: 0)
            }

            self.transitionGeneration &+= 1
            let sessionGeneration = self.transitionGeneration
            let transitionId = nativeNavigationTransitionIdentifier(
                explicitId: call.getString("id"),
                timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                generation: sessionGeneration
            )
            let direction = call.getString("direction") ?? "forward"
            let zoomSourceRect = direction == "zoom" ? self.transitionRect(call.getObject("sourceRect")) : nil
            let zoomSourceFrame = zoomSourceRect.map { self.transitionFrame(for: $0, webView: webView) }

            webView.layer.removeAllAnimations()
            webView.transform = .identity
            webView.alpha = 1
            webView.layer.cornerRadius = 0
            webView.clipsToBounds = false
            let transitionSurface = nativeNavigationFallbackBackground(for: webView).withAlphaComponent(1.0)
            self.prepareTransitionContainerBackground(transitionContainer, surface: transitionSurface)
            let snapshot = self.transitionSnapshotView(from: webView, sourceRect: zoomSourceRect)
            snapshot.frame = zoomSourceFrame ?? webView.frame
            snapshot.autoresizingMask = zoomSourceFrame == nil ? [.flexibleWidth, .flexibleHeight] : []
            snapshot.backgroundColor = transitionSurface
            snapshot.isOpaque = true
            snapshot.layer.cornerRadius = cornerRadius
            snapshot.clipsToBounds = cornerRadius > 0
            snapshot.isUserInteractionEnabled = false
            transitionContainer.insertSubview(snapshot, aboveSubview: webView)
            self.bringChromeToFront()
            let session = NativeNavigationTransitionSession(
                generation: sessionGeneration,
                id: transitionId,
                direction: direction,
                durationMs: durationMs,
                webView: webView,
                snapshot: snapshot,
                zoomSourceFrame: zoomSourceFrame,
                cornerRadius: cornerRadius
            )
            self.activeTransitionSession = session
            webView.alpha = 0.01
            self.armTransitionWatchdog(for: session, durationMs: durationMs)

            let event: [String: Any] = ["id": transitionId, "direction": direction, "duration": durationMs]
            self.emitPluginEvent("transitionStart", data: event)
            call.resolve(event)
        }
    }

    /// Schedules `recoverStuckTransition` to force-complete `id` if
    /// `finishTransition` has not cancelled the watchdog by then. The delay is
    /// generous (the requested duration plus a multi-second grace period) so
    /// it never fires during a legitimate, merely slow, transition.
    private func ownsTransition(_ session: NativeNavigationTransitionSession) -> Bool {
        guard let activeSession = activeTransitionSession else {
            return false
        }
        return activeSession === session && activeSession.generation == session.generation
    }

    private func armTransitionWatchdog(for session: NativeNavigationTransitionSession, durationMs: Int) {
        session.watchdog?.cancel()
        session.watchdogGeneration &+= 1
        let watchdogGeneration = session.watchdogGeneration
        let delay = max(TimeInterval(durationMs) / 1_000, defaultTransitionDuration) + 4.0
        let workItem = DispatchWorkItem { [weak self, weak session] in
            guard let self,
                  let session,
                  session.watchdogGeneration == watchdogGeneration,
                  self.ownsTransition(session) else {
                return
            }
            self.completeTransition(session, durationMs: 0)
        }
        session.watchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    @objc private func handleAppDidEnterBackground() {
        guard let session = activeTransitionSession else {
            return
        }
        completeTransition(session, durationMs: 0)
    }

    @objc func finishTransition(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let session = self.activeTransitionSession else {
                call.reject("No active transition")
                return
            }
            let callOptions = call.options as? [String: Any] ?? [:]
            if let requestedId = call.getString("id"), requestedId != session.id {
                call.reject("Transition id does not match the active transition")
                return
            }
            guard !session.isFinishing else {
                call.reject("Transition is already finishing")
                return
            }
            guard let durationMs = nativeNavigationDurationMilliseconds(
                callOptions["duration"],
                fallback: Double(session.durationMs)
            ) else {
                call.reject("duration must be a finite value between 0 and 60000 milliseconds")
                return
            }
            guard let cornerRadius = self.transitionCornerRadius(
                callOptions["cornerRadius"],
                fallback: Double(session.cornerRadius)
            ) else {
                call.reject("cornerRadius must be a finite value between 0 and 4096")
                return
            }

            let direction = call.getString("direction") ?? session.direction
            session.direction = direction
            session.durationMs = durationMs
            session.cornerRadius = cornerRadius
            session.isFinishing = true
            session.finishResolver = { result in call.resolve(result) }
            self.armTransitionWatchdog(for: session, durationMs: durationMs)
            let transition = NativeNavigationTransitionContext(
                session: session,
                webView: session.webView,
                snapshot: session.snapshot,
                id: session.id,
                direction: direction,
                duration: TimeInterval(durationMs) / 1_000,
                durationMs: durationMs
            )

            if direction == "zoom" {
                let sourceRect = self.transitionRect(call.getObject("sourceRect"))
                let targetRect = self.transitionRect(call.getObject("targetRect"))
                self.finishZoomTransition(NativeNavigationZoomTransitionContext(
                    transition: transition,
                    sourceFrame: sourceRect.map { self.transitionFrame(for: $0, webView: session.webView) },
                    targetFrame: targetRect.map { self.transitionFrame(for: $0, webView: session.webView) },
                    cornerRadius: cornerRadius
                ))
                return
            }

            self.finishStandardTransition(transition)
        }
    }

    private func finishStandardTransition(_ transition: NativeNavigationTransitionContext) {
        guard ownsTransition(transition.session) else {
            return
        }
        let width = transition.webView.bounds.width
        let transforms = standardTransitionTransforms(direction: transition.direction, width: width)
        let usesStationaryCrossfade = nativeNavigationUsesStationaryTransitionCrossfade(direction: transition.direction)
        transition.webView.transform = transforms.start
        transition.webView.alpha = usesStationaryCrossfade ? 1 : 0.01

        guard transition.duration > 0 else {
            finishTransitionCleanup(transition)
            return
        }

        UIView.animate(
            withDuration: transition.duration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                transition.webView.transform = .identity
                transition.webView.alpha = 1
                transition.snapshot?.transform = transforms.snapshotEnd
                transition.snapshot?.alpha = usesStationaryCrossfade ? 0 : 0.75
            },
            completion: { [weak self] _ in
                self?.finishTransitionCleanup(transition)
            }
        )
    }

    private func standardTransitionTransforms(
        direction: String,
        width: CGFloat
    ) -> (start: CGAffineTransform, snapshotEnd: CGAffineTransform) {
        switch direction {
        case "back":
            return (CGAffineTransform(translationX: -width * 0.3, y: 0), CGAffineTransform(translationX: width, y: 0))
        case "tab", "root", "none":
            return (.identity, .identity)
        default:
            return (CGAffineTransform(translationX: width, y: 0), CGAffineTransform(translationX: -width * 0.3, y: 0))
        }
    }

    private func finishZoomTransition(_ zoom: NativeNavigationZoomTransitionContext) {
        let transition = zoom.transition
        guard ownsTransition(transition.session) else {
            return
        }
        let startFrame = zoom.sourceFrame ?? transition.session.zoomSourceFrame ?? transition.webView.frame

        let finish: () -> Void = { [weak self] in
            self?.finishTransitionCleanup(transition)
        }

        guard transition.duration > 0 else {
            finish()
            return
        }

        if let targetFrame = zoom.targetFrame {
            animateZoomToTarget(zoom, startFrame: startFrame, targetFrame: targetFrame, completion: finish)
            return
        }

        animateZoomToFullScreen(zoom, startFrame: startFrame, completion: finish)
    }

    private func animateZoomToTarget(
        _ zoom: NativeNavigationZoomTransitionContext,
        startFrame: CGRect,
        targetFrame: CGRect,
        completion: @escaping () -> Void
    ) {
        let transition = zoom.transition
        transition.webView.transform = .identity
        transition.webView.alpha = 0.01
        transition.snapshot?.frame = startFrame
        transition.snapshot?.layer.cornerRadius = zoom.cornerRadius
        transition.snapshot?.clipsToBounds = zoom.cornerRadius > 0

        UIView.animate(
            withDuration: transition.duration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: {
                transition.webView.alpha = 1
                transition.snapshot?.frame = targetFrame
                transition.snapshot?.alpha = 0
            },
            completion: { _ in completion() }
        )
    }

    private func animateZoomToFullScreen(
        _ zoom: NativeNavigationZoomTransitionContext,
        startFrame: CGRect,
        completion: @escaping () -> Void
    ) {
        let transition = zoom.transition
        let fullFrame = transition.webView.frame
        let scaleX = max(startFrame.width / max(fullFrame.width, 1), 0.01)
        let scaleY = max(startFrame.height / max(fullFrame.height, 1), 0.01)
        let translationX = startFrame.midX - fullFrame.midX
        let translationY = startFrame.midY - fullFrame.midY
        transition.webView.transform = CGAffineTransform(translationX: translationX, y: translationY)
            .scaledBy(x: scaleX, y: scaleY)
        transition.webView.alpha = 1
        transition.webView.layer.cornerRadius = zoom.cornerRadius
        transition.webView.clipsToBounds = zoom.cornerRadius > 0
        transition.snapshot?.frame = startFrame

        UIView.animate(
            withDuration: transition.duration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: {
                transition.webView.transform = .identity
                transition.webView.layer.cornerRadius = 0
                transition.snapshot?.frame = fullFrame
                transition.snapshot?.alpha = 0
            },
            completion: { _ in completion() }
        )
    }

    private func finishTransitionCleanup(_ transition: NativeNavigationTransitionContext) {
        completeTransition(transition.session, durationMs: transition.durationMs)
    }

    private func completeTransition(_ session: NativeNavigationTransitionSession, durationMs: Int) {
        guard ownsTransition(session) else {
            return
        }
        activeTransitionSession = nil
        session.watchdog?.cancel()
        session.watchdog = nil
        session.snapshot?.layer.removeAllAnimations()
        session.snapshot?.removeFromSuperview()
        session.snapshot = nil
        session.webView.layer.removeAllAnimations()
        session.webView.transform = .identity
        session.webView.alpha = 1
        session.webView.layer.cornerRadius = 0
        session.webView.clipsToBounds = false
        restoreTransitionContainerBackground()

        let event: [String: Any] = [
            "id": session.id,
            "direction": session.direction,
            "duration": durationMs
        ]
        if !session.didEmitEnd {
            session.didEmitEnd = true
            emitPluginEvent("transitionEnd", data: event)
        }
        if !session.didResolveFinish, let resolver = session.finishResolver {
            session.didResolveFinish = true
            session.finishResolver = nil
            resolver(event)
        }
    }

    private func prepareTransitionContainerBackground(_ container: UIView, surface: UIColor) {
        activeTransitionContainer = container
        activeTransitionContainerBackgroundColor = container.backgroundColor
        activeTransitionContainerWasOpaque = container.isOpaque
        activeTransitionContainerBackgroundCaptured = true
        if nativeNavigationNeedsTransitionSurface(container.backgroundColor) {
            container.backgroundColor = surface
            container.isOpaque = true
        }
    }

    private func restoreTransitionContainerBackground() {
        guard activeTransitionContainerBackgroundCaptured else {
            return
        }
        activeTransitionContainer?.backgroundColor = activeTransitionContainerBackgroundColor
        activeTransitionContainer?.isOpaque = activeTransitionContainerWasOpaque
        activeTransitionContainer = nil
        activeTransitionContainerBackgroundColor = nil
        activeTransitionContainerWasOpaque = false
        activeTransitionContainerBackgroundCaptured = false
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve([
            "version": implementation.getPluginVersion()
        ])
    }

    @objc private func handleNavbarBack() {
        emitPluginEvent("navbarBack", data: ["source": "navbar"])
    }

    @objc private func handleNavbarButton(_ sender: UIBarButtonItem) {
        guard let id = sender.accessibilityIdentifier else {
            return
        }
        emitPluginEvent("navbarItemTap", data: [
            "id": id,
            "title": navbarItemTitle[id] ?? "",
            "placement": navbarItemPlacement[id] ?? "right"
        ])
    }

    public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        notifyTabSelect(index: item.tag)
    }

    public func tabBarController(
        _ tabBarController: UITabBarController,
        shouldSelect viewController: UIViewController
    ) -> Bool {
        if isUsingSystemTabBar {
            hostWebView(in: viewController)
        }
        return true
    }

    public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard !suppressTabSelectEvent else {
            hostWebViewInSelectedSystemTab()
            return
        }
        let index = viewController.tabBarItem.tag
        hostWebViewInSelectedSystemTab()
        notifyTabSelect(index: index)
    }

    private func notifyTabSelect(index: Int) {
        guard index >= 0,
              index < tabIds.count,
              !tabIds[index].isEmpty else {
            return
        }
        tabbarState["selectedId"] = tabIds[index]
        emitPluginEvent("tabSelect", data: [
            "id": tabIds[index],
            "index": index,
            "title": tabTitles[index]
        ])
    }

    @objc private func handleLayoutChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.layoutChrome()
            self.updateInsetsAndNotify()
        }
    }

    @objc private func handleKeyboardFrameChange() {
        DispatchQueue.main.async {
            self.layoutChrome()
        }
    }

    @objc private func handleKeyboardDidHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.refreshChromeAfterKeyboardDismiss()
        }
    }

    @objc private func handleReduceTransparencyChange() {
        DispatchQueue.main.async {
            self.refreshTabBarBackgroundIfNeeded()
            self.layoutChrome()
            self.updateInsetsAndNotify()
        }
    }

    private func refreshChromeAfterKeyboardDismiss() {
        layoutChrome()
        refreshTabBarBackgroundIfNeeded()
        updateInsetsAndNotify()
    }

    private func refreshTabBarBackgroundIfNeeded() {
        guard tabbarVisible else {
            return
        }

        tabBarController?.view.setNeedsLayout()
        tabBarController?.view.layoutIfNeeded()

        if let tabBar = tabBar {
            tabBar.isTranslucent = !prefersOpaqueTabBarBackground()
            let standardAppearance = tabBar.standardAppearance
            tabBar.standardAppearance = standardAppearance
            let scrollEdgeAppearance = tabBar.scrollEdgeAppearance ?? standardAppearance
            tabBar.scrollEdgeAppearance = scrollEdgeAppearance
            tabBar.items?.forEach { item in
                item.standardAppearance = standardAppearance
                item.scrollEdgeAppearance = tabBar.scrollEdgeAppearance
            }
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
        }

        tabContainer?.setNeedsLayout()
        tabContainer?.layoutIfNeeded()
        floatingTabBar?.setNeedsLayout()
        floatingTabBar?.layoutIfNeeded()
    }

    private func prefersOpaqueTabBarBackground() -> Bool {
        UIAccessibility.isReduceTransparencyEnabled
    }

    private func ensureNavBar() -> UINavigationBar {
        if let navBar = navBar {
            return navBar
        }

        let container = NativeNavigationChromeContainer()
        container.hitSlop = UIEdgeInsets(top: 0, left: 0, bottom: 32, right: 0)
        container.isUserInteractionEnabled = true
        container.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.isUserInteractionEnabled = false
        blurView.isHidden = usesSystemLiquidGlass
        container.addSubview(blurView)
        self.navBlurView = blurView

        let bar = NativeNavigationBar()
        bar.hitSlop = UIEdgeInsets(top: 0, left: 0, bottom: 32, right: 0)
        bar.isTranslucent = true
        if !usesSystemLiquidGlass {
            bar.backgroundColor = .clear
        }
        bar.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        container.addSubview(bar)

        bridge?.viewController?.view.addSubview(container)
        self.navContainer = container
        self.navBar = bar
        return bar
    }

    private func ensureTabBar() -> UITabBar {
        if usesSystemLiquidGlass {
            return ensureSystemTabBar()
        }

        if let tabBar = tabBar {
            return tabBar
        }

        let container = NativeNavigationChromeContainer()
        container.hitSlop = UIEdgeInsets(top: 32, left: 0, bottom: 24, right: 0)
        container.isUserInteractionEnabled = true
        container.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        container.backgroundColor = .clear

        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.14
        container.layer.shadowRadius = 18
        container.layer.shadowOffset = CGSize(width: 0, height: 10)

        let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        effectView.isUserInteractionEnabled = false
        effectView.clipsToBounds = true
        container.addSubview(effectView)
        self.tabEffectView = effectView

        let bar = UITabBar()
        bar.isTranslucent = true
        bar.backgroundColor = .clear
        bar.backgroundImage = UIImage()
        bar.shadowImage = UIImage()
        bar.clipsToBounds = true
        bar.delegate = self
        bar.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        container.addSubview(bar)
        bridge?.viewController?.view.addSubview(container)
        self.tabContainer = container
        self.tabBar = bar
        return bar
    }

    private func ensureFloatingTabBar() -> NativeNavigationFloatingTabBar {
        if let floatingTabBar = floatingTabBar {
            return floatingTabBar
        }

        let container = NativeNavigationChromeContainer()
        container.hitSlop = UIEdgeInsets(top: 32, left: 0, bottom: 24, right: 0)
        container.isUserInteractionEnabled = true
        container.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        container.backgroundColor = .clear
        container.clipsToBounds = false

        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.14
        container.layer.shadowRadius = 18
        container.layer.shadowOffset = CGSize(width: 0, height: 10)

        let effectView = UIVisualEffectView(effect: liquidGlassEffect() ?? UIBlurEffect(style: .systemChromeMaterial))
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        effectView.isUserInteractionEnabled = false
        effectView.clipsToBounds = true
        container.addSubview(effectView)
        self.tabEffectView = effectView

        let trailingEffectView = UIVisualEffectView(
            effect: liquidGlassEffect() ?? UIBlurEffect(style: .systemChromeMaterial)
        )
        trailingEffectView.autoresizingMask = []
        trailingEffectView.isUserInteractionEnabled = false
        trailingEffectView.clipsToBounds = true
        trailingEffectView.isHidden = true
        container.addSubview(trailingEffectView)
        self.trailingTabEffectView = trailingEffectView

        let bar = NativeNavigationFloatingTabBar()
        bar.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        bar.clipsToBounds = false
        container.addSubview(bar)
        bridge?.viewController?.view.addSubview(container)
        self.tabContainer = container
        self.floatingTabBar = bar
        return bar
    }

    private func ensureSystemTabBar() -> UITabBar {
        if let tabBarController = tabBarController {
            hostWebViewInSelectedSystemTab()
            return tabBarController.tabBar
        }

        let controller = NativeNavigationTabController()
        controller.delegate = self
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.isHidden = !tabbarVisible

        if let parent = bridge?.viewController {
            let containerView = systemTabHostingContainerView(in: parent)
            parent.addChild(controller)
            insertSystemTabControllerView(controller.view, in: containerView)
            controller.didMove(toParent: parent)
        }

        self.tabBarController = controller
        self.tabBar = controller.tabBar
        liftWebViewOverlaysAboveSystemTabs()
        hostWebViewInSelectedSystemTab()
        return controller.tabBar
    }

    private func systemTabHostingContainerView(in parent: UIViewController) -> UIView {
        if let systemTabRootContainer = systemTabRootContainer {
            return systemTabRootContainer
        }

        guard let webView = webView,
              parent.view === webView else {
            return parent.view
        }

        let previousSuperview = webView.superview
        let previousIndex = previousSuperview?.subviews.firstIndex(of: webView)
        let previousFrame = webView.frame
        let previousAutoresizingMask = webView.autoresizingMask
        let container = UIView(frame: previousFrame)
        container.backgroundColor = nativeNavigationFallbackBackground(for: webView)
        container.isOpaque = true
        container.autoresizingMask = previousAutoresizingMask.isEmpty
            ? [.flexibleWidth, .flexibleHeight]
            : previousAutoresizingMask

        if let previousSuperview = previousSuperview {
            previousSuperview.insertSubview(
                container,
                at: min(previousIndex ?? previousSuperview.subviews.count, previousSuperview.subviews.count)
            )
        }

        parent.view = container
        container.addSubview(webView)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.frame = container.bounds
        moveNativeChrome(from: webView, to: container)

        systemTabRootContainer = container
        originalWebViewSuperview = container
        originalWebViewIndex = 0
        originalWebViewAutoresizingMask = webView.autoresizingMask
        liftWebViewOverlaysAboveSystemTabs()
        return container
    }

    private func moveNativeChrome(from webView: UIView, to container: UIView) {
        if let navContainer = navContainer,
           navContainer.superview === webView {
            container.addSubview(navContainer)
        }
    }

    private func applySystemTabBarItems(_ items: [UITabBarItem], selectedIndex: Int?, animated: Bool) {
        guard let tabBarController = tabBarController else {
            return
        }

        let previousSelectedIndex = tabBarController.selectedIndex
        let controllers = systemTabContentControllers(for: items)
        let currentControllers = tabBarController.viewControllers ?? []
        let shouldUpdateControllers = currentControllers.count != controllers.count
            || zip(currentControllers, controllers).contains { currentController, nextController in
                currentController !== nextController
            }
        let shouldAnimate = animated && tabBarController.viewControllers?.count == controllers.count

        suppressTabSelectEvent = true
        defer { suppressTabSelectEvent = false }

        guard !controllers.isEmpty else {
            restoreWebViewFromSystemTabController()
            if shouldUpdateControllers {
                tabBarController.setViewControllers([], animated: false)
            }
            tabViewControllers = []
            return
        }

        if shouldUpdateControllers {
            tabBarController.setViewControllers(controllers, animated: shouldAnimate)
        }

        let fallbackIndex = selectedIndex ?? previousSelectedIndex
        let index = min(max(fallbackIndex, 0), controllers.count - 1)
        hostWebView(in: controllers[index])
        tabBarController.selectedIndex = index
        tabViewControllers = controllers
    }

    private func systemTabContentControllers(for items: [UITabBarItem]) -> [UIViewController] {
        let existingControllers = tabViewControllers.compactMap { $0 as? NativeNavigationTabContentController }
        if existingControllers.count == items.count {
            zip(existingControllers, items).forEach { controller, item in
                controller.tabBarItem = item
            }
            return existingControllers
        }

        return items.map { item -> UIViewController in
            let controller = NativeNavigationTabContentController()
            controller.tabBarItem = item
            return controller
        }
    }

    private func setSystemTabBarHidden(_ hidden: Bool) {
        guard let tabBarController = tabBarController else {
            return
        }

        let tabBar = tabBarController.tabBar
        if #available(iOS 18.0, *) {
            tabBarController.setTabBarHidden(hidden, animated: false)
        } else {
            tabBar.isHidden = hidden
        }

        if hidden {
            setTabBarBackgroundSubviewsHidden(true, on: tabBar)
        } else {
            setTabBarBackgroundSubviewsHidden(false, on: tabBar)
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
        }
    }

    private func setTabBarBackgroundSubviewsHidden(_ hidden: Bool, on tabBar: UITabBar) {
        tabBar.isHidden = hidden
        tabBar.alpha = hidden ? 0 : 1
        tabBar.isUserInteractionEnabled = !hidden
        tabBar.subviews.forEach { subview in
            subview.isHidden = hidden
            subview.alpha = hidden ? 0 : 1
        }
    }

    private func hideSystemTabBarChromeCompletely() {
        applySystemTabBarItems([], selectedIndex: nil, animated: false)
        setSystemTabBarHidden(true)
        tabBarController?.view.isHidden = true
        tabContainer?.isHidden = true
        floatingTabBar?.isHidden = true
    }

    private func hideTabBarChrome() {
        if isUsingSystemTabBar {
            hideSystemTabBarChromeCompletely()
        } else {
            restoreWebViewFromSystemTabController()
            hideSystemTabBarChromeCompletely()
            tabBar?.isHidden = true
        }
    }

    private func showTabBarChrome(_ tabBar: UITabBar) {
        tabContainer?.isHidden = true
        floatingTabBar?.isHidden = true
        tabBarController?.view.isHidden = false
        if isUsingSystemTabBar {
            setSystemTabBarHidden(false)
            liftWebViewOverlaysAboveSystemTabs()
            hostWebViewInSelectedSystemTab()
        } else {
            tabBar.isHidden = false
        }
    }

    private func showFloatingTabBarChrome(_ tabBar: NativeNavigationFloatingTabBar) {
        restoreWebViewFromSystemTabController()
        tabBarController?.view.isHidden = true
        tabContainer?.isHidden = false
        tabBar.isHidden = false
    }

    private func captureOriginalWebViewPlacementIfNeeded(_ webView: UIView) {
        guard originalWebViewSuperview == nil, let superview = webView.superview else {
            return
        }

        originalWebViewSuperview = superview
        originalWebViewIndex = superview.subviews.firstIndex(of: webView)
        originalWebViewAutoresizingMask = webView.autoresizingMask
    }

    private func insertSystemTabControllerView(_ controllerView: UIView, in parentView: UIView) {
        guard let webView = webView else {
            parentView.addSubview(controllerView)
            return
        }

        captureOriginalWebViewPlacementIfNeeded(webView)
        let insertionIndex = systemTabControllerInsertionIndex(in: parentView, for: webView)
        parentView.insertSubview(controllerView, at: insertionIndex)
    }

    private func systemTabControllerInsertionIndex(in parentView: UIView, for webView: UIView) -> Int {
        if let directChild = directChild(of: parentView, containing: webView),
           let index = parentView.subviews.firstIndex(of: directChild) {
            return min(index, parentView.subviews.count)
        }

        if let originalWebViewSuperview = originalWebViewSuperview,
           originalWebViewSuperview === parentView {
            return min(originalWebViewIndex ?? parentView.subviews.count, parentView.subviews.count)
        }

        return parentView.subviews.count
    }

    private func directChild(of ancestor: UIView, containing descendant: UIView) -> UIView? {
        var current: UIView? = descendant
        while let view = current, let superview = view.superview {
            if superview === ancestor {
                return view
            }
            current = superview
        }

        return nil
    }

    private func hostWebViewInSelectedSystemTab() {
        hostWebView(in: tabBarController?.selectedViewController)
    }

    private func hostWebView(in viewController: UIViewController?) {
        guard isUsingSystemTabBar,
              let webView = webView,
              let selectedController = viewController as? NativeNavigationTabContentController else {
            return
        }

        liftWebViewOverlaysAboveSystemTabs()
        captureOriginalWebViewPlacementIfNeeded(webView)
        clearHostedWebViews(matching: webView, except: selectedController, preservingSnapshots: true)
        guard selectedController.host(webView: webView) else {
            isWebViewHostedInSystemTabController = false
            return
        }
        clearHostedWebViews(matching: webView, except: selectedController)
        isWebViewHostedInSystemTabController = true
        bringLiftedWebViewOverlaysToFront()
    }

    private func liftWebViewOverlaysAboveSystemTabs() {
        guard isUsingSystemTabBar,
              let webView = webView,
              let container = systemTabRootContainer else {
            return
        }

        nativeNavigationLiftWebViewOverlaySubviews(
            from: webView,
            to: container,
            tracking: &liftedWebViewOverlays,
            excluding: [navContainer, tabContainer, tabBarController?.view]
        )
    }

    private func bringLiftedWebViewOverlaysToFront() {
        guard let container = systemTabRootContainer else {
            return
        }

        liftedWebViewOverlays = liftedWebViewOverlays.filter { $0.value != nil }
        liftedWebViewOverlays
            .compactMap(\.value)
            .filter { $0.superview === container }
            .forEach { container.bringSubviewToFront($0) }
    }

    private func restoreWebViewFromSystemTabController() {
        guard isWebViewHostedInSystemTabController,
              let webView = webView,
              let targetSuperview = originalWebViewSuperview ?? bridge?.viewController?.view else {
            return
        }

        let insertionIndex = min(originalWebViewIndex ?? targetSuperview.subviews.count, targetSuperview.subviews.count)
        clearHostedWebViews(matching: webView)
        webView.removeFromSuperview()
        targetSuperview.insertSubview(webView, at: insertionIndex)
        webView.autoresizingMask = originalWebViewAutoresizingMask ?? [.flexibleWidth, .flexibleHeight]
        webView.frame = targetSuperview.bounds
        isWebViewHostedInSystemTabController = false
    }

    private func clearHostedWebViews(
        matching webView: UIView,
        except owner: NativeNavigationTabContentController? = nil,
        preservingSnapshots: Bool = false
    ) {
        tabViewControllers
            .compactMap { $0 as? NativeNavigationTabContentController }
            .filter { $0 !== owner }
            .forEach { $0.clearHostedWebView(ifMatching: webView, preservingSnapshot: preservingSnapshots) }
    }

    private func makeBarButtonItems(_ rawItems: [[String: Any]], placement: String) -> [UIBarButtonItem] {
        return rawItems.map { rawItem in
            let id = rawItem["id"] as? String ?? UUID().uuidString
            let title = rawItem["title"] as? String
            let image = image(from: rawItem["icon"] as? [String: Any])
            let item = UIBarButtonItem(
                image: image,
                style: .plain,
                target: self,
                action: #selector(handleNavbarButton(_:))
            )
            if image == nil {
                item.title = title
            }
            item.isEnabled = rawItem["enabled"] as? Bool ?? true
            item.accessibilityIdentifier = id
            item.accessibilityLabel = title
            configureGlassBarButtonItem(item, id: id)
            navbarItemPlacement[id] = placement
            navbarItemTitle[id] = title ?? ""
            return item
        }
    }

    // swiftlint:disable:next function_body_length
    private func makeTabBarItems(
        _ tabs: [[String: Any]],
        selectedId: String?,
        labelVisibilityMode: String,
        icons: Bool
    ) -> ([UITabBarItem], Int?) {
        tabIds = []
        tabTitles = []
        tabDisplayTitles = []
        tabBaseImages = []
        tabSelectedImages = []
        var selectedIndex: Int?
        var items: [UITabBarItem] = []
        var trailingEntry: (item: UITabBarItem, title: String?, image: UIImage?, selectedImage: UIImage?)?

        for (sourceIndex, tab) in tabs.enumerated() {
            let id = tab["id"] as? String ?? "tab-\(sourceIndex)"
            let isHidden = tab["hidden"] as? Bool ?? false
            if isHidden && id != selectedId {
                continue
            }

            let rawTitle = tab["title"] as? String ?? ""
            let title = tabTitle(
                rawTitle,
                id: id,
                index: items.count,
                selectedId: selectedId,
                labelVisibilityMode: labelVisibilityMode
            )
            let image = icons ? self.image(from: tab["icon"] as? [String: Any]) : nil
            let selectedImage = icons ? self.image(from: tab["selectedIcon"] as? [String: Any]) : nil
            let role = (tab["role"] as? String)?.lowercased()
            let item: UITabBarItem
            if role == "search" || role == "prominent" {
                // iOS 26+ Liquid Glass renders `.search` as a detached trailing
                // circular action beside the floating tab capsule. Keep the
                // system-item title empty so UIKit treats it as icon-only.
                item = UITabBarItem(tabBarSystemItem: .search, tag: sourceIndex)
                item.title = nil
                if let image = image {
                    item.image = image
                }
                if let selectedImage = selectedImage {
                    item.selectedImage = selectedImage
                }
                item.accessibilityLabel = rawTitle.isEmpty ? id : rawTitle
            } else {
                item = UITabBarItem(title: title, image: image, selectedImage: selectedImage)
                item.tag = sourceIndex
            }
            item.isEnabled = tab["enabled"] as? Bool ?? true
            if let badge = tab["badge"] {
                item.badgeValue = String(describing: badge)
            }
            while tabIds.count <= sourceIndex {
                tabIds.append("")
                tabTitles.append("")
            }
            tabIds[sourceIndex] = id
            tabTitles[sourceIndex] = rawTitle
            if role == "search" || role == "prominent" {
                trailingEntry = (item, title, image, selectedImage ?? image)
            } else {
                items.append(item)
                tabDisplayTitles.append(title)
                tabBaseImages.append(image)
                tabSelectedImages.append(selectedImage ?? image)
            }
        }

        if let trailingEntry = trailingEntry {
            items.append(trailingEntry.item)
            tabDisplayTitles.append(trailingEntry.title)
            tabBaseImages.append(trailingEntry.image)
            tabSelectedImages.append(trailingEntry.selectedImage)
        }
        if let selectedId = selectedId {
            selectedIndex = items.firstIndex(where: { item in
                tabIds.indices.contains(item.tag) && tabIds[item.tag] == selectedId
            })
        }

        return (items, selectedIndex)
    }

    private func makeFloatingTabBarItems(
        _ tabs: [[String: Any]],
        selectedId: String?,
        icons: Bool
    ) -> ([NativeNavigationFloatingTabItem], Int?) {
        var selectedIndex: Int?
        var items: [NativeNavigationFloatingTabItem] = []

        for (sourceIndex, tab) in tabs.enumerated() {
            let id = tab["id"] as? String ?? "tab-\(sourceIndex)"
            let isHidden = tab["hidden"] as? Bool ?? false
            if isHidden && id != selectedId {
                continue
            }

            let visibleIndex = items.count
            let title = tab["title"] as? String ?? ""
            let image = icons ? self.image(from: tab["icon"] as? [String: Any]) : nil
            let selectedImage = icons ? self.image(from: tab["selectedIcon"] as? [String: Any]) : nil
            let role = (tab["role"] as? String)?.lowercased()
            let isDetachedTrailing = role == "search" || role == "prominent"
            if id == selectedId {
                selectedIndex = visibleIndex
            }
            items.append(NativeNavigationFloatingTabItem(
                id: id,
                title: title,
                accessibilityTitle: title.isEmpty ? id : title,
                image: image,
                selectedImage: selectedImage,
                badge: tab["badge"].map { String(describing: $0) },
                enabled: tab["enabled"] as? Bool ?? true,
                isDetachedTrailing: isDetachedTrailing,
                sourceIndex: sourceIndex
            ))
        }

        // Keep at most one detached trailing action and place it last so the
        // capsule + circular button layout matches the system Liquid Glass pattern.
        // Skip reordering for curve bars so center-item selection stays stable.
        if tabbarStyle.shape == .floating,
           let trailingIndex = items.lastIndex(where: { $0.isDetachedTrailing }) {
            let trailing = items.remove(at: trailingIndex)
            items.removeAll(where: { $0.isDetachedTrailing })
            items.append(trailing)
            if let selectedId = selectedId {
                selectedIndex = items.firstIndex(where: { $0.id == selectedId })
            }
        }

        return (items, selectedIndex)
    }

    private func tabTitle(
        _ title: String?,
        id: String,
        index: Int,
        selectedId: String?,
        labelVisibilityMode: String
    ) -> String? {
        let isSelected = id == selectedId || (selectedId == nil && index == 0)
        switch labelVisibilityMode {
        case "unlabeled":
            return nil
        case "selected":
            return isSelected ? title : nil
        case "auto":
            let compact = bridge?.viewController?.traitCollection.horizontalSizeClass == .compact
                || UIDevice.current.userInterfaceIdiom == .phone
            return compact && !isSelected ? nil : title
        default:
            return title
        }
    }

    private func image(from descriptor: [String: Any]?) -> UIImage? {
        guard let descriptor = descriptor else {
            return nil
        }
        let template = descriptor["template"] as? Bool ?? true
        if let svg = svgMarkup(from: descriptor),
           let image = SVGIconRenderer.render(svg: svg, size: iconSize(from: descriptor)) {
            return template ? image.withRenderingMode(.alwaysTemplate) : image
        }
        if let ios = descriptor["ios"] as? [String: Any] {
            if let symbol = ios["sfSymbol"] as? String, let image = UIImage(systemName: symbol) {
                return template ? image.withRenderingMode(.alwaysTemplate) : image
            }
            if let imageName = ios["image"] as? String, let image = UIImage(named: imageName) {
                return template ? image.withRenderingMode(.alwaysTemplate) : image
            }
        }
        if let svg = descriptor["svg"] as? String,
           let image = SVGIconRenderer.render(svg: svg, size: iconSize(from: descriptor)) {
            return template ? image.withRenderingMode(.alwaysTemplate) : image
        }
        if let src = descriptor["src"] as? String {
            if let svg = inlineSVG(from: src),
               let image = SVGIconRenderer.render(svg: svg, size: iconSize(from: descriptor)) {
                return template ? image.withRenderingMode(.alwaysTemplate) : image
            }
            if let image = UIImage(named: src) {
                return template ? image.withRenderingMode(.alwaysTemplate) : image
            }
        }
        return nil
    }

    private func svgMarkup(from descriptor: [String: Any]) -> String? {
        if let ios = descriptor["ios"] as? [String: Any],
           let svg = ios["svg"] as? String {
            return svg
        }
        if let svg = descriptor["svg"] as? String {
            return svg
        }
        if let src = descriptor["src"] as? String {
            return inlineSVG(from: src)
        }
        return nil
    }

    private func inlineSVG(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<svg") {
            return trimmed
        }
        let prefix = "data:image/svg+xml"
        guard trimmed.lowercased().hasPrefix(prefix),
              let commaIndex = trimmed.firstIndex(of: ",") else {
            return nil
        }
        let payload = String(trimmed[trimmed.index(after: commaIndex)...])
        if trimmed[..<commaIndex].lowercased().contains(";base64") {
            guard payload.utf8.count <= nativeNavigationMaximumBase64SVGCharacters,
                  let data = Data(base64Encoded: payload),
                  data.count <= nativeNavigationMaximumDecodedSVGBytes else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
        guard payload.utf8.count <= nativeNavigationMaximumPercentEncodedSVGCharacters,
              let decoded = payload.removingPercentEncoding,
              decoded.utf8.count <= nativeNavigationMaximumDecodedSVGBytes else {
            return nil
        }
        return decoded
    }

    private func iconSize(from descriptor: [String: Any]) -> CGSize {
        let width = number(from: descriptor["width"]) ?? 24
        let height = number(from: descriptor["height"]) ?? width
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    private func number(from value: Any?) -> CGFloat? {
        if let value = value as? NSNumber {
            let number = CGFloat(truncating: value)
            return number.isFinite ? number : nil
        }
        if let value = value as? String,
           let number = Double(value),
           number.isFinite {
            return CGFloat(number)
        }
        return nil
    }

    private func transitionCornerRadius(_ value: Any?, fallback: Double) -> CGFloat? {
        let rawValue = value == nil ? fallback : nativeNavigationFiniteDouble(value)
        guard let rawValue,
              rawValue >= 0,
              rawValue <= Double(nativeNavigationMaximumLayoutDimension) else {
            return nil
        }
        return CGFloat(rawValue)
    }

    private func transitionRect(_ rawRect: [String: Any]?) -> CGRect? {
        guard let rawRect = rawRect,
              let width = number(from: rawRect["width"]),
              let height = number(from: rawRect["height"]) else {
            return nil
        }

        let rect = CGRect(
            x: number(from: rawRect["x"]) ?? 0,
            y: number(from: rawRect["y"]) ?? 0,
            width: width,
            height: height
        )
        return nativeNavigationIsSafeTransitionRect(rect) ? rect : nil
    }

    private func transitionFrame(for viewportRect: CGRect, webView: UIView) -> CGRect {
        guard let transitionContainer = webView.superview else {
            return CGRect(
                x: webView.frame.minX + viewportRect.minX,
                y: webView.frame.minY + viewportRect.minY,
                width: viewportRect.width,
                height: viewportRect.height
            )
        }
        return webView.convert(viewportRect, to: transitionContainer)
    }

    private func transitionSnapshotView(from webView: UIView, sourceRect: CGRect?) -> UIView {
        guard let sourceRect = sourceRect else {
            return webView.snapshotView(afterScreenUpdates: false) ?? nativeNavigationSnapshotPlaceholder(for: webView)
        }

        let cropRect = sourceRect.intersection(webView.bounds)
        guard cropRect.width > 0, cropRect.height > 0 else {
            return webView.snapshotView(afterScreenUpdates: false) ?? nativeNavigationSnapshotPlaceholder(for: webView)
        }

        let renderer = UIGraphicsImageRenderer(bounds: webView.bounds)
        let image = renderer.image { _ in
            webView.drawHierarchy(in: webView.bounds, afterScreenUpdates: false)
        }
        let scale = image.scale
        let scaledCropRect = CGRect(
            x: cropRect.minX * scale,
            y: cropRect.minY * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        ).integral

        guard let croppedImage = image.cgImage?.cropping(to: scaledCropRect) else {
            return webView.snapshotView(afterScreenUpdates: false) ?? nativeNavigationSnapshotPlaceholder(for: webView)
        }

        let imageView = UIImageView(
            image: UIImage(cgImage: croppedImage, scale: scale, orientation: image.imageOrientation)
        )
        imageView.contentMode = .scaleAspectFill
        return imageView
    }

    private func makeTabbarStyle(from options: NativeNavigationOptions) -> NativeNavigationTabbarStyleConfig {
        let rawStyle = options.object("style") ?? [:]
        let requestedShape = (rawStyle["shape"] as? String)?.lowercased()
        let shape: NativeNavigationTabbarShape = requestedShape == "curve" ? .curve : .floating
        let isCurve = shape == .curve
        let centerDiameter = boundedLayoutDimension(rawStyle["centerButtonDiameter"], fallback: 56, minimum: 44)
        let height = boundedLayoutDimension(rawStyle["height"], fallback: isCurve ? 76 : 64, minimum: 44)
        let centerLift = boundedLayoutDimension(
            rawStyle["centerButtonLift"],
            fallback: centerDiameter / 2,
            minimum: 0
        )
        let bottomGap = boundedLayoutDimension(rawStyle["bottomGap"], fallback: isCurve ? 0 : 10, minimum: 0)
        let horizontalMargin = boundedLayoutDimension(
            rawStyle["horizontalMargin"],
            fallback: isCurve ? 0 : 24,
            minimum: 0
        )
        let maxWidth = boundedLayoutDimension(rawStyle["maxWidth"], fallback: isCurve ? 0 : 430, minimum: 0)
        let cornerRadius = boundedLayoutDimension(
            rawStyle["cornerRadius"],
            fallback: isCurve ? 0 : height / 2,
            minimum: 0
        )
        let centerButtonColor = (rawStyle["centerButtonColor"] as? String)
            .flatMap { UIColor(nativeNavigationHexString: $0) }
        let centerButtonIconColor = (rawStyle["centerButtonIconColor"] as? String)
            .flatMap { UIColor(nativeNavigationHexString: $0) } ?? .white

        return NativeNavigationTabbarStyleConfig(
            shape: shape,
            height: height,
            horizontalMargin: horizontalMargin,
            maxWidth: maxWidth,
            bottomGap: bottomGap,
            cornerRadius: cornerRadius,
            centerItemId: rawStyle["centerItemId"] as? String,
            centerButtonDiameter: centerDiameter,
            centerButtonLift: centerLift,
            centerButtonColor: centerButtonColor,
            centerButtonIconColor: centerButtonIconColor
        )
    }

    private func boundedLayoutDimension(
        _ value: Any?,
        fallback: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        guard let value = number(from: value) else {
            return fallback
        }
        return min(max(value, minimum), nativeNavigationMaximumLayoutDimension)
    }

    private func glassIsEnabled(_ options: NativeNavigationOptions) -> Bool {
        (options.object("glass")?["effect"] as? String)?.lowercased() != "none"
    }

    private func glassSurfaceAlpha(_ options: NativeNavigationOptions) -> CGFloat {
        nativeNavigationClampedUnitInterval(options.object("glass")?["surfaceAlpha"], fallback: 0.62)
    }

    private func applyNavBarAppearance(navBar: UINavigationBar, options: NativeNavigationOptions) {
        let appearance = UINavigationBarAppearance()
        let transparent = options.bool("transparent", default: false)
        let usesLiquidGlass = usesSystemLiquidGlass && glassIsEnabled(options)
        navBlurView?.contentView.backgroundColor = .clear
        if usesLiquidGlass {
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil
            appearance.shadowColor = .clear
            navBlurView?.isHidden = true
        } else if transparent {
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
            if let effect = blurEffect(from: options.string("blurEffect"), fallback: .systemChromeMaterial) {
                navBlurView?.effect = effect
                navBlurView?.isHidden = false
                let tint = colorValue(options.object("colors")?["background"]) ?? .systemBackground
                navBlurView?.contentView.backgroundColor = tint.withAlphaComponent(glassSurfaceAlpha(options))
            } else {
                navBlurView?.isHidden = true
            }
        } else {
            appearance.configureWithDefaultBackground()
            navBlurView?.isHidden = true
        }

        if let colors = options.object("colors") {
            if let color = colorValue(colors["tint"]) {
                navBar.tintColor = color
            }
            if let color = colorValue(colors["foreground"]) {
                appearance.titleTextAttributes = [.foregroundColor: color]
                appearance.largeTitleTextAttributes = [.foregroundColor: color]
            }
            if let background = colors["background"] as? String,
               let color = colorValue(background),
               !usesLiquidGlass,
               !transparent {
                appearance.backgroundColor = color
            }
        }

        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
    }

    private func applyTabBarAppearance(tabBar: UITabBar, options: NativeNavigationOptions) {
        if usesSystemLiquidGlass {
            let standardAppearance = UITabBarAppearance()
            configureSystemTabBarStandardBackground(standardAppearance)
            applyTabBarColorOptions(standardAppearance, tabBar: tabBar, options: options)
            applyTabBarBadgeOptions(standardAppearance, options: options)

            let scrollEdgeAppearance = UITabBarAppearance()
            configureSystemTabBarScrollEdgeBackground(scrollEdgeAppearance, options: options)
            applyTabBarColorOptions(scrollEdgeAppearance, tabBar: tabBar, options: options)
            applyTabBarBadgeOptions(scrollEdgeAppearance, options: options)

            tabBar.isTranslucent = !prefersOpaqueTabBarBackground()
            tabBar.standardAppearance = standardAppearance
            tabBar.scrollEdgeAppearance = scrollEdgeAppearance
            tabBar.items?.forEach { item in
                item.standardAppearance = standardAppearance
                item.scrollEdgeAppearance = scrollEdgeAppearance
            }
            applyExperimentalBakedTintColors(tabBar: tabBar, options: options)
            return
        }

        let appearance = UITabBarAppearance()
        configureTabBarBackground(appearance, options: options)
        applyTabBarColorOptions(appearance, tabBar: tabBar, options: options)
        applyTabBarBadgeOptions(appearance, options: options)

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private func configureTabBarBackground(_ appearance: UITabBarAppearance, options: NativeNavigationOptions) {
        appearance.configureWithDefaultBackground()
        if prefersOpaqueTabBarBackground() {
            tabEffectView?.isHidden = true
            return
        }
        if let effect = blurEffect(from: options.string("blurEffect"), fallback: nil) {
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            tabEffectView?.effect = effect
            tabEffectView?.isHidden = false
        } else {
            tabEffectView?.isHidden = true
        }
    }

    private func configureSystemTabBarStandardBackground(_ appearance: UITabBarAppearance) {
        appearance.configureWithDefaultBackground()
    }

    private func configureSystemTabBarScrollEdgeBackground(
        _ appearance: UITabBarAppearance,
        options: NativeNavigationOptions
    ) {
        if options.bool("disableTransparentOnScrollEdge", default: false) || prefersOpaqueTabBarBackground() {
            configureSystemTabBarStandardBackground(appearance)
        } else {
            appearance.configureWithTransparentBackground()
            appearance.shadowColor = .clear
        }
    }

    private func applyTabBarColorOptions(
        _ appearance: UITabBarAppearance,
        tabBar: UITabBar,
        options: NativeNavigationOptions
    ) {
        if let colors = options.object("colors") {
            if let color = colorValue(colors["tint"]) {
                tabBar.tintColor = color
                applyTabItemAppearances(appearance) { itemAppearance in
                    itemAppearance.selected.iconColor = color
                    itemAppearance.selected.titleTextAttributes = [.foregroundColor: color]
                }
            }
            if let color = colorValue(colors["inactiveTint"]), !usesSystemLiquidGlass {
                tabBar.unselectedItemTintColor = color
                applyTabItemAppearances(appearance) { itemAppearance in
                    itemAppearance.normal.iconColor = color
                    itemAppearance.normal.titleTextAttributes = [.foregroundColor: color]
                }
            }
            if let color = colorValue(colors["badgeBackground"]) {
                applyTabItemAppearances(appearance) { itemAppearance in
                    itemAppearance.normal.badgeBackgroundColor = color
                    itemAppearance.selected.badgeBackgroundColor = color
                }
            }
            if let color = colorValue(colors["badgeText"]) {
                applyTabItemAppearances(appearance) { itemAppearance in
                    itemAppearance.normal.badgeTextAttributes = [.foregroundColor: color]
                    itemAppearance.selected.badgeTextAttributes = [.foregroundColor: color]
                }
            }
            if let background = colors["background"] as? String,
               let color = colorValue(background),
               !usesSystemLiquidGlass {
                appearance.backgroundColor = color
            }
        }
    }

    private func applyFloatingTabBarAppearance(
        tabBar: NativeNavigationFloatingTabBar,
        options: NativeNavigationOptions
    ) {
        let colors = options.object("colors")
        let backgroundTint = colorValue(colors?["background"])
        let backgroundColor = (backgroundTint ?? .systemBackground)
            .withAlphaComponent(tabbarStyle.shape == .curve ? 0.96 : 0.46)
        let tintSurfaceColor = (backgroundTint ?? .systemBackground)
            .withAlphaComponent(glassSurfaceAlpha(options))
        let glassEffect = glassIsEnabled(options) ? liquidGlassEffect() : nil
        let usesLiquidGlass = glassEffect != nil

        if tabbarStyle.shape == .curve || prefersOpaqueTabBarBackground() {
            tabEffectView?.isHidden = true
            trailingTabEffectView?.isHidden = true
        } else if let glass = glassEffect {
            tabEffectView?.effect = glass
            tabEffectView?.isHidden = false
            tabEffectView?.contentView.backgroundColor = tintSurfaceColor
            trailingTabEffectView?.effect = glassEffect ?? glass
            trailingTabEffectView?.contentView.backgroundColor = tintSurfaceColor
        } else if let effect = blurEffect(from: options.string("blurEffect"), fallback: .systemChromeMaterial) {
            tabEffectView?.effect = effect
            tabEffectView?.isHidden = false
            tabEffectView?.contentView.backgroundColor = tintSurfaceColor
            trailingTabEffectView?.effect = effect
            trailingTabEffectView?.contentView.backgroundColor = tintSurfaceColor
        } else {
            tabEffectView?.isHidden = true
            trailingTabEffectView?.isHidden = true
        }

        let opaqueBackground = backgroundTint ?? .systemBackground
        if prefersOpaqueTabBarBackground() {
            tabBar.backgroundFillColor = opaqueBackground
        } else if usesLiquidGlass {
            // Keep the hand-drawn fill clear so UIGlassEffect can show through.
            tabBar.backgroundFillColor = .clear
        } else {
            tabBar.backgroundFillColor = backgroundColor
        }
        if let color = colorValue(colors?["tint"]) {
            tabBar.selectedTintColor = color
        }
        if let color = colorValue(colors?["inactiveTint"]) {
            tabBar.inactiveTintColor = color
        }
        if let color = colorValue(options.string("badgeBackgroundColor")) ?? colorValue(colors?["badgeBackground"]) {
            tabBar.badgeBackgroundColor = color
        }
        if let color = colorValue(options.string("badgeTextColor")) ?? colorValue(colors?["badgeText"]) {
            tabBar.badgeTextColor = color
        }
        tabBar.setNeedsLayout()
    }

    private func applyTabBarBadgeOptions(_ appearance: UITabBarAppearance, options: NativeNavigationOptions) {
        if let color = colorValue(options.string("badgeBackgroundColor")) {
            applyTabItemAppearances(appearance) { itemAppearance in
                itemAppearance.normal.badgeBackgroundColor = color
                itemAppearance.selected.badgeBackgroundColor = color
            }
        }
        if let color = colorValue(options.string("badgeTextColor")) {
            applyTabItemAppearances(appearance) { itemAppearance in
                itemAppearance.normal.badgeTextAttributes = [.foregroundColor: color]
                itemAppearance.selected.badgeTextAttributes = [.foregroundColor: color]
            }
        }
    }

    private func applyExperimentalBakedTintColors(tabBar: UITabBar, options: NativeNavigationOptions) {
        guard shouldUseExperimentalBakedTintColors(options: options),
              let items = tabBar.items,
              let colors = options.object("colors") else {
            return
        }

        let activeTint = colorValue(colors["tint"]) ?? tabBar.tintColor ?? .tintColor
        let inactiveTint = colorValue(colors["inactiveTint"]) ?? tabBar.unselectedItemTintColor ?? .secondaryLabel
        guard colorValue(colors["tint"]) != nil || colorValue(colors["inactiveTint"]) != nil else {
            return
        }

        let labelVisibilityMode = tabLabelVisibilityMode(options: options)
        for (index, item) in items.enumerated() {
            let visibleTitle = tabDisplayTitles.indices.contains(index)
                ? (tabDisplayTitles[index] ?? "")
                : (item.title ?? "")
            let rawTitle = tabTitles.indices.contains(item.tag) ? tabTitles[item.tag] : visibleTitle
            let titles = bakedTintTitles(
                rawTitle: rawTitle,
                visibleTitle: visibleTitle,
                labelVisibilityMode: labelVisibilityMode
            )
            let icon = tabBaseImages.indices.contains(index) ? (tabBaseImages[index] ?? item.image) : item.image
            let selectedIcon = tabSelectedImages.indices.contains(index)
                ? (tabSelectedImages[index] ?? icon)
                : icon
            guard !titles.normal.isEmpty || !titles.selected.isEmpty || icon != nil || selectedIcon != nil else {
                continue
            }

            let accessibilityTitle = rawTitle.isEmpty ? visibleTitle : rawTitle
            if !accessibilityTitle.isEmpty {
                item.accessibilityLabel = accessibilityTitle
            }
            item.title = ""
            item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 100)
            item.image = makeTabBarItemImage(icon: icon, title: titles.normal, color: inactiveTint)
            item.selectedImage = makeTabBarItemImage(icon: selectedIcon, title: titles.selected, color: activeTint)
        }
    }

    private func shouldUseExperimentalBakedTintColors(options: NativeNavigationOptions) -> Bool {
        guard usesSystemLiquidGlass,
              options.bool("experimentalBakedTintColors", default: false) else {
            return false
        }

        return ["auto", "selected", "labeled", "unlabeled"].contains(tabLabelVisibilityMode(options: options))
    }

    private func tabLabelVisibilityMode(options: NativeNavigationOptions) -> String {
        let labels = options.bool("labels", default: true)
        return options.string("labelVisibilityMode") ?? (labels ? "labeled" : "unlabeled")
    }

    private func bakedTintTitles(
        rawTitle: String,
        visibleTitle: String,
        labelVisibilityMode: String
    ) -> (normal: String, selected: String) {
        switch labelVisibilityMode {
        case "unlabeled":
            return (normal: "", selected: "")
        case "selected":
            return (normal: "", selected: rawTitle)
        case "auto":
            let compact = bridge?.viewController?.traitCollection.horizontalSizeClass == .compact
                || UIDevice.current.userInterfaceIdiom == .phone
            return compact ? (normal: "", selected: rawTitle) : (normal: rawTitle, selected: rawTitle)
        case "labeled":
            return (normal: rawTitle, selected: rawTitle)
        default:
            return (normal: visibleTitle, selected: visibleTitle)
        }
    }

    private func makeTabBarItemImage(icon: UIImage?, title: String, color: UIColor) -> UIImage {
        let iconSize = CGSize(width: 27, height: 27)
        let font = UIFont.systemFont(ofSize: 10, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        let hasTitle = !title.isEmpty
        let titleSize = hasTitle ? (title as NSString).size(withAttributes: attributes) : .zero
        let imageSize = hasTitle
            ? CGSize(
                width: max(iconSize.width, ceil(titleSize.width)) + 8,
                height: iconSize.height + 3 + ceil(titleSize.height)
            )
            : iconSize
        // `UIScreen.main` is deprecated and wrong under multi-scene/multi-display;
        // `preferred()` resolves the scale from the current trait environment.
        let format = UIGraphicsImageRendererFormat.preferred()

        let image = UIGraphicsImageRenderer(size: imageSize, format: format).image { _ in
            if let icon {
                let tintedIcon = icon.withTintColor(color, renderingMode: .alwaysOriginal)
                let iconFrame = aspectFitRect(
                    size: tintedIcon.size,
                    in: CGRect(
                        x: (imageSize.width - iconSize.width) / 2,
                        y: 0,
                        width: iconSize.width,
                        height: iconSize.height
                    )
                )
                tintedIcon.draw(in: iconFrame)
            }
            if hasTitle {
                (title as NSString).draw(
                    in: CGRect(
                        x: 0,
                        y: iconSize.height + 3,
                        width: imageSize.width,
                        height: ceil(titleSize.height)
                    ),
                    withAttributes: attributes
                )
            }
        }

        return image.withRenderingMode(.alwaysOriginal)
    }

    private func aspectFitRect(size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return rect
        }

        let scale = min(rect.width / size.width, rect.height / size.height)
        let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.minX + (rect.width - fittedSize.width) / 2,
            y: rect.minY + (rect.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func applyTabItemAppearances(
        _ appearance: UITabBarAppearance,
        update: (UITabBarItemAppearance) -> Void
    ) {
        update(appearance.stackedLayoutAppearance)
        update(appearance.inlineLayoutAppearance)
        update(appearance.compactInlineLayoutAppearance)
    }

    private func layoutChrome() {
        guard let rootView = bridge?.viewController?.view else {
            return
        }
        rootView.layoutIfNeeded()
        let safeInsets = rootView.safeAreaInsets
        let width = rootView.bounds.width
        let height = rootView.bounds.height

        if let container = systemTabRootContainer {
            container.frame = rootView.bounds
            webView?.frame = container.bounds
        }

        if let container = navContainer {
            if let navBar {
                navbarHeight = nativeNavigationMeasuredNavigationBarHeight(navBar, width: width)
            }
            container.frame = CGRect(x: 0, y: 0, width: width, height: safeInsets.top + navbarHeight)
            navBlurView?.frame = container.bounds
            navBar?.frame = CGRect(x: 0, y: safeInsets.top, width: width, height: navbarHeight)
        }

        if let container = tabContainer {
            let availableWidth = max(0, width - (tabbarStyle.horizontalMargin * 2))
            let maxWidth = tabbarStyle.maxWidth > 0 ? tabbarStyle.maxWidth : availableWidth
            let hasDetachedTrailing = floatingTabBar?.hasDetachedTrailing == true && tabbarStyle.shape == .floating
            let trailingDiameter = tabbarStyle.height
            let trailingGap: CGFloat = 10
            let trailingExtra = hasDetachedTrailing ? trailingDiameter + trailingGap : 0
            let tabbarWidth = min(availableWidth, maxWidth + trailingExtra)
            let originX = (width - tabbarWidth) / 2
            let originY = height - safeInsets.bottom - tabbarStyle.bottomGap - tabbarStyle.totalHeight
            container.frame = CGRect(x: originX, y: originY, width: tabbarWidth, height: tabbarStyle.totalHeight)
            floatingTabBar?.frame = container.bounds
            floatingTabBar?.layer.cornerRadius = 0
            floatingTabBar?.layoutIfNeeded()

            let capsuleBounds = floatingTabBar?.capsuleBounds(in: container.bounds) ?? container.bounds
            container.layer.cornerRadius = tabbarStyle.shape == .floating ? tabbarStyle.cornerRadius : 0
            container.layer.shadowPath = NativeNavigationTabbarBackgroundPath
                .path(in: capsuleBounds, style: tabbarStyle).cgPath
            tabEffectView?.frame = capsuleBounds
            tabEffectView?.layer.cornerRadius = tabbarStyle.shape == .floating ? tabbarStyle.cornerRadius : 0
            tabEffectView?.isHidden = tabbarStyle.shape == .curve
                || prefersOpaqueTabBarBackground()
                || tabEffectView?.effect == nil

            if let trailingBounds = floatingTabBar?.trailingActionBounds(in: container.bounds),
               hasDetachedTrailing,
               !prefersOpaqueTabBarBackground() {
                trailingTabEffectView?.frame = trailingBounds
                trailingTabEffectView?.layer.cornerRadius = trailingBounds.height / 2
                trailingTabEffectView?.isHidden = trailingTabEffectView?.effect == nil
            } else {
                trailingTabEffectView?.isHidden = true
            }
        }

        if let tabBarController = tabBarController {
            tabBarController.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tabBarController.view.setNeedsLayout()
            tabBarController.view.layoutIfNeeded()
        }

        bringChromeToFront()
    }

    private func bringChromeToFront() {
        if isUsingSystemTabBar {
            if let navContainer = navContainer {
                bridge?.viewController?.view.bringSubviewToFront(navContainer)
            }
            bringLiftedWebViewOverlaysToFront()
            return
        }

        if let navContainer = navContainer {
            bridge?.viewController?.view.bringSubviewToFront(navContainer)
        }
        if let tabContainer = tabContainer {
            bridge?.viewController?.view.bringSubviewToFront(tabContainer)
        }
        if let tabBarController = tabBarController {
            bridge?.viewController?.view.bringSubviewToFront(tabBarController.view)
        }
    }

    private func colorValue(_ value: Any?) -> UIColor? {
        guard let value = value as? String else {
            return nil
        }

        switch value {
        case "ios:label", "system:label":
            return .label
        case "ios:secondaryLabel", "system:secondaryLabel":
            return .secondaryLabel
        case "ios:systemBackground", "system:background":
            return .systemBackground
        case "ios:secondarySystemBackground", "system:secondaryBackground":
            return .secondarySystemBackground
        default:
            return UIColor(nativeNavigationHexString: value)
        }
    }

    private func blurEffect(from value: String?, fallback: UIBlurEffect.Style?) -> UIBlurEffect? {
        guard value != "none" else {
            return nil
        }
        guard let style = blurStyle(from: value) ?? fallback else {
            return nil
        }
        return UIBlurEffect(style: style)
    }

    private func blurStyle(from value: String?) -> UIBlurEffect.Style? {
        guard let value = value else {
            return nil
        }
        return [
            "extraLight": .extraLight,
            "light": .light,
            "dark": .dark,
            "regular": .regular,
            "prominent": .prominent,
            "systemUltraThinMaterial": .systemUltraThinMaterial,
            "systemThinMaterial": .systemThinMaterial,
            "systemMaterial": .systemMaterial,
            "systemThickMaterial": .systemThickMaterial,
            "systemUltraThinMaterialLight": .systemUltraThinMaterialLight,
            "systemThinMaterialLight": .systemThinMaterialLight,
            "systemMaterialLight": .systemMaterialLight,
            "systemThickMaterialLight": .systemThickMaterialLight,
            "systemUltraThinMaterialDark": .systemUltraThinMaterialDark,
            "systemThinMaterialDark": .systemThinMaterialDark,
            "systemMaterialDark": .systemMaterialDark,
            "systemThickMaterialDark": .systemThickMaterialDark,
            "systemDefault": .systemChromeMaterial,
            "systemChromeMaterial": .systemChromeMaterial,
            "systemChromeMaterialLight": .systemChromeMaterialLight,
            "systemChromeMaterialDark": .systemChromeMaterialDark
        ][value]
    }

    private func liquidGlassEffect() -> UIVisualEffect? {
        guard usesSystemLiquidGlass,
              let effectClass = NSClassFromString("UIGlassEffect") else {
            return nil
        }

        let styleSelector = NSSelectorFromString("effectWithStyle:")
        if let method = class_getClassMethod(effectClass, styleSelector) {
            typealias EffectWithStyle = @convention(c) (AnyClass, Selector, Int) -> AnyObject?
            let factory = unsafeBitCast(method_getImplementation(method), to: EffectWithStyle.self)
            if let effect = factory(effectClass, styleSelector, 0) as? UIVisualEffect {
                return effect
            }
        }

        if let objectType = effectClass as? NSObject.Type {
            return objectType.init() as? UIVisualEffect
        }

        return nil
    }

    private func configureGlassBarButtonItem(_ item: UIBarButtonItem, id: String) {
        guard #available(iOS 26.0, *) else {
            return
        }

        // Keep older SDK builds working while adopting the native iOS 26 bar
        // button Liquid Glass grouping APIs when the runtime exposes them.
        let object = item as NSObject
        if object.responds(to: NSSelectorFromString("setIdentifier:")) {
            object.setValue(id, forKey: "identifier")
        }
        if object.responds(to: NSSelectorFromString("setSharesBackground:")) {
            object.setValue(navbarUsesLiquidGlass, forKey: "sharesBackground")
        }
        if object.responds(to: NSSelectorFromString("setHidesSharedBackground:")) {
            object.setValue(!navbarUsesLiquidGlass, forKey: "hidesSharedBackground")
        }
    }

    private func currentInsets() -> [String: Any] {
        let safeInsets = bridge?.viewController?.view.safeAreaInsets ?? .zero
        let navHeight = isEnabled && navbarVisible ? navbarHeight + safeInsets.top : 0
        let nativeTabHeight = max(tabBar?.frame.height ?? 0, 49 + safeInsets.bottom)
        let customTabHeight = tabbarHeight + safeInsets.bottom + tabbarStyle.bottomGap
        let tabHeight = isEnabled && tabbarVisible ? (isUsingSystemTabBar ? nativeTabHeight : customTabHeight) : 0
        return [
            "top": navHeight,
            "right": safeInsets.right,
            "bottom": tabHeight,
            "left": safeInsets.left,
            "navbarHeight": navHeight,
            "tabbarHeight": tabHeight
        ]
    }

    private func insetsResult() -> [String: Any] {
        return ["insets": currentInsets()]
    }

    private func updateInsetsAndNotify() {
        layoutChrome()
        let insets = currentInsets()
        if contentInsetMode == "none" {
            let script = """
            (() => {
              const root = document.documentElement;
              root.style.removeProperty('--cap-native-navigation-top');
              root.style.removeProperty('--cap-native-navigation-right');
              root.style.removeProperty('--cap-native-navigation-bottom');
              root.style.removeProperty('--cap-native-navigation-left');
              root.style.removeProperty('--cap-native-navbar-height');
              root.style.removeProperty('--cap-native-tabbar-height');
            })();
            """
            bridge?.webView?.evaluateJavaScript(script)
            emitPluginEvent("safeAreaChanged", data: ["insets": insets])
            return
        }
        let top = insets["top"] as? CGFloat ?? 0
        let right = insets["right"] as? CGFloat ?? 0
        let bottom = insets["bottom"] as? CGFloat ?? 0
        let left = insets["left"] as? CGFloat ?? 0
        let navbar = insets["navbarHeight"] as? CGFloat ?? 0
        let tabbar = insets["tabbarHeight"] as? CGFloat ?? 0
        let script = """
        (() => {
          const root = document.documentElement;
          root.style.setProperty('--cap-native-navigation-top', '\(top)px');
          root.style.setProperty('--cap-native-navigation-right', '\(right)px');
          root.style.setProperty('--cap-native-navigation-bottom', '\(bottom)px');
          root.style.setProperty('--cap-native-navigation-left', '\(left)px');
          root.style.setProperty('--cap-native-navbar-height', '\(navbar)px');
          root.style.setProperty('--cap-native-tabbar-height', '\(tabbar)px');
        })();
        """
        bridge?.webView?.evaluateJavaScript(script)
        emitPluginEvent("safeAreaChanged", data: ["insets": insets])
    }

    private func emitPluginEvent(_ name: String, data: [String: Any]) {
        notifyListeners(name, data: data)
        let detail = jsonString(data)
        let script = """
        (() => {
          window.dispatchEvent(new CustomEvent('capNativeNavigation:\(name)', { detail: \(detail) }));
        })();
        """
        bridge?.webView?.evaluateJavaScript(script)
    }

    private func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length
