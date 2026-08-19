/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import UIKit
import WebKit

func nativeNavigationSystemTabBottomSafeAreaCompensation(
    safeAreaBottom: CGFloat,
    currentCompensation: CGFloat
) -> CGFloat {
    guard safeAreaBottom.isFinite,
          currentCompensation.isFinite else {
        return 0
    }
    // UIKit reports the already-compensated safe area after the first update.
    // Remove the previous negative inset to recover the original inherited value.
    let inheritedBottomInset = safeAreaBottom - currentCompensation
    return -max(0, inheritedBottomInset)
}

func nativeNavigationSystemTabExtendedContentFrame(
    currentFrame: CGRect,
    systemTabBounds: CGRect
) -> CGRect {
    let values = [
        currentFrame.minX,
        currentFrame.minY,
        currentFrame.width,
        currentFrame.height,
        systemTabBounds.minX,
        systemTabBounds.minY,
        systemTabBounds.width,
        systemTabBounds.height
    ]
    guard values.allSatisfy(\.isFinite),
          currentFrame.width >= 0,
          currentFrame.height >= 0,
          systemTabBounds.width >= 0,
          systemTabBounds.height >= 0 else {
        return currentFrame
    }

    let targetMaxY = max(currentFrame.maxY, systemTabBounds.maxY)
    guard targetMaxY > currentFrame.maxY else {
        return currentFrame
    }

    return CGRect(
        x: currentFrame.minX,
        y: currentFrame.minY,
        width: currentFrame.width,
        height: targetMaxY - currentFrame.minY
    )
}

func nativeNavigationSystemTabAppearanceHasOpaqueBackground(_ appearance: UITabBarAppearance) -> Bool {
    if appearance.backgroundEffect != nil {
        return true
    }
    if let backgroundColor = appearance.backgroundColor,
       backgroundColor.cgColor.alpha > 0.001 {
        return true
    }
    if let shadowColor = appearance.shadowColor,
       shadowColor.cgColor.alpha > 0.001 {
        return true
    }
    return false
}

func nativeNavigationSystemTabTransparentStandardAppearance(
    from source: UITabBarAppearance
) -> UITabBarAppearance {
    guard let appearance = source.copy() as? UITabBarAppearance else {
        return source
    }
    appearance.backgroundEffect = nil
    appearance.backgroundColor = .clear
    appearance.shadowColor = .clear
    return appearance
}

@available(iOS 26.0, *)
final class NativeNavigationSystemTabSafeAreaObserverView: UIView {
    weak var contentController: NativeNavigationTabContentController?
    weak var hostedWebView: WKWebView?
    private(set) var bottomSafeAreaCompensation: CGFloat = 0
    private var opaqueStandardAppearance: UITabBarAppearance?

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        synchronize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        synchronize()
    }

    func synchronize() {
        guard let contentController,
              let tabController = contentController.tabBarController as? NativeNavigationTabController else {
            return
        }

        synchronizeSystemTabBarBackground(tabController)

        let nextCompensation = nativeNavigationSystemTabBottomSafeAreaCompensation(
            safeAreaBottom: contentController.view.safeAreaInsets.bottom,
            currentCompensation: bottomSafeAreaCompensation
        )

        let contentView = contentController.view!
        contentView.clipsToBounds = false
        tabController.view.clipsToBounds = false

        var extendedFrame = contentView.frame
        if let contentContainer = contentView.superview {
            // UITabBarController may size its selected child only to the area
            // above the system tab bar. Extend that child to the controller's
            // physical bottom so the WKWebView can render behind Liquid Glass.
            contentContainer.clipsToBounds = false
            let systemTabBounds = tabController.view.convert(
                tabController.view.bounds,
                to: contentContainer
            )
            extendedFrame = nativeNavigationSystemTabExtendedContentFrame(
                currentFrame: contentView.frame,
                systemTabBounds: systemTabBounds
            )
        }

        UIView.performWithoutAnimation {
            if contentView.frame != extendedFrame {
                contentView.frame = extendedFrame
            }
            if let hostedWebView, hostedWebView.superview === contentView {
                hostedWebView.frame = contentView.bounds
            }
            if self.frame != contentView.bounds {
                self.frame = contentView.bounds
            }
        }

        guard abs(nextCompensation - bottomSafeAreaCompensation) > 0.5 else {
            return
        }

        bottomSafeAreaCompensation = nextCompensation
        var insets = contentController.additionalSafeAreaInsets
        insets.bottom = nextCompensation
        contentController.additionalSafeAreaInsets = insets
    }

    private func synchronizeSystemTabBarBackground(_ tabController: NativeNavigationTabController) {
        let tabBar = tabController.tabBar

        if UIAccessibility.isReduceTransparencyEnabled {
            if let opaqueStandardAppearance {
                tabBar.standardAppearance = opaqueStandardAppearance
                tabBar.items?.forEach { item in
                    item.standardAppearance = opaqueStandardAppearance
                }
                self.opaqueStandardAppearance = nil
            }
            tabBar.isTranslucent = false
            return
        }

        let currentAppearance = tabBar.standardAppearance
        if nativeNavigationSystemTabAppearanceHasOpaqueBackground(currentAppearance) {
            opaqueStandardAppearance = currentAppearance.copy() as? UITabBarAppearance
        }

        let transparentAppearance = nativeNavigationSystemTabTransparentStandardAppearance(
            from: currentAppearance
        )
        tabBar.standardAppearance = transparentAppearance
        tabBar.items?.forEach { item in
            item.standardAppearance = transparentAppearance
        }
        tabBar.isTranslucent = true
    }
}

extension NativeNavigationTabContentController {
    @discardableResult
    func host(webView: WKWebView) -> Bool {
        guard host(webView: webView as UIView) else {
            return false
        }

        if #available(iOS 26.0, *) {
            prepareForSystemLiquidGlassHosting(webView: webView)
        }
        return true
    }

    @available(iOS 26.0, *)
    private func prepareForSystemLiquidGlassHosting(webView: WKWebView) {
        // Extending only the safe-area layout guide does not enlarge the child
        // frame that UITabBarController owns. Extend both the child view and the
        // hosted WKWebView so rendering reaches the physical screen bottom.
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        view.insetsLayoutMarginsFromSafeArea = false
        view.clipsToBounds = false
        webView.insetsLayoutMarginsFromSafeArea = false
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let observer: NativeNavigationSystemTabSafeAreaObserverView
        if let existingObserver = view.subviews.first(where: {
            $0 is NativeNavigationSystemTabSafeAreaObserverView
        }) as? NativeNavigationSystemTabSafeAreaObserverView {
            observer = existingObserver
        } else {
            observer = NativeNavigationSystemTabSafeAreaObserverView(frame: view.bounds)
            observer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            observer.backgroundColor = .clear
            observer.isOpaque = false
            observer.isUserInteractionEnabled = false
            view.insertSubview(observer, at: 0)
        }

        observer.contentController = self
        observer.hostedWebView = webView
        observer.synchronize()

        // UIKit can recalculate the selected child frame after tab items are
        // installed. Run the normal tab-controller layout once, then reapply the
        // edge-to-edge frame using the settled hierarchy.
        tabBarController?.view.setNeedsLayout()
        tabBarController?.view.layoutIfNeeded()
        observer.synchronize()
    }
}
