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

@available(iOS 26.0, *)
final class NativeNavigationSystemTabSafeAreaObserverView: UIView {
    weak var contentController: NativeNavigationTabContentController?
    private(set) var bottomSafeAreaCompensation: CGFloat = 0

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

        let nextCompensation = nativeNavigationSystemTabBottomSafeAreaCompensation(
            safeAreaBottom: contentController.view.safeAreaInsets.bottom,
            currentCompensation: bottomSafeAreaCompensation
        )
        guard abs(nextCompensation - bottomSafeAreaCompensation) > 0.5 else {
            return
        }

        bottomSafeAreaCompensation = nextCompensation
        var insets = contentController.additionalSafeAreaInsets
        insets.bottom = nextCompensation
        contentController.additionalSafeAreaInsets = insets
    }
}

extension NativeNavigationTabContentController {
    @discardableResult
    func host(webView: WKWebView) -> Bool {
        if #available(iOS 26.0, *) {
            installSystemTabSafeAreaObserver()
        }
        return host(webView: webView as UIView)
    }

    @available(iOS 26.0, *)
    private func installSystemTabSafeAreaObserver() {
        // The iOS 26 system UITabBarController adds its full bottom safe area to
        // each child. Cancel that native ownership so contentInsetMode remains the
        // only source of WebView content avoidance and Liquid Glass can overlay it.
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
