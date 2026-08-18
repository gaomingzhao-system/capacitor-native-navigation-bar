/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

import UIKit
import WebKit

func nativeNavigationSystemTabAdditionalSafeAreaBottom(
    systemSafeAreaBottom: CGFloat
) -> CGFloat {
    guard systemSafeAreaBottom.isFinite else {
        return 0
    }
    return -max(0, systemSafeAreaBottom)
}

func nativeNavigationApplySystemTabAdditionalSafeArea(
    systemSafeAreaBottom: CGFloat,
    to contentController: UIViewController
) {
    var insets = contentController.additionalSafeAreaInsets
    let bottom = nativeNavigationSystemTabAdditionalSafeAreaBottom(
        systemSafeAreaBottom: systemSafeAreaBottom
    )
    guard insets.bottom != bottom else {
        return
    }
    insets.bottom = bottom
    contentController.additionalSafeAreaInsets = insets
}

@available(iOS 26.0, *)
final class NativeNavigationSystemTabSafeAreaObserverView: UIView {
    weak var contentController: NativeNavigationTabContentController?

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
              contentController.tabBarController is NativeNavigationTabController else {
            return
        }
        let systemSafeAreaBottom = contentController.tabBarController?.view.safeAreaInsets.bottom ?? 0
        nativeNavigationApplySystemTabAdditionalSafeArea(
            systemSafeAreaBottom: systemSafeAreaBottom,
            to: contentController
        )
    }
}

extension NativeNavigationTabContentController {
    @discardableResult
    func host(webView: WKWebView) -> Bool {
        if #available(iOS 26.0, *) {
            prepareForSystemLiquidGlassHosting(webView: webView)
        }
        return host(webView: webView as UIView)
    }

    @available(iOS 26.0, *)
    private func prepareForSystemLiquidGlassHosting(webView: WKWebView) {
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        view.insetsLayoutMarginsFromSafeArea = false
        webView.insetsLayoutMarginsFromSafeArea = false

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
        observer.synchronize()
    }
}
